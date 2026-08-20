//
//  AcademicMatchTableTests.swift
//  AnchorTests
//
//  Pins which roster entry a Zoom participant resolves to, and — the part this
//  file was actually written for — what happens when the answer is "more than
//  one".
//
//  ── Why this file did not exist until 2026-08-20 ────────────────────────────
//
//  `AcademicMatchTable` decides whose grades appear under whose name, and had
//  **no test of any kind**. It was not overlooked for being trivial: it is the
//  single place in Anchor where being wrong shows one student's coursework
//  against another student's face, in front of a teacher who has no way to tell.
//
//  It went untested because it looked settled. The refusal rule reads correctly
//  and is correct — two students who normalise to the same name both drop out
//  rather than one being picked. What nothing checked was the *consequence* of
//  that refusal further down, and that is where the defect was.
//
//  ── The defect, which was in the copy rather than the rule ──────────────────
//
//  The table dropped both entries and said nothing about why, so downstream
//  "two students normalise alike" was indistinguishable from "nobody on this
//  roster is called that". `AcademicSection` therefore told the teacher the
//  display name matched no one and to have the student **"rename themselves in
//  Zoom to the name their school uses"** — which in the collision case is the
//  name they are already using, and is precisely why the match failed.
//  Following the advice cannot work. `ManualRosterLinks`, the control that does
//  work and sits in that same view, went unmentioned.
//
//  ── Why it is not an edge case ──────────────────────────────────────────────
//
//  Anchor dropped `classroom.profile.emails` on 2026-08-17, so `matchKey` is
//  nil on **every** roster entry on a normal install. Name matching stopped
//  being the fallback and became the ordinary path, and a class with two Emmas
//  became the ordinary shape of a roster that looks broken. The ship-checklist
//  says as much in §2 and calls it "the most likely way a pilot roster looks
//  broken, and it is by design" — but by-design and legible-to-a-teacher are
//  different claims, and only the first one was true.
//

import XCTest
@testable import Anchor

final class AcademicMatchTableTests: XCTestCase {

    private func student(_ id: String, _ name: String, email: String? = nil) -> ClassroomStudent {
        ClassroomStudent(id: id, name: name, email: email)
    }

    /// A roster with no addresses at all — the shape every install has had
    /// since the email scope was dropped, and the shape all the interesting
    /// cases live in.
    private let emmaClarke = ClassroomStudent(id: "s1", name: "Emma Clarke", email: nil)
    private let emmaClarkeTwin = ClassroomStudent(id: "s2", name: "emma  clarke.", email: nil)
    private let noahReed = ClassroomStudent(id: "s3", name: "Noah Reed", email: nil)

    // MARK: - The refusal itself

    func testAnUnambiguousNameMatches() {
        // The control. Without this every assertion below could pass because
        // name matching is broken outright rather than because it is being
        // refused for the right reason.
        let table = AcademicMatchTable(roster: [emmaClarke, noahReed], snapshots: [:])
        XCTAssertEqual(
            table.match(forIdentity: "name:Noah Reed", name: "Noah Reed")?.student.id,
            "s3",
            "A name only one student answers to stopped matching."
        )
    }

    func testTwoStudentsNormalisingAlikeBothDropOut() {
        // Neither is picked, in either direction. The rule is "refuse", not
        // "prefer the first one loaded" — and a roster's order is Google's,
        // not something Anchor controls or should depend on.
        let table = AcademicMatchTable(roster: [emmaClarke, emmaClarkeTwin], snapshots: [:])
        XCTAssertNil(
            table.match(forIdentity: "name:Emma Clarke", name: "Emma Clarke"),
            "A colliding name matched someone. That shows one student's grades "
            + "under another's name."
        )
        XCTAssertNil(
            AcademicMatchTable(roster: [emmaClarkeTwin, emmaClarke], snapshots: [:])
                .match(forIdentity: "name:Emma Clarke", name: "Emma Clarke"),
            "The refusal depends on roster order, so it is not a rule."
        )
    }

    // MARK: - Why the refusal happened, which is the new part

    func testACollisionNamesTheStudentsItRefused() {
        // The whole point. "Anchor found too many" and "Anchor found none" are
        // different facts with different fixes, and the teacher-facing copy
        // turns on being able to tell them apart.
        let table = AcademicMatchTable(roster: [emmaClarke, emmaClarkeTwin, noahReed], snapshots: [:])
        let twins = table.rosterTwins(forIdentity: "name:Emma Clarke", name: "Emma Clarke")

        XCTAssertEqual(
            Set(twins.map(\.id)), ["s1", "s2"],
            "A refused name did not report which students it was refused for, so the "
            + "teacher is told nobody answers to it — and asked to fix that by using "
            + "the name that collided."
        )
    }

