//
//  PollScheduleTests.swift
//  AnchorTests
//
//  What Anchor does when the connection goes wrong mid-lesson.
//
//  The failures this covers are the ordinary ones — a meeting dropping, a laptop
//  sleeping, school Wi-Fi blipping between rooms — and they share a property
//  that makes them easy to get wrong: none of them are the teacher's fault and
//  none of them need the teacher. Anchor's job is to retreat far enough that a
//  struggling connection can recover, come back on its own, and in the meantime
//  say something true about what it is doing.
//
//  Two things sit behind that. How long to wait, which is `PollSchedule` and is
//  pure arithmetic. And whether to keep waiting at all, which is the error
//  classification on `ZoomError` — the difference between "the Wi-Fi went" and
//  "your grant was revoked", where the first must never stop polling and the
//  second must never keep burning quota pretending it might recover.
//
//  What is deliberately not tested here is the loop itself. It has one job —
//  wait this long, then sync — and no seam to test it through that would not be
//  testing the seam. The arithmetic it consults is here instead.
//

import XCTest
@testable import Anchor

// MARK: - Steady cadence

final class PollScheduleSteadyStateTests: XCTestCase {

    func testTheChosenIntervalIsHonouredWhenTheSourceCanSustainIt() {
        // The bot reads participants from in-process SDK state, so there is no
        // rate limit to respect and a teacher asking for 10 seconds gets 10.
        let interval = PollSchedule.steadyInterval(
            floor: ZoomConfig.minimumBotPollInterval,
            chosen: 10
        )

        XCTAssertEqual(interval, 10)
    }

    func testTheRestFloorOverridesAFasterSetting() {
        // Zoom's Dashboard endpoints are heavily rate limited. Honouring a
        // 10-second picker here would spend the quota in minutes and start
        // returning 429s, so the floor wins and Settings explains why rather
        // than appearing to ignore the choice.
        let interval = PollSchedule.steadyInterval(
            floor: ZoomConfig.minimumPollInterval,
            chosen: 10
        )

        XCTAssertEqual(interval, ZoomConfig.minimumPollInterval)
        XCTAssertEqual(interval, 30)
    }

    func testASlowerSettingIsNeverSpedUpToTheFloor() {
        // The floor is a minimum wait, not a target. A teacher who picked five
        // minutes wants five minutes.
        XCTAssertEqual(
            PollSchedule.steadyInterval(floor: ZoomConfig.minimumPollInterval, chosen: 300),
            300
        )
    }
}

// MARK: - Backoff

final class PollScheduleBackoffTests: XCTestCase {

    /// No jitter, so the rung under test is the whole answer.
    private func rung(_ failures: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        PollSchedule.retryInterval(
            consecutiveFailures: failures,
            jitterFraction: 0,
            retryAfter: retryAfter
        )
    }

    func testTheLadderIsClimbedOneFailureAtATime() {
        // A single blip should cost fifteen seconds, not five minutes. The
        // ladder exists so a connection that recovers immediately is barely
        // interrupted, while one that is genuinely down is left alone.
        XCTAssertEqual(rung(1), 15)
        XCTAssertEqual(rung(2), 30)
        XCTAssertEqual(rung(3), 60)
        XCTAssertEqual(rung(4), 120)
        XCTAssertEqual(rung(5), 300)
    }

    func testTheLadderHoldsAtItsTopRatherThanGrowingForever() {
        // An outage lasting the whole lesson must settle at five minutes, not
        // walk off the end of the array or drift toward never retrying.
        XCTAssertEqual(rung(6), 300)
        XCTAssertEqual(rung(50), 300)
        XCTAssertEqual(rung(10_000), 300)
    }

    func testAFailureCountBelowOneStillProducesTheFirstRung() {
        // Defensive: nothing should ask for a retry interval without a failure,
        // but answering zero would turn a retreat into a tight loop against a
        // service that is already unhappy.
        XCTAssertEqual(rung(0), 15)
        XCTAssertEqual(rung(-3), 15)
    }

