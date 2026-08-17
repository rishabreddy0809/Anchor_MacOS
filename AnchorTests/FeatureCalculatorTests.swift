//
//  FeatureCalculatorTests.swift
//  AnchorTests
//
//  The vector the model reads, and the accumulators that build it.
//
//  Everything downstream of here — the score, the band, the colour on the
//  dashboard, the alert that pulls a teacher's attention across a room — is a
//  function of sixteen integers assembled in FeatureCalculator.swift. Two of
//  them cannot be measured at all: Zoom reports "muted *now*", and
//  StruggleSignalHistory integrates that into "seconds spent unmuted" one poll
//  at a time. Integration is where the interesting failures live, because they
//  are arithmetic rather than crashes: a laptop that slept through lunch, a
//  clock that stepped backwards, a hand held up across three polls. None of
//  those break a build. They just quietly hand the model a student who never
//  existed.
//
//  The other half of the file is about the difference between *zero* and
//  *unknown*. A nil mute reading is not an unmuted student; a camera the
//  teacher asked us not to score is not a camera that is off. The vector has no
//  way to say "missing", so those distinctions are carried in `observed`, and
//  the tests below pin them at every point where a benign default is
//  substituted for a measurement.
//

import XCTest
@testable import Anchor

// MARK: - Cross-poll accumulators

