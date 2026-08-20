//
//  RosterMatchabilityTests.swift
//  AnchorTests
//
//  Pins who Anchor reports as unmatchable, and — the scan at the bottom — that
//  no view looks an academic snapshot up under a key nothing is filed under.
//
//  ── The two defects this file was written against ───────────────────────────
//
//  Both are the same mistake seen from two sides, and both were introduced on
//  2026-08-17 by dropping the `classroom.profile.emails` scope. That change was
//  correct and is not being revisited: it took Google verification off the
//  critical path entirely. What it also did was make `ClassroomStudent.matchKey`
//  nil for **every** roster entry on a normal install, and two pieces of code
//  went on treating a nil `matchKey` as an exception.
//
//  **1. The count told every teacher their whole class was unmatchable.**
//  `unmatchableStudentCount` was `monitoredRoster.filter { $0.matchKey == nil }`,
//  which after 17 Aug is the entire roster. It drives a note in the Classroom
//  panel reading: *"N student(s) on this roster have no email address from
//  Google, so they can't be matched to a Zoom participant. Their coursework
//  won't affect any score."* Two false claims about every student, on the first
//  screen after connecting Classroom. Name matching is the ordinary path now,
//  it works, and their coursework does reach their score.
//
//  **2. One snapshot lookup was missed in the sweep.**
//  `CourseStudentHistoryView.snapshot` read `student?.matchKey.flatMap { … }`,
//  while snapshots are *filed* under `rosterKey` (`GoogleClassroomService`) —
//  which falls back to the normalised name and is, since 17 Aug, the only key
//  any of them are filed under. So that panel rendered empty on every normal
//  install with nothing on screen to explain it. The rest of that same file
//  already used `rosterKey`, which is what makes it a missed call site rather
//  than a misunderstanding — and why the fix worth having is a scan, not an
//  edit to one line.
//

import XCTest
@testable import Anchor

final class RosterMatchabilityTests: XCTestCase {

    private func student(_ id: String, _ name: String, email: String? = nil) -> ClassroomStudent {
        ClassroomStudent(id: id, name: name, email: email)
    }

    // MARK: - Who is actually unmatchable

    func testARosterWithNoAddressesIsNotUnmatchable() {
        // The shape of every roster on a normal install since 17 Aug, and the
        // exact input the old predicate answered "all of them" to.
        let roster = [
            student("s1", "Emma Clarke"),
            student("s2", "Noah Reed"),
            student("s3", "Mia Fournier")
        ]
        XCTAssertTrue(
            RosterMatchability.unmatchable(in: roster).isEmpty,
            "Every student on an ordinary roster was reported as unmatchable — which is "
            + "what the Classroom panel then tells the teacher, about their whole class."
        )
    }

    func testAnEntryWithNeitherAnAddressNorAUsableNameIsUnmatchable() {
        // What the note was always meant to describe. A name of punctuation
        // normalises to nothing, so there is no key of any kind.
        let roster = [student("s1", "Emma Clarke"), student("s2", "•••")]
        XCTAssertEqual(
            RosterMatchability.unmatchable(in: roster).map(\.id), ["s2"],
            "The rule no longer finds the case it exists for."
        )
    }

    func testAnAddressAloneIsEnough() {
        let roster = [student("s1", "", email: "e.clarke@school.org")]
        XCTAssertTrue(
            RosterMatchability.unmatchable(in: roster).isEmpty,
            "A student with a verified address was called unmatchable."
        )
    }

    // MARK: - Shared names, counted separately because the fix differs

    func testTwoStudentsSharingANormalisedNameAreBothReported() {
        // Both, not one. Anchor refuses the match in both directions, so a note
        // naming one of them would send the teacher looking for a single
        // problem student who does not exist.
        let roster = [
            student("s1", "Emma Clarke"),
            student("s2", "emma  clarke."),
            student("s3", "Noah Reed")
        ]
        XCTAssertEqual(
            Set(RosterMatchability.ambiguouslyNamed(in: roster).map(\.id)), ["s1", "s2"],
            "The shared-name count is wrong, so the note under-reports or names the wrong "
            + "students."
        )
    }