    func testJitterOnlyEverAddsAndIsBoundedByItsSpread() {
        // Jitter keeps several clients that failed on the same outage from
        // returning in lockstep. It must not be able to pull a wait *below* its
        // rung, which would defeat the backoff it is decorating.
        let base: TimeInterval = 15

        XCTAssertEqual(PollSchedule.retryInterval(consecutiveFailures: 1, jitterFraction: 0), base)
        XCTAssertEqual(
            PollSchedule.retryInterval(consecutiveFailures: 1, jitterFraction: 1),
            base + base * PollSchedule.jitterSpread
        )

        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
            let interval = PollSchedule.retryInterval(
                consecutiveFailures: 1,
                jitterFraction: fraction
            )
            XCTAssertGreaterThanOrEqual(interval, base)
            XCTAssertLessThanOrEqual(interval, base * (1 + PollSchedule.jitterSpread))
        }
    }

    func testAnOutOfRangeJitterFractionIsClamped() {
        // The caller draws this, and a caller that drew it wrong must not be
        // able to produce a negative wait or an unbounded one.
        XCTAssertEqual(PollSchedule.retryInterval(consecutiveFailures: 1, jitterFraction: -5), 15)
        XCTAssertEqual(
            PollSchedule.retryInterval(consecutiveFailures: 1, jitterFraction: 99),
            15 + 15 * PollSchedule.jitterSpread
        )
    }

    // MARK: Retry-After

    func testZoomsOwnRetryAfterIsHonouredWhenItIsLongerThanTheRung() {
        // The defect this was written for. `rateLimited` has carried a
        // `retryAfter` since it was introduced and nothing ever read it, so a
        // 429 saying "wait two minutes" was answered fifteen seconds later —
        // earning another 429, walking the ladder up, and on some providers
        // extending the penalty. The loop dug itself in precisely when it needed
        // to stop.
        XCTAssertEqual(rung(1, retryAfter: 120), 120)
        XCTAssertEqual(rung(2, retryAfter: 90), 90)
    }

    func testTheLadderWinsWhenItIsTheMoreCautiousOfTheTwo() {
        // Taken as a floor, not an override. After five failures the ladder's
        // five minutes is the better answer, and a provider asking for two
        // seconds should not talk Anchor out of it.
        XCTAssertEqual(rung(5, retryAfter: 2), 300)
        XCTAssertEqual(rung(3, retryAfter: 10), 60)
    }

    func testAnAbsentOrNonsenseRetryAfterFallsBackToTheLadder() {
        // Most failures are not rate limits and carry nothing at all; a header
        // that arrives malformed must not be mistaken for an instruction.
        XCTAssertEqual(rung(1, retryAfter: nil), 15)
        XCTAssertEqual(rung(1, retryAfter: 0), 15)
        XCTAssertEqual(rung(1, retryAfter: -60), 15)
        XCTAssertEqual(rung(1, retryAfter: .infinity), 15)
        XCTAssertEqual(rung(1, retryAfter: .nan), 15)
    }

    func testAWildRetryAfterCannotParkALessonPastTheBell() {
        // A rate-limit header is trusted, but not unboundedly. Waiting out a
        // bogus twelve-hour value would end monitoring for the class without
        // ever reporting a failure; retrying four times an hour is more use to a
        // teacher than not retrying at all.
        XCTAssertEqual(rung(1, retryAfter: 43_200), PollSchedule.maximumInterval)
        XCTAssertEqual(PollSchedule.maximumInterval, 900)
    }

    func testTheLadderItselfNeverReachesTheCeiling() {
        // The cap is only reachable through a provider header. If the ladder
        // ever grew past it, the top rungs would silently flatten into one.
        for failures in 1...20 {
            XCTAssertLessThan(rung(failures), PollSchedule.maximumInterval)
        }
    }
}

// MARK: - Which failures are worth waiting out

final class ZoomErrorRecoveryClassificationTests: XCTestCase {

    func testTheEverydayInterruptionsNeverStopPolling() {
        // The whole point of the retry loop. A meeting that hasn't started, a
        // laptop that woke on a different network, a blip between classrooms —
        // none of these need the teacher, and stopping on any of them would mean
        // a dashboard that quietly never comes back.
        let transient: [ZoomError] = [
            .network("The Internet connection appears to be offline."),
            .rateLimited(retryAfter: 30),
            .noActiveMeeting,
            .meetingEnded,
            .server(status: 503, code: nil, message: "Service Unavailable")
        ]

        for error in transient {
            XCTAssertFalse(
                error.requiresUserAction,
                "\(error) must not stop the polling loop"
            )
        }
    }

    func testTerminalAuthProblemsStopPollingAndAskForTheTeacher() {
        // The opposite failure, and the reason the distinction exists: a revoked
        // grant will never fix itself, and retrying it every five minutes for an
        // hour burns quota to arrive exactly where it started.
        let terminal: [ZoomError] = [
            .missingCredentials,
            .missingSDKCredentials,
            .invalidCredentials(reason: "Invalid client_id or client_secret"),
            .notSignedIn,
            .missingOAuthClient,
            .authorizationExpired,
            .authorizationFailed("Zoom refused the sign-in."),
            .insufficientScope("meeting:read")
        ]

        for error in terminal {
            XCTAssertTrue(
                error.requiresUserAction,
                "\(error) will never fix itself and must stop the loop"
            )
        }
    }

    func testRetryAfterIsCarriedOnlyByARateLimit() {
        XCTAssertEqual(ZoomError.rateLimited(retryAfter: 120).retryAfterSeconds, 120)
        XCTAssertNil(ZoomError.rateLimited(retryAfter: nil).retryAfterSeconds)
        XCTAssertNil(ZoomError.network("offline").retryAfterSeconds)
        XCTAssertNil(ZoomError.meetingEnded.retryAfterSeconds)
    }

    func testAPlanLimitIsReportedWithoutEndingTheSession() {
        // A teacher on a plan without the participant scopes is not broken, and
        // must not be treated as such: Anchor keeps running on the signals the
        // plan does expose. This is the shape of the likely first pilot.
        XCTAssertFalse(ZoomError.planRequired("Business").requiresUserAction)
    }

    func testTheTwoClassificationsAreNotTheSameQuestion() {
        // `isRetryable` governs the participant-email refresh; the polling loop
        // branches on `requiresUserAction`. They disagree on purpose, and the
        // disagreement is the interesting part: a malformed response gives up
        // permanently in the email refresh, where it is a side feature, while
        // the main loop keeps going, because ending a lesson's monitoring over
        // one bad payload is the worse trade.
        XCTAssertFalse(ZoomError.decoding("bad payload").isRetryable)
        XCTAssertFalse(ZoomError.decoding("bad payload").requiresUserAction)

        // And where they agree, they agree for the same reason.
        XCTAssertTrue(ZoomError.network("offline").isRetryable)
        XCTAssertFalse(ZoomError.network("offline").requiresUserAction)
    }
}