final class StruggleSignalHistoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Mirrors `StruggleSignalHistory.maximumSampleGap`, which is private. If
    /// this drifts from the production constant the clamp tests below stop
    /// testing the clamp, so they assert against the observable consequence
    /// too, not just this number.
    private let maximumSampleGap: TimeInterval = 300

    /// Mirrors the private `recencyTau`. Same caveat.
    private let recencyTau: Double = 300

    private func participant(
        muted: Bool? = nil,
        audioLevel: Int? = nil,
        handRaised: Bool? = nil
    ) -> ZoomParticipant {
        ZoomParticipant(
            id: "p1",
            name: "Ada",
            isInMeeting: true,
            isMuted: muted,
            handRaised: handRaised,
            audioLevel: audioLevel
        )
    }

    // MARK: First sighting

    func testFirstSightingObservesNothing() {
        // The poll that discovers a student says nothing about the time before
        // it. Crediting the interval since — there isn't one — would hand a
        // student who joined a second ago the engagement record of whoever the
        // clock happened to be measuring, and would let ObservationRamp declare
        // them warmed up before anything had been watched.
        let history = StruggleSignalHistory()
            .advanced(with: participant(muted: false, audioLevel: 50), now: now)

        XCTAssertEqual(history.observedSeconds, 0)
        XCTAssertEqual(history.unmutedSeconds, 0)
        XCTAssertEqual(history.talkingSeconds, 0)
        XCTAssertEqual(history.recentUnmutedSeconds, 0)
        XCTAssertEqual(history.lastSampledAt, now, "The next poll has to have a floor to measure from")
    }

    func testFirstSightingStillCountsAHandThatIsAlreadyUp() {
        // Hand raises are counted per edge, not per second, so unlike the
        // duration accumulators they are not gated on an elapsed interval. A
        // student holding their hand up when Anchor joins is raising it.
        let history = StruggleSignalHistory()
            .advanced(with: participant(handRaised: true), now: now)

        XCTAssertEqual(history.handRaiseCount, 1)
        XCTAssertEqual(history.lastEngagementAt, now)
    }

    func testSecondPollCreditsTheIntervalBetweenThem() {
        let first = StruggleSignalHistory()
            .advanced(with: participant(muted: false, audioLevel: 40), now: now)
        let second = first.advanced(
            with: participant(muted: false, audioLevel: 40),
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(second.observedSeconds, 30)
        XCTAssertEqual(second.unmutedSeconds, 30)
        XCTAssertEqual(second.talkingSeconds, 30)
    }

    // MARK: The sample gap clamp

    func testASleepingLaptopCannotCreditAnHourOfEngagement() {
        // The failure this exists for: the lid closes, polling stops, and an
        // hour later the first poll back reports a student who happens to be
        // unmuted. Without the clamp that single sample credits 3,600 seconds
        // of unmuted attention and 3,600 seconds of observation, which is both
        // a fabricated engagement record and enough observed time to take
        // ObservationRamp straight to full weight on evidence that was never
        // gathered.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now.addingTimeInterval(-3_600)

        let next = history.advanced(with: participant(muted: false, audioLevel: 70), now: now)

        XCTAssertEqual(next.unmutedSeconds, Int(maximumSampleGap))
        XCTAssertEqual(next.talkingSeconds, Int(maximumSampleGap))
        XCTAssertEqual(next.observedSeconds, Int(maximumSampleGap))
        XCTAssertLessThan(next.observedSeconds, 3_600, "The clamp is the whole point of this test")
    }

    func testStaleEngagementDoesNotSurviveASuspend() {
        // The counterpart to the clamp above, and it used to be wrong.
        //
        // Crediting is clamped so a sleeping laptop cannot invent an hour of
        // attention. Decay was reading that same clamped value, so an hour of
        // sleep decayed the counters by only e^-1 — leaving ~37% of the
        // pre-sleep figure — instead of e^-12, which is nothing. A student who
        // was talking before the lid closed still read as recently engaged
        // after it, and `EngagementRecovery` reads exactly that counter.
        //
        // Crediting answers "how much did they earn"; decay answers "how long
        // ago was that". An hour really was an hour.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now.addingTimeInterval(-3_600)
        history.recentTalkingSeconds = 200
        history.recentUnmutedSeconds = 200

        // Silent and muted on the first poll back, so nothing new is credited
        // and only the decay term moves the counters.
        let next = history.advanced(with: participant(muted: true, audioLevel: 0), now: now)

        XCTAssertLessThan(
            next.recentTalkingSeconds, 1,
            "An hour of sleep must decay recent talking effectively to zero"
        )
        XCTAssertLessThan(
            next.recentUnmutedSeconds, 1,
            "An hour of sleep must decay recent unmuted time effectively to zero"
        )

        // A poll at the clamp boundary still decays by exactly one tau, so the
        // fix has not simply thrown the clamp away.
        var atBoundary = StruggleSignalHistory()
        atBoundary.lastSampledAt = now.addingTimeInterval(-maximumSampleGap)
        atBoundary.recentTalkingSeconds = 200

        let stepped = atBoundary.advanced(with: participant(muted: true, audioLevel: 0), now: now)
        XCTAssertEqual(stepped.recentTalkingSeconds, 200 * exp(-1), accuracy: 0.001)
    }

    func testAClockThatStepsBackwardsCreditsNothingRatherThanSubtracting() {
        // NTP correction, or a poll delivered out of order. `max(0, …)` keeps
        // the gap non-negative; without it a backwards step would *decrement*
        // unmutedSeconds and observedSeconds, walking a student's record
        // backwards past zero and inverting the exponential decay below into
        // exponential growth.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now.addingTimeInterval(60)
        history.unmutedSeconds = 100
        history.observedSeconds = 100

        let next = history.advanced(with: participant(muted: false), now: now)

        XCTAssertEqual(next.unmutedSeconds, 100)
        XCTAssertEqual(next.observedSeconds, 100)
    }

    // MARK: Decay ordering

    func testTheIntervalJustObservedIsCreditedUndecayed() {
        // Decay-then-credit, not credit-then-decay. The ordering is one line in
        // the source and invisible in every other way, but reversing it makes
        // the seconds a student just spent unmuted arrive already discounted by
        // the length of the very interval they were measured over: five minutes
        // of continuous speech would be recorded as ~110 seconds of recent
        // speech, and the longer the poll interval the worse the under-count.
        // EngagementRecovery reads these counters, so the visible symptom is a
        // student who is talking right now failing to earn a recovery.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now.addingTimeInterval(-300)
        history.recentUnmutedSeconds = 200
        history.recentTalkingSeconds = 200

        let next = history.advanced(with: participant(muted: false, audioLevel: 60), now: now)

        let decayed = 200 * exp(-300 / recencyTau)
        XCTAssertEqual(next.recentUnmutedSeconds, decayed + 300, accuracy: 0.0001)
        XCTAssertEqual(next.recentTalkingSeconds, decayed + 300, accuracy: 0.0001)
        XCTAssertGreaterThan(
            next.recentUnmutedSeconds,
            300,
            "Seconds observed in this interval must not be discounted by this interval"
        )
    }

    func testOldEngagementFadesWhileTheStudentIsQuiet() {
        // The reason the `recent…` counters exist at all: the plain totals only
        // grow, so a student who spoke twice in the first five minutes reads as
        // engaged for the rest of the hour.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now.addingTimeInterval(-300)
        history.recentTalkingSeconds = 400

        let next = history.advanced(with: participant(muted: true, audioLevel: 0), now: now)

        XCTAssertEqual(next.recentTalkingSeconds, 400 * exp(-1), accuracy: 0.0001)
        XCTAssertEqual(next.talkingSeconds, 0, "The plain total is untouched — it never decays")
    }

    func testDecayIsMonotonicAcrossRepeatedQuietPolls() {
        var history = StruggleSignalHistory()
        history.lastSampledAt = now
        history.recentTalkingSeconds = 500

        var previous = history.recentTalkingSeconds
        for step in 1...10 {
            history = history.advanced(
                with: participant(muted: true, audioLevel: 0),
                now: now.addingTimeInterval(Double(step) * 30)
            )
            XCTAssertLessThan(history.recentTalkingSeconds, previous, "Went up while nobody spoke")
            previous = history.recentTalkingSeconds
        }
    }

    // MARK: Hand raises

    func testAHandHeldUpAcrossPollsIsOneRaise() {
        // Zoom reports the state, not the transition. Counting the state would
        // turn a student who leaves their hand up waiting to be called on into
        // the most engaged person in the class — and hand_raise_count feeds
        // both the model and confidence_level, so the error compounds.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now

        for step in 1...3 {
            history = history.advanced(
                with: participant(handRaised: true),
                now: now.addingTimeInterval(Double(step) * 30)
            )
        }

        XCTAssertEqual(history.handRaiseCount, 1)
        XCTAssertTrue(history.wasHandRaised)
    }

    func testAHeldHandKeepsCountingAsEngagement() {
        // Regression, and the bug this was written for was the wrong way round
        // in the way that matters most.
        //
        // handRaiseCount is edge-counted and should be. lastEngagementAt used
        // to share that edge condition, so a student who raised their hand and
        // waited stopped counting as engaged the instant the edge passed. Five
        // minutes later they aged out of EngagementDrift's grace period and
        // began accruing a drift penalty — with their hand still up. Anchor
        // would then tell the teacher to ask a direct question of the one
        // student already asking for one.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now

        // Ten minutes of a raised hand and nothing else: no speech, no chat.
        for step in 1...20 {
            history = history.advanced(
                with: participant(handRaised: true),
                now: now.addingTimeInterval(Double(step) * 30)
            )
        }

        XCTAssertEqual(history.handRaiseCount, 1, "Still one raise — the count stays edge-based")

        let lastPoll = now.addingTimeInterval(20 * 30)
        XCTAssertEqual(
            history.lastEngagementAt, lastPoll,
            "A hand that is still up is still engagement"
        )

        // The consequence, asserted through the layer that actually reads it.
        let drift = EngagementDrift(now: lastPoll).apply(to: 0.5, history: history)
        XCTAssertFalse(drift.didDrift, "A student with their hand up must never be drifting")
    }

    func testLoweringAndRaisingAgainIsASecondRaise() {
        var history = StruggleSignalHistory()
        history.lastSampledAt = now

        let states = [true, true, false, false, true]
        for (step, raised) in states.enumerated() {
            history = history.advanced(
                with: participant(handRaised: raised),
                now: now.addingTimeInterval(Double(step + 1) * 30)
            )
        }

        XCTAssertEqual(history.handRaiseCount, 2)
    }

    func testAnUnreportedHandIsNotALoweredHand() {
        // `handRaised` is nil on the REST path, where Zoom reports no
        // in-meeting state at all. Nil coalescing to false is correct for
        // counting — we cannot count an edge we did not see — but the point
        // being pinned is that it never *invents* one either.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now
        history.wasHandRaised = true
        history.handRaiseCount = 1

        let next = history.advanced(
            with: participant(handRaised: nil),
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(next.handRaiseCount, 1)
        XCTAssertFalse(next.wasHandRaised)
    }

    // MARK: Engagement recency

    func testSpeakingRefreshesTheEngagementClock() {
        // `lastEngagementAt` is what separates "went quiet" from "was never
        // audible", which is the gate EngagementDrift and EngagementRecovery
        // both hang off.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now

        let next = history.advanced(
            with: participant(muted: false, audioLevel: 15),
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(next.lastEngagementAt, now.addingTimeInterval(30))
    }

    func testBeingUnmutedAndSilentIsNotEngagement() {
        // An open mic in an empty room is not participation. If it counted,
        // every student on a call with no push-to-talk would be permanently
        // "recently engaged" and drift could never fire.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now

        let next = history.advanced(
            with: participant(muted: false, audioLevel: 0),
            now: now.addingTimeInterval(30)
        )

        XCTAssertNil(next.lastEngagementAt)
        XCTAssertEqual(next.unmutedSeconds, 30, "Still counts as unmuted time, just not as engagement")
    }

    func testAnUnreportedMicNeverCreditsUnmutedTime() {
        // `isMuted` is Optional precisely so a missing reading cannot be
        // mistaken for `false`. The comparison in `advanced` is
        // `isMuted == false`, not `!(isMuted ?? true)`, and this pins the
        // difference: on a REST-only connection every student would otherwise
        // accumulate a full session of fictional unmuted seconds.
        var history = StruggleSignalHistory()
        history.lastSampledAt = now

        let next = history.advanced(with: participant(muted: nil), now: now.addingTimeInterval(60))

        XCTAssertEqual(next.unmutedSeconds, 0)
        XCTAssertEqual(next.observedSeconds, 60, "Time still passed; we just learned nothing from it")
    }
}

// MARK: - Building the vector

final class FeatureCalculatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func participant(
        userID: String? = "u1",
        name: String = "Ada",
        muted: Bool? = nil,
        hasVideo: Bool? = nil,
        handRaised: Bool? = nil,
        speakingSeconds: Int? = nil,
        audioLevel: Int? = nil
    ) -> ZoomParticipant {
        ZoomParticipant(
            id: "p1",
            userID: userID,
            name: name,
            isInMeeting: true,
            isMuted: muted,
            hasVideo: hasVideo,
            handRaised: handRaised,
            speakingSeconds: speakingSeconds,
            audioLevel: audioLevel
        )
    }

    private func chat(_ text: String, from senderID: String? = "u1", named: String = "Ada") -> ZoomChat {
        ZoomChat(id: UUID().uuidString, senderID: senderID, senderName: named, message: text, timestamp: now)
    }

    // MARK: Missing readings are not zero readings

    func testAnUnreportedMicIsAssumedMutedAndNotRecordedAsObserved() {
        // Muted is the modal state in a class, so it is the least distorting
        // stand-in — but it must not be laundered into a measurement. If
        // `.mute` ended up in `observed`, confidence_level would average in a
        // timeUnmuted of zero that nobody ever measured and the fallback
        // scorer would weight a guess as evidence.
        let features = FeatureCalculator(now: now).calculateFeatures(from: participant(muted: nil))

        XCTAssertEqual(features.isMuted, 1)
        XCTAssertEqual(features.timeUnmuted, 0)
        XCTAssertFalse(features.observed.contains(.mute))
    }

    func testAnUnreportedCameraIsAssumedOn() {
        // The benign direction. An unknown camera must not invent a red flag.
        let features = FeatureCalculator(now: now).calculateFeatures(from: participant(hasVideo: nil))

        XCTAssertEqual(features.cameraOn, 1)
        XCTAssertFalse(features.observed.contains(.camera))
    }

    func testTurningCameraScoringOffTreatsAKnownCameraAsAnUnknownOne() {
        // The case the Settings toggle exists for: a class where cameras are
        // off by school policy or for bandwidth. Setting cameraOn = 0 while
        // dropping `.camera` from `observed` would be worse than either
        // extreme — the model would see the off camera and the confidence
        // estimate would refuse to account for it — so the two have to move
        // together.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(hasVideo: false),
            includesCamera: false
        )

        XCTAssertEqual(features.cameraOn, 1)
        XCTAssertFalse(features.observed.contains(.camera))
    }

    func testAReportedCameraIsUsedWhenTheSettingIsOn() {
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(hasVideo: false),
            includesCamera: true
        )

        XCTAssertEqual(features.cameraOn, 0)
        XCTAssertTrue(features.observed.contains(.camera))
    }

    // MARK: Speaking

    func testSpeakingFallsBackToTheIntegratedTotalWhenZoomReportsNone() {
        var history = StruggleSignalHistory()
        history.talkingSeconds = 45

        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(speakingSeconds: nil),
            history: history
        )

        XCTAssertEqual(features.speakingDuration, 45)
        XCTAssertTrue(features.observed.contains(.speaking))
    }

    func testAZeroFallbackIsNotAMeasurementOfSilence() {
        // The subtle half of the fallback. With no reported total and nothing
        // integrated yet, speakingDuration is zero because we have watched
        // nobody, not because they said nothing — so `.speaking` stays out of
        // `observed` and confidence_level declines to average in a zero it
        // cannot vouch for.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(speakingSeconds: nil),
            history: StruggleSignalHistory()
        )

        XCTAssertEqual(features.speakingDuration, 0)
        XCTAssertFalse(features.observed.contains(.speaking))
    }

    func testAReportedZeroSpeakingDurationIsAMeasurementOfSilence() {
        // The counterpart to the test above, and the pair is the whole point of
        // `observed`: both vectors carry speakingDuration = 0, and only the
        // flag says whether that zero was measured. Zoom reporting a total of
        // zero means we asked and the answer was none; a nil total with nothing
        // integrated means we never asked.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(speakingSeconds: 0)
        )

        XCTAssertEqual(features.speakingDuration, 0)
        XCTAssertTrue(features.observed.contains(.speaking))
    }

    func testANegativeReportedDurationIsFlooredAtZero() {
        // Every column is fed to CoreML as an Int64 in training units; a
        // negative duration is not a value the model has ever seen.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(speakingSeconds: -30)
        )

        XCTAssertEqual(features.speakingDuration, 0)
    }

    func testAudioLevelDrivesTheInstantaneousSpeakingFlag() {
        let calculator = FeatureCalculator(now: now)

        XCTAssertEqual(calculator.calculateFeatures(from: participant(audioLevel: 20)).isSpeaking, 1)
        XCTAssertEqual(calculator.calculateFeatures(from: participant(audioLevel: 0)).isSpeaking, 0)

        let unknown = calculator.calculateFeatures(from: participant(audioLevel: nil))
        XCTAssertEqual(unknown.isSpeaking, 0)
        XCTAssertFalse(unknown.observed.contains(.audio), "No feed is not a measurement of silence")
    }

    // MARK: Chat

    func testOnlyThisStudentsMessagesAreCounted() {
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(userID: "u1", name: "Ada"),
            chat: [
                chat("i am completely lost"),
                chat("everyone here is fine", from: "u2", named: "Grace")
            ]
        )

        XCTAssertEqual(features.messageLength, 4)
    }

    func testMessagesAreMatchedByNameWhenThereIsNoUserID() {
        // The REST path often has a display name and nothing else.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(userID: nil, name: "Ada"),
            chat: [chat("three words here", from: "someone-else", named: "Ada")]
        )

        XCTAssertEqual(features.messageLength, 3)
    }

    func testAChatFeedWithNothingFromThisStudentIsStillAMeasurement() {
        // "Said nothing in a chat we were reading" is real information about a
        // student; "we could not read the chat" is not. Both produce
        // messageLength = 0, and only `observed` tells them apart.
        let calculator = FeatureCalculator(now: now)

        let withFeed = calculator.calculateFeatures(
            from: participant(),
            chat: [chat("hello", from: "u2", named: "Grace")]
        )
        XCTAssertEqual(withFeed.messageLength, 0)
        XCTAssertTrue(withFeed.observed.contains(.chat))

        let withoutFeed = calculator.calculateFeatures(from: participant(), chat: [])
        XCTAssertFalse(withoutFeed.observed.contains(.chat))
    }

    func testAMessageFromAKnownDifferentSenderIsNotClaimedByAMatchingName() {
        // Name matching is the fallback for a missing id, not an override for
        // one that already answered. Two students who both go by "Ada" is
        // ordinary in a class, and attributing one's chat to the other moves
        // message_length, hesitation_count and has_question onto a student who
        // typed nothing — every chat-derived column at once.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(userID: "u1", name: "Ada"),
            chat: [chat("i am completely lost", from: "u2", named: "Ada")]
        )

        XCTAssertEqual(features.messageLength, 0)
        XCTAssertTrue(
            features.observed.contains(.chat),
            "The feed was still read — this student just didn't write in it"
        )
    }

    func testOneStudentOnTwoDevicesDoesNotHaveTheirChatCountedTwice() {
        // The everyday shape of the same bug, and the more likely one: a
        // student joins from a laptop and a phone, so Zoom reports two
        // participants sharing a display name and differing in nothing else the
        // matcher looks at. Both entries used to collect both messages, which
        // doubled the chat columns for the pair while making it look like two
        // students were struggling in identical words.
        let calculator = FeatureCalculator(now: now)
        let messages = [
            chat("i am lost", from: "u1", named: "Ada"),
            chat("still lost here", from: "u2", named: "Ada")
        ]

        let laptop = calculator.calculateFeatures(
            from: participant(userID: "u1", name: "Ada"),
            chat: messages
        )
        let phone = calculator.calculateFeatures(
            from: participant(userID: "u2", name: "Ada"),
            chat: messages
        )

        XCTAssertEqual(laptop.messageLength, 3)
        XCTAssertEqual(phone.messageLength, 3)
    }

    func testHesitationsAreCountedAcrossAllOfAStudentsMessages() {
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(),
            chat: [chat("um i think so"), chat("uh like maybe")]
        )

        // um, so, uh, like
        XCTAssertEqual(features.hesitationCount, 4)
    }

    func testQuestionsAreDetectedByMarkOrByOpener() {
        XCTAssertTrue(FeatureCalculator.isQuestion("what page are we on"))
        XCTAssertTrue(FeatureCalculator.isQuestion("Sounds right?"))
        XCTAssertTrue(FeatureCalculator.isQuestion("How does that work"))
        XCTAssertFalse(FeatureCalculator.isQuestion("sounds right"))
        XCTAssertFalse(FeatureCalculator.isQuestion(""))
    }

    func testAQuestionOpeningWithAFillerIsStillAQuestion() {
        // Students almost never open a chat question with the interrogative.
        // Matching only the literal first word read all of these as statements,
        // and the cost landed twice on the same student: has_question stayed 0
        // *and* hesitation_count rose for the very word that caused the miss.
        // Asking for help the way students actually ask scored as disengaged
        // and hesitant at once.
        XCTAssertTrue(FeatureCalculator.isQuestion("so how do we do part b"))
        XCTAssertTrue(FeatureCalculator.isQuestion("um what page are we on"))
        XCTAssertTrue(FeatureCalculator.isQuestion("like is this right"))

        // …without turning every filler-led sentence into a question.
        XCTAssertFalse(FeatureCalculator.isQuestion("so i finished it"))
        XCTAssertFalse(FeatureCalculator.isQuestion("um sounds right"))
    }

    func testAMessageOfNothingButFillersIsNotAQuestion() {
        // The degenerate case of skipping fillers: skip them all and there is
        // no opener left to test. Reaching past the end must read as "not a
        // question" rather than crediting one.
        XCTAssertFalse(FeatureCalculator.isQuestion("um uh like so"))
        XCTAssertFalse(FeatureCalculator.isQuestion("hmm"))
    }

    func testEmojiOnlyChatIsReadAsNoWordsAtAll() {
        // Known and deliberate, recorded because it is invisible and because
        // K-12 students react in emoji constantly. message_length counts words,
        // and the model was trained on a word count, so a thumbs-up is
        // indistinguishable from silence in a chat we are demonstrably reading.
        // `observed` still says the feed was live, which is what stops the
        // confidence estimate treating it as missing data — so the student
        // reads as present and quiet, not as unmeasured. Fixing it properly
        // means a column the model has never seen, i.e. a retrain.
        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(),
            chat: [chat("👍"), chat("🎉🎉")]
        )

        XCTAssertEqual(features.messageLength, 0)
        XCTAssertEqual(features.hasQuestion, 0)
        XCTAssertTrue(features.observed.contains(.chat))
    }

    func testEverydayUsesOfSoAndLikeAreCountedAsHesitations() {
        // Pinned because the proxy over-flags rather than under-flags, which is
        // the opposite of what is comfortable to assume. "like" and "so" are
        // ordinary English and this cannot tell the uses apart. The set is left
        // alone on purpose — it is the set the model was trained against, and
        // narrowing it here would move the column out from under the weights
        // without a retrain. The 15-point cap in confidenceLevel is what bounds
        // the damage in the meantime.
        XCTAssertEqual(FeatureCalculator.hesitationCount(in: "so i finished all the homework"), 1)
        XCTAssertEqual(FeatureCalculator.hesitationCount(in: "i like this class"), 1)
    }

    // MARK: Accumulators reaching the vector

    func testTheIntegratedAccumulatorsAreTheOnesTheModelSees() {
        // timeUnmuted and handRaiseCount have no instantaneous source. If the
        // history stopped being threaded through, both columns would read zero
        // for every student for the whole session and the model would see a
        // room where nobody ever unmuted or raised a hand.
        var history = StruggleSignalHistory()
        history.unmutedSeconds = 240
        history.handRaiseCount = 3

        let features = FeatureCalculator(now: now).calculateFeatures(
            from: participant(muted: false, handRaised: false),
            history: history
        )

        XCTAssertEqual(features.timeUnmuted, 240)
        XCTAssertEqual(features.handRaiseCount, 3)
        XCTAssertEqual(features.handRaised, 0, "The instantaneous flag is separate from the count")
    }
}

