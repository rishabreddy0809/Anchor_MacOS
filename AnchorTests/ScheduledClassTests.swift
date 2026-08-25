//
//  ScheduledClassTests.swift
//  AnchorTests
//
//  The calendar model, minus EventKit.
//
//  Everything here is arithmetic on two dates, which is exactly the part that
//  is wrong in a way nobody notices: an off-by-one on "is this happening now"
//  shows the wrong class on the dashboard, and both the right and the wrong
//  answer look plausible at a glance.
//
//  Deliberately no EventKit: authorization cannot be granted in a test, and a
//  test that needs a real calendar is one that gets disabled the first time it
//  is inconvenient.
//

import XCTest
@testable import Anchor

final class ScheduledClassTests: XCTestCase {

    private func makeClass(
        startMinutesFromNow: Int,
        durationMinutes: Int = 50,
        now: Date
    ) -> ScheduledClass {
        let start = now.addingTimeInterval(TimeInterval(startMinutesFromNow * 60))
        return ScheduledClass(
            id: "test",
            title: "AP Biology",
            start: start,
            end: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            calendarName: "Teaching"
        )
    }

    // MARK: - Is it happening

    func testAClassInProgressIsHappening() {
        let now = Date()
        let event = makeClass(startMinutesFromNow: -10, now: now)
        XCTAssertTrue(event.isHappening(at: now))
    }

    func testStartIsInclusiveAndEndIsNot() {
        // The boundary both ways round. Inclusive start means a class counts the
        // instant it begins; exclusive end means a 10:00–10:50 and a 10:50–11:40
        // never both report as happening, which would put two "Now" rows on the
        // dashboard for back-to-back periods — the normal shape of a timetable.
        let now = Date()
        let event = ScheduledClass(
            id: "t", title: "T",
            start: now,
            end: now.addingTimeInterval(3000),
            calendarName: "Teaching"
        )
        XCTAssertTrue(event.isHappening(at: now))
        XCTAssertFalse(event.isHappening(at: now.addingTimeInterval(3000)))
        XCTAssertTrue(event.isHappening(at: now.addingTimeInterval(2999)))
    }

    func testAFinishedClassIsNotHappening() {
        let now = Date()
        let event = makeClass(startMinutesFromNow: -120, now: now)
        XCTAssertFalse(event.isHappening(at: now))
    }

    func testAFutureClassIsNotHappening() {
        let now = Date()
        XCTAssertFalse(makeClass(startMinutesFromNow: 30, now: now).isHappening(at: now))
    }

    // MARK: - Countdown

    func testMinutesUntilStartCountsDown() {
        let now = Date()
        XCTAssertEqual(makeClass(startMinutesFromNow: 12, now: now).minutesUntilStart(from: now), 12)
    }

    func testMinutesUntilStartGoesNegativeOnceStarted() {
        // The schedule card reads this to decide between "in N min" and
        // "Starting". A value clamped at zero would leave a class that began
        // twenty minutes ago reading "in 0 min" forever.
        let now = Date()
        XCTAssertLessThan(makeClass(startMinutesFromNow: -20, now: now).minutesUntilStart(from: now), 0)
    }

    // MARK: - Display

    func testTimeRangeShowsBothEndsAndSeparatesThem() {
        // Not pinned to a literal: the formatter is locale- and 12/24-hour
        // dependent by design, and asserting "10:00 – 10:50" would fail on a
        // machine set to 24-hour time rather than catch a defect.
        let now = Date()
        let range = makeClass(startMinutesFromNow: 0, now: now).timeRange

        XCTAssertTrue(range.contains("–"), "expected an en dash between the two times")
        XCTAssertFalse(range.hasPrefix("–"))
        XCTAssertFalse(range.hasSuffix("–"))
        XCTAssertGreaterThan(range.split(separator: "–").count, 1)
    }

    func testEquatabilityIsByValue() {
        // The dashboard diffs these to decide what changed between refreshes.
        let now = Date()
        XCTAssertEqual(makeClass(startMinutesFromNow: 5, now: now), makeClass(startMinutesFromNow: 5, now: now))
        XCTAssertNotEqual(makeClass(startMinutesFromNow: 5, now: now), makeClass(startMinutesFromNow: 6, now: now))
    }
}
