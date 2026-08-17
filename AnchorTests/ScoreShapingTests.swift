//
//  ScoreShapingTests.swift
//  AnchorTests
//
//  The two time-based adjustments applied after the model has spoken.
//
//  These are worth testing before anything else in Anchor. They are pure
//  functions of numbers and dates, they are the last thing to touch a score
//  before a teacher reads it, and — unlike the model — they are rules someone
//  can change by hand in an afternoon. A regression here is silent: the
//  dashboard still renders, every student still gets a number, and the number
//  is wrong.
//

import XCTest
@testable import Anchor

final class ObservationRampTests: XCTestCase {

    func testNothingIsKnownAtFirstSighting() {
        // The whole reason the ramp exists: minute zero of a class is
        // indistinguishable from a room full of disengaged students.
        XCTAssertEqual(ObservationRamp.factor(observedSeconds: 0), 0)
    }

    func testReachesFullWeightAtWarmUp() {
        let full = Int(ObservationRamp.warmUpSeconds)
        XCTAssertEqual(ObservationRamp.factor(observedSeconds: full), 1)
        XCTAssertFalse(ObservationRamp.isWarmingUp(observedSeconds: full))
    }

    func testRampIsLinearAcrossTheWarmUp() {
        let half = Int(ObservationRamp.warmUpSeconds / 2)
        XCTAssertEqual(ObservationRamp.factor(observedSeconds: half), 0.5, accuracy: 0.0001)
    }

    func testFactorNeverExceedsOne() {
        // A three-hour session must not scale scores to 18x.
        let long = Int(ObservationRamp.warmUpSeconds) * 18
        XCTAssertEqual(ObservationRamp.factor(observedSeconds: long), 1)
    }

    func testNegativeObservationClampsToZeroRatherThanInverting() {
        XCTAssertEqual(ObservationRamp.factor(observedSeconds: -600), 0)
    }

    func testWarmUpNoteAppearsOnlyWhileWarming() {
        XCTAssertNotNil(ObservationRamp.note(observedSeconds: 60))
        XCTAssertNil(ObservationRamp.note(observedSeconds: Int(ObservationRamp.warmUpSeconds)))
    }
}

final class EngagementDriftTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func history(lastEngagementSecondsAgo: TimeInterval?) -> StruggleSignalHistory {
        var history = StruggleSignalHistory()
        if let ago = lastEngagementSecondsAgo {
            history.lastEngagementAt = now.addingTimeInterval(-ago)
        }
        return history
    }

    func testStudentWhoWasNeverAudibleIsNotDrifted() {
        // Silence all hour is the model's problem. Drifting it here would
        // penalise the same silence twice.
        let result = EngagementDrift(now: now)
            .apply(to: 0.5, history: history(lastEngagementSecondsAgo: nil))

        XCTAssertEqual(result.adjustedScore, 0.5)
        XCTAssertFalse(result.didDrift)
        XCTAssertNil(result.quietSeconds)
    }

    func testSilenceInsideTheGracePeriodIsJustListening() {
        let result = EngagementDrift(now: now)
            .apply(to: 0.5, history: history(lastEngagementSecondsAgo: EngagementDrift.graceSeconds - 1))

        XCTAssertEqual(result.adjustedScore, 0.5)
        XCTAssertFalse(result.didDrift)
    }

    func testDriftAccruesPerMinuteBeyondGrace() {
        // Two minutes past grace, at the documented rate.
        let quiet = EngagementDrift.graceSeconds + 120
        let result = EngagementDrift(now: now)
            .apply(to: 0.5, history: history(lastEngagementSecondsAgo: quiet))

        XCTAssertEqual(result.addedPoints, 2 * EngagementDrift.pointsPerMinute, accuracy: 0.0001)
        XCTAssertTrue(result.didDrift)
    }

    func testDriftIsCappedSoItCannotManufactureARedFlag() {
        // An hour of silence must not walk a green student into the red on its
        // own — that is what the model is for.
        let result = EngagementDrift(now: now)
            .apply(to: 0.5, history: history(lastEngagementSecondsAgo: 3_600))

        XCTAssertEqual(result.addedPoints, EngagementDrift.maximumAdjustment, accuracy: 0.0001)
    }

    func testAdjustedScoreIsClampedToOne() {
        let result = EngagementDrift(now: now)
            .apply(to: 0.98, history: history(lastEngagementSecondsAgo: 3_600))

        XCTAssertEqual(result.adjustedScore, 1.0, accuracy: 0.0001)
    }
}