// MARK: - confidence_level

final class ConfidenceLevelTests: XCTestCase {

    /// A vector with every observable signal at a healthy value.
    private func engaged() -> StruggleFeatures {
        var features = StruggleFeatures()
        features.observed = [.mute, .audio, .speaking, .camera, .hand, .chat]
        features.speakingDuration = 120
        features.timeUnmuted = 300
        features.cameraOn = 1
        features.handRaiseCount = 2
        features.messageLength = 40
        features.hasQuestion = 1
        return features
    }

    /// The same signals, all observed, all absent.
    private func absent() -> StruggleFeatures {
        var features = StruggleFeatures()
        features.observed = [.mute, .audio, .speaking, .camera, .hand, .chat]
        return features
    }

    func testKnowingNothingScoresFiftyRatherThanZero() {
        // The difference between "no data" and "in trouble". Zero here is the
        // most alarming value the model's heaviest input can take, so a
        // participant we have learned nothing about would be presented as the
        // most disengaged student in the room.
        XCTAssertEqual(
            FeatureCalculator.confidenceLevel(for: StruggleFeatures(), meetingElapsed: 0),
            50
        )
    }

    func testTheProxySpansTheWholeScale() {
        // The scale matters more than the shape. This is the model's heaviest
        // input (−0.28 logits per point against a +4.47 intercept), so the
        // decision boundary sits near 16/100 — a proxy that bottomed out at,
        // say, 28 would never cross it and every student in every class would
        // score as coping. Reaching 0 and 100 is what makes the column usable
        // at all.
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: absent(), meetingElapsed: 0), 0)
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: engaged(), meetingElapsed: 0), 100)
    }

    func testOnlyObservedSignalsAreAveragedIn() {
        // A student with a camera on and nothing else measurable is at 100, not
        // at 20 — the unmeasured components are absent from the denominator
        // rather than scored as failures.
        var features = StruggleFeatures()
        features.observed = [.camera]
        features.cameraOn = 1

        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: features, meetingElapsed: 0), 100)
    }

    func testTheBarRisesWithTheLengthOfTheSession() {
        // Two minutes of speech is a lot in a ten-minute stand-up and very
        // little across a full period, so the expectation scales with elapsed
        // time rather than sitting at a fixed number of seconds.
        var features = StruggleFeatures()
        features.observed = [.audio, .speaking]
        features.speakingDuration = 60

        let short = FeatureCalculator.confidenceLevel(for: features, meetingElapsed: 0)
        let long = FeatureCalculator.confidenceLevel(for: features, meetingElapsed: 3_600)

        XCTAssertEqual(short, 100)
        XCTAssertEqual(long, 42)   // 60s against the 4%-of-3600s expectation
    }

    func testHesitationsOnlyCountWhereThereWasAFeedToCountThem() {
        var withFeed = engaged()
        withFeed.hesitationCount = 3
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: withFeed, meetingElapsed: 0), 91)

        // Same count, no chat feed. The number is a leftover, not a reading, so
        // it must not deduct anything.
        var withoutFeed = engaged()
        withoutFeed.observed.remove(.chat)
        withoutFeed.hesitationCount = 3
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: withoutFeed, meetingElapsed: 0), 100)
    }

    func testTheHesitationPenaltyIsCapped() {
        // A student who types "like" thirty times is nervous, not absent. Left
        // uncapped the deduction alone would drive a fully participating
        // student below the decision boundary.
        var features = engaged()
        features.hesitationCount = 50

        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: features, meetingElapsed: 0), 85)
    }

    func testAnAudioFeedEnrollsSpeakingDurationEvenWithNoIntegratedTotal() {
        // A genuine surprise between two files, pinned so nobody re-derives it.
        //
        // `testAZeroFallbackIsNotAMeasurementOfSilence` keeps `.speaking` out of
        // `observed` so an unmeasured zero cannot be averaged in — but the
        // speaking component here fires on `.speaking` OR `.audio`, and reads
        // speakingDuration either way. On the Meeting SDK path audioLevel is
        // always reported, so `.audio` is always set and that zero is averaged
        // in after all, on the heaviest component in the estimate.
        //
        // Correct, but only because of a layer that lives elsewhere: a student
        // whose duration is zero because nobody has watched them yet also has
        // observedSeconds near zero, and ObservationRamp scales their score to
        // nothing until that changes. Remove the ramp and this becomes a
        // first-poll false alarm on every student who joins.
        var heard = StruggleFeatures()
        heard.observed = [.audio]
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: heard, meetingElapsed: 0), 0)

        // With no mic feed at all the same vector is genuinely unknown.
        var unheard = StruggleFeatures()
        unheard.observed = []
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: unheard, meetingElapsed: 0), 50)
    }

    func testOneFloodedSignalCannotBuyBackTheOthers() {
        // Each component's share is clamped to 0...1 before it is weighted, so
        // a signal cannot earn more than its own weight. Without the clamp a
        // student who pasted three thousand words into chat would earn ten times
        // the chat weight and finish at 100 with their camera off and nobody
        // ever hearing them — the flood alone would paper over every other
        // column in the vector.
        var features = StruggleFeatures()
        features.observed = [.camera, .chat]
        features.cameraOn = 0
        features.messageLength = 3_000
        features.hasQuestion = 1

        let value = FeatureCalculator.confidenceLevel(for: features, meetingElapsed: 0)

        XCTAssertEqual(value, 56)
        XCTAssertLessThan(value, 100, "The clamp is the whole point of this test")
    }

    func testTheHesitationPenaltyIsReachedAtFiveFillers() {
        // The boundary of the cap the test above only probes from far away.
        // Five is not many for a student who types the way people talk, so this
        // is the realistic worst case rather than an extreme one.
        var four = engaged()
        four.hesitationCount = 4
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: four, meetingElapsed: 0), 88)

        var five = engaged()
        five.hesitationCount = 5
        XCTAssertEqual(FeatureCalculator.confidenceLevel(for: five, meetingElapsed: 0), 85)
    }

    func testRefreshUsesTheElapsedTimeStoredOnTheVector() {
        // `meetingElapsed` is carried on StruggleFeatures for exactly one
        // reason: attribution re-runs the prediction with a single feature
        // moved to its engaged baseline, and confidence_level has to be
        // re-derived at the same session length or the counterfactual vector
        // describes a different meeting.
        var features = StruggleFeatures()
        features.observed = [.audio, .speaking]
        features.speakingDuration = 60
        features.meetingElapsed = 3_600
        features.confidenceLevel = 99

        features.refreshConfidenceLevel()

        XCTAssertEqual(features.confidenceLevel, 42)
    }
}