    func testANameNobodyAnswersToReportsNoTwins() {
        // The other side of the same distinction, and the one that keeps the
        // new UI branch from swallowing the ordinary case. A non-empty result
        // must mean "too many", never "none".
        let table = AcademicMatchTable(roster: [emmaClarke, noahReed], snapshots: [:])
        XCTAssertTrue(
            table.rosterTwins(forIdentity: "name:Mia Fournier", name: "Mia Fournier").isEmpty,
            "A name nobody answers to was reported as a collision."
        )
    }

    func testASuccessfulMatchReportsNoTwins() {
        let table = AcademicMatchTable(roster: [emmaClarke, noahReed], snapshots: [:])
        XCTAssertTrue(
            table.rosterTwins(forIdentity: "name:Noah Reed", name: "Noah Reed").isEmpty,
            "A name that matched cleanly was also reported as ambiguous."
        )
    }

    func testTheSameStudentTwiceIsNotACollision() {
        // A roster that lists one student twice is a duplicate, not two people.
        // Reporting it as a name clash would send a teacher looking for a second
        // Emma who does not exist — and `byName` is right to keep matching her.
        let table = AcademicMatchTable(roster: [emmaClarke, emmaClarke], snapshots: [:])
        XCTAssertEqual(
            table.match(forIdentity: "name:Emma Clarke", name: "Emma Clarke")?.student.id,
            "s1",
            "The same student listed twice was treated as two people and refused."
        )
        XCTAssertTrue(
            table.rosterTwins(forIdentity: "name:Emma Clarke", name: "Emma Clarke").isEmpty,
            "A duplicated roster entry was reported to the teacher as a name clash."
        )
    }

    /// **This case exists because the canary above it did not fire.**
    ///
    /// Planting the obvious violation — dropping the duplicate-id fold from the
    /// collection loop — failed *nothing*, which meant the case that was
    /// supposed to catch it was passing for an unrelated reason: a roster of
    /// `[A, A]` never becomes ambiguous at all (the loop compares ids), so the
    /// collected list is never even read. The fold only matters where a
    /// duplicate sits *alongside* a genuine twin, and nothing reached that.
    ///
    /// Left as two cases rather than one edited case, because the weaker one
    /// still pins something real — that a plain duplicate keeps matching — and
    /// because a test that has been watched failing for the wrong reason is
    /// worth keeping visible.
    func testADuplicateAlongsideARealTwinIsNotListedTwice() {
        let table = AcademicMatchTable(
            roster: [emmaClarke, emmaClarke, emmaClarkeTwin],
            snapshots: [:]
        )
        let twins = table.rosterTwins(forIdentity: "name:Emma Clarke", name: "Emma Clarke")

        XCTAssertEqual(
            twins.count, 2,
            "The refused list repeats a student, so the teacher is told three people "
            + "share the name when two do — and one of the choices offered is the same "
            + "person twice."
        )
        XCTAssertEqual(Set(twins.map(\.id)), ["s1", "s2"])
    }

    // MARK: - What still outranks a collision

    func testAManualLinkBeatsACollision() {
        // This is the recovery path the new copy points at, so it had better
        // survive the thing it recovers from. A teacher who has already picked
        // must not keep being told the name is ambiguous.
        let table = AcademicMatchTable(
            roster: [emmaClarke, emmaClarkeTwin],
            snapshots: [:],
            manualLinks: ["name:emma clarke": "s2"]
        )
        let match = table.match(forIdentity: "name:Emma Clarke", name: "Emma Clarke")
        XCTAssertEqual(match?.student.id, "s2", "A recorded manual link was ignored.")
        XCTAssertEqual(match?.isManual, true, "A manual link lost its provenance.")
    }

    func testAVerifiedAddressBeatsACollision() {
        // Where addresses exist they decide, and a shared name cannot unmake
        // one. This is the pre-2026-08-17 world and a partner school with the
        // email scope granted is still in it.
        let a = student("s1", "Emma Clarke", email: "emma.clarke@school.org")
        let b = student("s2", "Emma  Clarke", email: "e.clarke@school.org")
        let table = AcademicMatchTable(roster: [a, b], snapshots: [:])
        XCTAssertEqual(
            table.match(forIdentity: "email:emma.clarke@school.org")?.student.id, "s1",
            "An address that identifies someone was overridden by a name collision."
        )
    }

    // MARK: - Vacuity guard

    func testTheTwoTestFixturesActuallyCollide() {
        // Without this, every collision case above passes for the wrong reason
        // the moment someone edits a fixture name and the two stop normalising
        // alike — the assertions are all `nil`/`isEmpty`, which an absent
        // collision satisfies just as well as a handled one.
        XCTAssertEqual(
            ClassroomNameKey.make(emmaClarke.name),
            ClassroomNameKey.make(emmaClarkeTwin.name),
            "The fixtures no longer normalise to the same key, so the collision tests "
            + "assert nothing."
        )
        XCTAssertNotEqual(
            emmaClarke.id, emmaClarkeTwin.id,
            "The fixtures share an id, so they are one student and never collided."
        )
    }
}