final class EngagementRecoveryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func history(
        recentTalking: Double,
        lastEngagementSecondsAgo: TimeInterval?
    ) -> StruggleSignalHistory {
        var history = StruggleSignalHistory()
        history.recentTalkingSeconds = recentTalking
        if let ago = lastEngagementSecondsAgo {
            history.lastEngagementAt = now.addingTimeInterval(-ago)
        }
        return history
    }

    func testACoughIsNotParticipation() {
        let result = EngagementRecovery().apply(
            to: 0.6,
            history: history(recentTalking: EngagementRecovery.meaningfulSeconds - 1,
                             lastEngagementSecondsAgo: 10),
            now: now
        )

        XCTAssertEqual(result.adjustedScore, 0.6)
        XCTAssertFalse(result.didRecover)
    }

    func testSustainedSpeechEarnsTheFullReduction() {
        let result = EngagementRecovery().apply(
            to: 0.6,
            history: history(recentTalking: EngagementRecovery.fullCreditSeconds,
                             lastEngagementSecondsAgo: 10),
            now: now
        )

        XCTAssertEqual(result.removedPoints, EngagementRecovery.maximumReduction, accuracy: 0.0001)
        XCTAssertTrue(result.didRecover)
    }

    func testAdjustedScoreIsClampedToZero() {
        let result = EngagementRecovery().apply(
            to: 0.05,
            history: history(recentTalking: EngagementRecovery.fullCreditSeconds,
                             lastEngagementSecondsAgo: 10),
            now: now
        )

        XCTAssertEqual(result.adjustedScore, 0, accuracy: 0.0001)
    }

    // MARK: The boundary between the two layers

    func testRecoveryStopsWhereDriftStarts() {
        // The subtle one, and the reason the recency gate exists.
        //
        // `recentTalkingSeconds` decays with the same ~300s constant that drift
        // uses as its grace period, so a student who talked a lot keeps most of
        // a full credit for ten minutes after falling silent — while drift has
        // been penalising them since minute five. Without the gate the two
        // overlap for that whole window and recovery swamps the exact signal
        // drift exists to raise: someone silent for eight minutes reads as
        // recovering.
        //
        // Inside the grace period recovery owns the score; past it, drift does.
        // Nothing in the type system enforces that, so it is pinned here.
        let talkative = EngagementRecovery.fullCreditSeconds

        let insideGrace = EngagementRecovery().apply(
            to: 0.6,
            history: history(recentTalking: talkative,
                             lastEngagementSecondsAgo: EngagementDrift.graceSeconds - 1),
            now: now
        )
        XCTAssertTrue(insideGrace.didRecover, "Recovery owns the score inside the grace period")

        let pastGrace = EngagementRecovery().apply(
            to: 0.6,
            history: history(recentTalking: talkative,
                             lastEngagementSecondsAgo: EngagementDrift.graceSeconds + 1),
            now: now
        )
        XCTAssertFalse(pastGrace.didRecover, "Past the grace period drift owns the score, not recovery")
        XCTAssertEqual(pastGrace.adjustedScore, 0.6)
    }

    func testRecoveryAndDriftAreWorthTheSame() {
        // Coming back should be worth exactly what going quiet cost, or the
        // chain has a ratchet in it.
        XCTAssertEqual(EngagementRecovery.maximumReduction, EngagementDrift.maximumAdjustment)
    }

    func testNeverEngagedStudentCannotRecover() {
        let result = EngagementRecovery().apply(
            to: 0.6,
            history: history(recentTalking: EngagementRecovery.fullCreditSeconds,
                             lastEngagementSecondsAgo: nil),
            now: now
        )

        XCTAssertFalse(result.didRecover)
    }
}