// MARK: - Feature identity

final class StruggleFeatureIdentityTests: XCTestCase {

    func testEveryFeatureBelongsToExactlyOneHalfOfTheVector() {
        // A feature in neither list is invisible twice over: it is not required
        // of a candidate model, and it is not recognised as academic, so it
        // would silently never be checked for and never be filtered.
        XCTAssertEqual(StruggleFeature.allCases.count, 16)
        XCTAssertEqual(StruggleFeature.engagementFeatures.count, 11)
        XCTAssertEqual(StruggleFeature.academicFeatures.count, 5)

        let union = Set(StruggleFeature.engagementFeatures)
            .union(StruggleFeature.academicFeatures)
        XCTAssertEqual(union, Set(StruggleFeature.allCases))
        XCTAssertTrue(
            Set(StruggleFeature.engagementFeatures)
                .isDisjoint(with: StruggleFeature.academicFeatures)
        )
    }

    func testOnlyTheElevenZoomColumnsAreRequiredOfACandidateModel() {
        // Requiring all 16 would make StruggleDetectionService reject the model
        // that ships today and drop the whole app to heuristic scoring without
        // saying so. A retrained 16-feature model still satisfies a subset
        // check, so it drops in without a code change.
        XCTAssertEqual(
            StruggleFeatures.requiredFeatureNames,
            Set(StruggleFeature.engagementFeatures.map(\.rawValue))
        )
        XCTAssertTrue(
            StruggleFeatures.requiredFeatureNames
                .isDisjoint(with: StruggleFeatures.academicFeatureNames)
        )
        XCTAssertTrue(
            StruggleFeatures.requiredFeatureNames
                .isSubset(of: StruggleFeatures.allFeatureNames)
        )
    }

