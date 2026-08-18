//
//  RetentionPolicyTests.swift
//  AnchorTests
//
//  The retention window is the one number in this product that is also a
//  published legal claim, and until now nothing tested it at all.
//
//  On 2026-08-18 the deployed privacy policy said session history is "kept
//  until you delete it" while the app had been deleting it at 120 days since
//  2026-08-17. The document a school's IT reviewer reads described a different
//  product from the one shipping, and the only reason anyone noticed was
//  someone fetching the live page by hand and reading it.
//
//  That is a two-sided failure — the app's number can drift, or the site's can —
//  and the last test in this file is the one that matters: it reads the actual
//  marketing-site source and asserts the two still agree. It is the same
//  cross-artifact pin as `SupportContactTests.testSupportAddressMatchesTheMarketingSite`,
//  written for the same reason: two copies of one fact, in repositories that
//  deploy separately, will drift, and the cheap moment to find out is here
//  rather than in front of a partner.
//
//  What this file does *not* cover, stated plainly so the coverage is not
//  overread: `pruneExpiredSessions` itself. Seeding `SessionArchive.sessions`
//  needs the whole begin/update/finalize flow — the property is `private(set)` —
//  so the deletion is exercised only by the manual pass in §9. What is pinned
//  here is the policy those mechanics implement.
//

import XCTest
@testable import Anchor

final class RetentionPolicyTests: XCTestCase {

    private typealias Window = SessionArchive.RetentionWindow

    // MARK: - The numbers themselves

    func testWindowLengths() {
        XCTAssertEqual(Window.term.days, 120)
        XCTAssertEqual(Window.year.days, 365)
        XCTAssertNil(Window.forever.days, "\"Keep everything\" must mean no cutoff, not a very large one")
    }

    /// A bounded default is the whole policy. An unbounded default with a
    /// setting nobody opens is the same as having no policy, which is what
    /// `SessionArchive`'s own header says.
    func testTheDefaultIsBounded() {
        let archive = SessionArchive(loadsFromDisk: false)
        XCTAssertEqual(archive.retention, .term, "the shipped default must delete something, eventually")
        XCTAssertNotNil(archive.retention.days)
    }

    func testEveryWindowIsOfferedToTheTeacher() {
        XCTAssertEqual(Set(Window.allCases.map(\.rawValue)), ["term", "year", "forever"])
    }

    // MARK: - Cutoff arithmetic

    /// The boundary is what a teacher would be told: a class that ended exactly
    /// 120 days ago is on the edge, 121 days is gone, 119 stays.
    func testCutoffIsExactlyTheWindowBack() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = try XCTUnwrap(Window.term.cutoff(from: now))

        XCTAssertEqual(now.timeIntervalSince(cutoff), 120 * 86_400, accuracy: 1)

        let day = 86_400.0
        XCTAssertLessThan(now.addingTimeInterval(-121 * day), cutoff, "121 days old should be past the window")
        XCTAssertGreaterThan(now.addingTimeInterval(-119 * day), cutoff, "119 days old should be inside it")
    }

    /// Nil is the signal `pruneExpiredSessions` returns early on. If this ever
    /// became a date, "keep everything" would quietly start deleting.
    func testForeverHasNoCutoffAtAnyPointInTime() {
        for stamp in [0.0, 1_800_000_000.0, 4_000_000_000.0] {
            XCTAssertNil(Window.forever.cutoff(from: Date(timeIntervalSince1970: stamp)))
        }
    }

    // MARK: - What Anchor says about itself

    /// The sentence shown in Settings has to carry the same number the code
    /// enforces. A window changed without its copy is a lie told in the app's
    /// own voice.
    func testEachPolicySentenceStatesItsOwnNumber() {
        XCTAssertTrue(Window.term.policySentence.contains("120"))
        XCTAssertTrue(Window.term.label.contains("120"))
        XCTAssertTrue(Window.year.policySentence.contains("365"))
        XCTAssertTrue(Window.year.label.contains("365"))

        let forever = Window.forever.policySentence
        XCTAssertFalse(forever.contains("120"), "\"keep everything\" must not quote a window")
        XCTAssertFalse(forever.contains("365"), "\"keep everything\" must not quote a window")
    }

    // MARK: - The cross-artifact pin

    /// The app and the marketing site state the same retention promise, and
    /// they deploy from different pipelines.
    ///
    /// This is the test that would have caught the 18 August contradiction:
    /// `privacy.tsx` had been updated, the app had been updated, and the
    /// *deployed* site had not — but the failure mode this guards is the
    /// commoner one, where someone changes `RetentionWindow.term` to 90 days
    /// and never touches the policy that promises 120.
    ///
    /// Reads the source rather than the live URL on purpose: a test that makes
    /// a network call fails on a plane, and would be measuring the deploy
    /// rather than the claim. Whether the deploy is current is a separate
    /// question, answered by the Git connection on the Vercel project.
    func testTheMarketingSiteQuotesTheSameWindowAsTheCode() throws {
        let privacy = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("website/landing/src/routes/privacy.tsx")

        let source = try String(contentsOf: privacy, encoding: .utf8)

        let days = try XCTUnwrap(Window.term.days)

        // Every day-count the policy states about deleting a class record must
        // be the window the code enforces.
        //
        // A bare `contains("120 days")` is not enough, and this test shipped
        // wrong for exactly that reason: the policy states the number twice
        // (§"Where the data lives" and §"Retention and deletion"), so changing
        // one and leaving the other still satisfied `contains` — the canary
        // that should have failed passed. Matching every occurrence is what
        // makes a half-finished edit fail.
        let pattern = try NSRegularExpression(pattern: #"(\d+) days after (?:the|each) class"#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let quoted: [Int] = pattern.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).flatMap { Int(source[$0]) }
        }

        XCTAssertFalse(
            quoted.isEmpty,
            "The privacy policy no longer states any retention period for a class record."
        )
        XCTAssertEqual(
            Set(quoted), [days],
            """
            The privacy policy quotes \(Set(quoted).sorted()) day(s) for deleting a class \
            record; the shipped default is \(days). Change every occurrence together — \
            a school's reviewer reads the policy, not the enum.
            """
        )

        XCTAssertFalse(
            source.contains("kept until you delete it"),
            """
            The privacy policy still carries the pre-retention wording. It said \
            this on the live site until 18 Aug 2026 while the app deleted at \
            \(days) days.
            """
        )
    }
}