    func testAnAddressOutranksASharedName() {
        // The address decides and a shared name cannot unmake it, so these are
        // not awaiting a manual link and must not be counted as though they are.
        let roster = [
            student("s1", "Emma Clarke", email: "emma.clarke@school.org"),
            student("s2", "Emma Clarke", email: "e.clarke@school.org")
        ]
        XCTAssertTrue(
            RosterMatchability.ambiguouslyNamed(in: roster).isEmpty,
            "Students identified by address were reported as needing a manual link."
        )
    }

    func testADuplicatedRosterEntryIsNotASharedName() {
        // One student listed twice is a duplicate, not two people. Reporting it
        // sends a teacher hunting a second Emma who does not exist.
        let emma = student("s1", "Emma Clarke")
        XCTAssertTrue(
            RosterMatchability.ambiguouslyNamed(in: [emma, emma]).isEmpty,
            "A duplicated roster entry was reported to the teacher as a name clash."
        )
    }

    func testTheTwoCountsDoNotOverlap() {
        // They are shown as two separate sentences, so a student appearing in
        // both would be counted twice on screen. Unmatchable means no name key
        // at all; ambiguous requires one, so the sets are disjoint by
        // construction — this pins that they stay so.
        let roster = [
            student("s1", "Emma Clarke"),
            student("s2", "emma clarke"),
            student("s3", "•••"),
            student("s4", "Noah Reed", email: "n.reed@school.org")
        ]
        let a = Set(RosterMatchability.unmatchable(in: roster).map(\.id))
        let b = Set(RosterMatchability.ambiguouslyNamed(in: roster).map(\.id))
        XCTAssertEqual(a, ["s3"])
        XCTAssertEqual(b, ["s1", "s2"])
        XCTAssertTrue(a.isDisjoint(with: b), "A student is counted in both notes.")
    }

    // MARK: - The scan: nothing may look a snapshot up by matchKey

    // `AcademicSnapshot`s are filed under `rosterKey`, which is `matchKey`
    // falling back to the normalised name. Looking one up by `matchKey` finds
    // nothing on any install where Google withholds addresses — which is all of
    // them — and fails *silently*, as an empty panel.
    //
    // A scan rather than a fixed test because the failure is a missed call site.
    // `CourseStudentHistoryView` used `rosterKey` in one place and `matchKey` in
    // another, in the same file; the second was simply overlooked when the scope
    // was dropped. Nothing but a sweep catches the next one.

    private func swiftSources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("Anchor")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        var files: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    func testNoViewLooksUpASnapshotByMatchKey() throws {
        let sources = try swiftSources()
        for (name, text) in sources {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                guard trimmed.contains("matchKey") else { continue }
                // `rosterKey` and `nameMatchKey` both contain "matchKey" as a
                // substring; only the bare property is the mistake.
                let bare = trimmed
                    .replacingOccurrences(of: "nameMatchKey", with: "")
                    .replacingOccurrences(of: "rosterKey", with: "")
                guard bare.contains("matchKey") else { continue }
                XCTAssertFalse(
                    bare.contains("snapshot") || bare.contains("Snapshot"),
                    """
                    \(name) looks an academic snapshot up by `matchKey`. Snapshots are filed \
                    under `rosterKey`, so this finds nothing on any install where Google \
                    withholds roster addresses — which, since the scope was dropped on \
                    2026-08-17, is all of them. It fails as an empty panel, not an error.
                    Line: \(trimmed)
                    """
                )
            }
        }
    }

    func testTheScanIsLookingAtRealSource() throws {
        // Vacuity guard. Every assertion above is an `XCTAssertFalse` inside two
        // loops, and an empty file list satisfies all of them — which is exactly
        // how this scan would rot if the path ever stopped resolving.
        let sources = try swiftSources()
        XCTAssertGreaterThan(sources.count, 40, "The scan found almost no Swift files.")
        XCTAssertTrue(
            sources.contains { $0.name == "CourseStudentHistoryView.swift" },
            "The file the scan was written for is not being scanned."
        )
        XCTAssertTrue(
            sources.contains { $0.text.contains("rosterKey") },
            "No source mentions rosterKey, so the scan cannot be reading the real tree."
        )
    }
}