    func testModelInputsCarryOnlyWhatTheModelDeclares() {
        // This filtering is what makes `usesAcademicFeatures` an honest answer
        // to "is the model actually reading Classroom data?" — and that flag is
        // the switch that turns the rule-based AcademicEscalation off. If
        // undeclared columns were sent anyway the two layers could both be
        // live, double counting every missing assignment.
        var features = StruggleFeatures()
        features.missingAssignments = 4

        let elevenColumnModel = features.modelInputs(accepting: StruggleFeatures.requiredFeatureNames)
        XCTAssertEqual(elevenColumnModel.count, 11)
        XCTAssertNil(elevenColumnModel["missing_assignments"])

        let sixteenColumnModel = features.modelInputs(accepting: StruggleFeatures.allFeatureNames)
        XCTAssertEqual(sixteenColumnModel.count, 16)
        XCTAssertEqual(sixteenColumnModel["missing_assignments"], 4)
    }

    func testAModelDeclaringUnknownColumnsGetsNothingInvented() {
        let inputs = StruggleFeatures().modelInputs(accepting: ["is_muted", "sunspot_activity"])

        XCTAssertEqual(Set(inputs.keys), ["is_muted"])
    }

    func testExportCarriesEveryColumnEvenWhenTheModelIgnoresThem() {
        // Training data is the only path by which the academic columns can ever
        // become useful, so the exporter has to see all 16 regardless of what
        // today's model declares.
        XCTAssertEqual(StruggleFeatures().allInputs.count, 16)
    }

    func testOnlyConfidenceLevelIsDerived() {
        // Derived features are kept out of attribution: telling a teacher "the
        // score is high because the confidence number is low" only restates the
        // score. Marking a measured column as derived would hide a real reason.
        for feature in StruggleFeature.allCases {
            XCTAssertEqual(feature.isDerived, feature == .confidenceLevel, "\(feature.rawValue)")
        }
    }

    func testTheEngagedBaselineNeverMakesAHealthyValueWorse() {
        // Attribution re-runs the prediction with one feature moved to a
        // healthy value. A baseline that clamped *down* would report that a
        // student who spoke for ten minutes would be better off speaking for
        // ninety seconds, which reads as the speaking being the problem.
        XCTAssertEqual(StruggleFeature.speakingDuration.engagedBaseline(given: 600), 600)
        XCTAssertEqual(StruggleFeature.timeUnmuted.engagedBaseline(given: 600), 600)
        XCTAssertEqual(StruggleFeature.handRaiseCount.engagedBaseline(given: 7), 7)
        XCTAssertEqual(StruggleFeature.gradeAverage.engagedBaseline(given: 95), 95)

        // …and still lifts a genuinely poor one.
        XCTAssertEqual(StruggleFeature.speakingDuration.engagedBaseline(given: 0), 90)
        XCTAssertEqual(StruggleFeature.isMuted.engagedBaseline(given: 1), 0)
    }

    func testTheGradeTrendBaselineIsTheOffsetNoChangeValue() {
        // gradeTrend is stored +100 so the column stays a non-negative Int.
        // A baseline of 0 here would mean "grades down 100 points" — the
        // opposite of healthy — and attribution would report improving grades
        // as the thing holding a score up.
        XCTAssertEqual(StruggleFeature.gradeTrend.engagedBaseline(given: 88), 100)
        XCTAssertEqual(StruggleFeature.gradeTrend.engagedBaseline(given: 105), 105)
    }

    func testExplanationsStaySilentWhenAValueIsNotAConcern() {
        // These strings are shown to a teacher as reasons a score is high.
        // A reason that fires on a healthy value is worse than no reason.
        XCTAssertNil(StruggleFeature.isMuted.explanation(value: 0))
        XCTAssertNil(StruggleFeature.hesitationCount.explanation(value: 0))
        XCTAssertNil(StruggleFeature.missingAssignments.explanation(value: 0))
        XCTAssertNil(StruggleFeature.gradeAverage.explanation(value: 70))
        XCTAssertNotNil(StruggleFeature.gradeAverage.explanation(value: 69))
        XCTAssertNil(StruggleFeature.gradeTrend.explanation(value: 100))
        XCTAssertEqual(StruggleFeature.gradeTrend.explanation(value: 88), "Grades down 12%")
        XCTAssertNil(StruggleFeature.daysSinceSubmission.explanation(value: 6))
        XCTAssertNotNil(StruggleFeature.daysSinceSubmission.explanation(value: 7))
    }
}

// MARK: - Classroom half of the vector

final class ClassroomFeatureExtractionTests: XCTestCase {

    private func snapshot(
        missing: Int = 0,
        late: Int = 0,
        graded: Int = 0,
        average: Double? = nil,
        trend: Double? = nil,
        pastDue: Int = 0,
        lastSubmission: Date? = nil
    ) -> AcademicSnapshot {
        AcademicSnapshot(
            studentID: "s1",
            name: "Ada",
            email: "ada@example.edu",
            missingAssignments: (0..<missing).map {
                ClassroomAssignment(id: "a\($0)", courseID: "c1", title: "Worksheet \($0 + 1)")
            },
            lateCount: late,
            gradedCount: graded,
            averageGrade: average,
            gradeTrend: trend,
            lastSubmission: lastSubmission,
            pastDueCount: pastDue
        )
    }

    func testACourseWithNothingGradedIsNotAStudentWithNoGrades() {
        // The academic defaults are the values a student in good standing has,
        // so a class three weeks old with nothing marked cannot read as a class
        // full of failures. `.grades` is what records that the 80 is a default
        // rather than a measurement.
        let features = FeatureCalculator.extractClassroomFeatures(from: snapshot())

        XCTAssertEqual(features.gradeAverage, 80)
        XCTAssertEqual(features.gradeTrend, 100)
        XCTAssertEqual(features.daysSinceSubmission, 0)
        XCTAssertTrue(features.observed.contains(.academic))
        XCTAssertFalse(features.observed.contains(.grades))
    }

    func testGradesAreConvertedToWholePercent() {
        let features = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(graded: 4, average: 0.625)
        )

        XCTAssertEqual(features.gradeAverage, 63)
        XCTAssertTrue(features.observed.contains(.grades))
    }

    func testTheTrendIsStoredOffsetSoTheColumnStaysNonNegative() {
        // CreateML's tabular classifier is fed Int64 columns; a negative value
        // here would need a signed schema for one feature alone. 100 means no
        // change, so a falling trend has to land *below* 100 — an inverted sign
        // would tell the model that dropping grades are an improvement.
        XCTAssertEqual(
            FeatureCalculator.extractClassroomFeatures(from: snapshot(trend: -0.12)).gradeTrend,
            88
        )
        XCTAssertEqual(
            FeatureCalculator.extractClassroomFeatures(from: snapshot(trend: 0.05)).gradeTrend,
            105
        )
    }

    func testNothingSubmittedOnlyCountsOnceTheCourseHasSetWork() {
        // In a brand new course "nothing submitted" is the correct and
        // unremarkable state for every student in it.
        // Calendar arithmetic rather than 30 × 86,400: `daysSinceSubmission`
        // counts calendar days, and a DST transition inside the window would
        // otherwise make this test fail twice a year.
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        let quiet = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(pastDue: 0, lastSubmission: thirtyDaysAgo)
        )
        XCTAssertEqual(quiet.daysSinceSubmission, 0)

        let overdue = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(pastDue: 2, lastSubmission: thirtyDaysAgo)
        )
        XCTAssertEqual(overdue.daysSinceSubmission, 30)
    }

    func testAStudentWhoHasNeverSubmittedAnythingGetsTheStandInGap() {
        // No lastSubmission at all, in a course with past-due work: there is no
        // interval to measure, and zero would read as "submitted today".
        let features = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(pastDue: 3, lastSubmission: nil)
        )

        XCTAssertEqual(features.daysSinceSubmission, 30)
    }

    func testTheSubmissionGapIsMeasuredAgainstTheSuppliedClock() {
        let submitted = Date(timeIntervalSince1970: 1_700_000_000)
        let twelveDaysLater = Calendar.current.date(byAdding: .day, value: 12, to: submitted)!

        let features = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(pastDue: 2, lastSubmission: submitted),
            asOf: twelveDaysLater
        )

        XCTAssertEqual(features.daysSinceSubmission, 12)
    }

    func testTheCalculatorsOwnClockReachesTheSubmissionGap() {
        // The regression that matters, and it is the same defect
        // `daysSinceSubmission(asOf:)` was written to fix in AcademicEscalation,
        // repeated one layer up: FeatureCalculator takes an injected clock and
        // then called the extractor with no clock at all, which reached the
        // property that reads `Date()` directly.
        //
        // Live scoring barely noticed, because `now` is normally the wall clock
        // anyway. The export path is where it bites — `allInputs` exists to
        // write training rows, and rebuilding historical rows stamped every one
        // of them with the gap as of the day of the export instead of the gap on
        // the day the row happened. That is a column of pure hindsight fed back
        // into the model that reads it.
        let submitted = Date(timeIntervalSince1970: 1_700_000_000)
        let twelveDaysLater = Calendar.current.date(byAdding: .day, value: 12, to: submitted)!

        let features = FeatureCalculator(now: twelveDaysLater).calculateFeatures(
            from: ZoomParticipant(id: "p1", name: "Ada", isInMeeting: true),
            academic: snapshot(pastDue: 2, lastSubmission: submitted)
        )

        XCTAssertEqual(features.daysSinceSubmission, 12)
    }

    func testAMeasuredZeroGradeIsNotTheInGoodStandingDefault() {
        // 0.0 is the one average that has to survive the optional unwrap on its
        // own merits: a student failing everything and a course with nothing
        // marked must not arrive at the model as the same vector.
        let failing = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(graded: 5, average: 0.0)
        )
        XCTAssertEqual(failing.gradeAverage, 0)
        XCTAssertTrue(failing.observed.contains(.grades))

        let unmarked = FeatureCalculator.extractClassroomFeatures(from: snapshot())
        XCTAssertEqual(unmarked.gradeAverage, 80)
        XCTAssertFalse(unmarked.observed.contains(.grades))
    }

    func testFullMarksLandAtTheTopOfTheColumn() {
        // The upper bound holds because ClassroomSubmission.fraction clamps to
        // 0...1 at the source, which is what keeps extra credit — points above
        // an assignment's maximum, which Classroom does allow — from handing the
        // model a percentage it has never seen.
        let features = FeatureCalculator.extractClassroomFeatures(
            from: snapshot(graded: 5, average: 1.0)
        )

        XCTAssertEqual(features.gradeAverage, 100)
    }

    func testCountsPassStraightThrough() {
        let features = FeatureCalculator.extractClassroomFeatures(from: snapshot(missing: 3, late: 5))

        XCTAssertEqual(features.missingAssignments, 3)
        XCTAssertEqual(features.lateSubmissions, 5)
    }

    func testFoldingInClassroomDataKeepsTheZoomObservationFlags() {
        // The two data sources write to the same `observed` set from different
        // code paths. Assigning rather than unioning would erase whichever
        // arrived first, and every Zoom signal would silently stop counting for
        // any student Google Classroom happened to match.
        var features = StruggleFeatures()
        features.observed = [.mute, .camera]

        features.applyClassroomFeatures(
            FeatureCalculator.extractClassroomFeatures(from: snapshot(missing: 2, graded: 3, average: 0.5))
        )

        XCTAssertTrue(features.observed.contains(.mute))
        XCTAssertTrue(features.observed.contains(.camera))
        XCTAssertTrue(features.observed.contains(.academic))
        XCTAssertTrue(features.hasAcademicSignals)
        XCTAssertEqual(features.missingAssignments, 2)
    }

    func testAVectorWithNoClassroomMatchDoesNotClaimAcademicSignals() {
        let features = FeatureCalculator().calculateFeatures(
            from: ZoomParticipant(id: "p1", name: "Ada", isInMeeting: true),
            academic: nil
        )

        XCTAssertFalse(features.hasAcademicSignals)
        XCTAssertEqual(features.gradeAverage, 80, "Still the in-good-standing default, not a zero")
    }
}
