//
//  FeatureCalculator.swift
//  Anchor
//
//  Turns a live Zoom participant into the 16-feature vector the Core ML model
//  was trained on.
//
//  The model is a CreateML tabular classifier whose inputs are all Int64, so
//  nothing here is normalised to 0...1 — the values are fed in the same units
//  the training data used (seconds, counts, 0/1 flags, 0...100).
//
//  Two of the features — time_unmuted and hand_raise_count — are *accumulators*
//  rather than instantaneous readings. Zoom reports only current state, so they
//  are integrated across polls by StruggleSignalHistory, which the mapper
//  carries forward on the Student the same way it carries trend and timeline.
//

import Foundation

// MARK: - Feature identity

/// The model's input columns. Raw values are the exact feature names in the
/// .mlmodel — do not rename them without retraining.
nonisolated enum StruggleFeature: String, CaseIterable, Hashable, Sendable {
    case isMuted = "is_muted"
    case timeUnmuted = "time_unmuted"
    case isSpeaking = "is_speaking"
    case speakingDuration = "speaking_duration"
    case cameraOn = "camera_on"
    case handRaised = "hand_raised"
    case handRaiseCount = "hand_raise_count"
    case messageLength = "message_length"
    case hesitationCount = "hesitation_count"
    case hasQuestion = "has_question"
    case confidenceLevel = "confidence_level"

    // MARK: Academic (Google Classroom)
    //
    // Added for the 16-feature retrain. The model shipped today was trained on
    // the 11 above and does not declare these inputs, so
    // `StruggleDetectionService` filters them out before predicting — they are
    // carried, exported for training, and shown to the teacher, but they cannot
    // move a score until a model that declares them is dropped in.
    case missingAssignments = "missing_assignments"
    case gradeAverage = "grade_average"
    case gradeTrend = "grade_trend"
    case daysSinceSubmission = "days_since_submission"
    case lateSubmissions = "late_submissions"

    /// The 11 Zoom features the current model was trained on. A candidate model
    /// must declare all of these to be usable at all.
    static let engagementFeatures: [StruggleFeature] = [
        .isMuted, .timeUnmuted, .isSpeaking, .speakingDuration, .cameraOn,
        .handRaised, .handRaiseCount, .messageLength, .hesitationCount,
        .hasQuestion, .confidenceLevel
    ]

    /// The 5 Google Classroom features. Optional for the model.
    static let academicFeatures: [StruggleFeature] = [
        .missingAssignments, .gradeAverage, .gradeTrend,
        .daysSinceSubmission, .lateSubmissions
    ]

    var isAcademic: Bool { Self.academicFeatures.contains(self) }

    /// True for features computed from the others rather than measured.
    /// Excluded from attribution: telling a teacher "the score is high because
    /// the confidence number is low" only restates the score.
    var isDerived: Bool { self == .confidenceLevel }

    /// The value this feature takes for a comfortably engaged student.
    ///
    /// Used for attribution: re-running the prediction with one feature moved to
    /// its engaged baseline shows how much of the score that feature is holding
    /// up. Values that are already at least as healthy as the baseline are left
    /// alone, so a student who spoke for 10 minutes is not "improved" down to 90
    /// seconds.
    func engagedBaseline(given current: Int) -> Int {
        switch self {
        case .isMuted:          0
        case .timeUnmuted:      max(current, 120)
        case .isSpeaking:       1
        case .speakingDuration: max(current, 90)
        case .cameraOn:         1
        case .handRaised:       1
        case .handRaiseCount:   max(current, 1)
        case .messageLength:    max(current, 25)
        case .hesitationCount:  0
        case .hasQuestion:      1
        case .confidenceLevel:  max(current, 85)

        case .missingAssignments:    0
        case .gradeAverage:          max(current, 80)
        // Stored offset by +100 (see StruggleFeatures.gradeTrend) so the column
        // stays a non-negative Int; 100 is "no change".
        case .gradeTrend:            max(current, 100)
        case .daysSinceSubmission:   0
        case .lateSubmissions:       0
        }
    }

    /// Teacher-readable phrasing for why this feature is pushing a score up.
    /// Returns nil when the value is not actually a concern.
    func explanation(value: Int, now: Date = Date()) -> String? {
        switch self {
        case .isMuted:
            value == 1 ? "Muted" : nil
        case .timeUnmuted:
            value == 0 ? "Never unmuted" : "Unmuted only \(Self.duration(value))"
        case .isSpeaking:
            value == 0 ? "Not speaking right now" : nil
        case .speakingDuration:
            value == 0 ? "Hasn't spoken this session" : "Spoke just \(Self.duration(value))"
        case .cameraOn:
            value == 0 ? "Camera off" : nil
        case .handRaised:
            value == 0 ? "Hand not raised" : nil
        case .handRaiseCount:
            value == 0 ? "No hand raises" : "Only \(value) hand raise\(value == 1 ? "" : "s")"
        case .messageLength:
            value == 0 ? "No chat messages" : "Short messages (\(value) words total)"
        case .hesitationCount:
            value > 0 ? "\(value) hesitation\(value == 1 ? "" : "s") (um, uh, like, so)" : nil
        case .hasQuestion:
            value == 0 ? "Hasn't asked a question" : nil
        case .confidenceLevel:
            "Low confidence signals (\(value)/100)"

        case .missingAssignments:
            value > 0 ? "\(value) missing assignment\(value == 1 ? "" : "s")" : nil
        case .gradeAverage:
            value < 70 ? "Grade average \(value)%" : nil
        case .gradeTrend:
            value < 100 ? "Grades down \(100 - value)%" : nil
        case .daysSinceSubmission:
            value >= 7 ? "Nothing submitted in \(value) days" : nil
        case .lateSubmissions:
            value > 0 ? "\(value) late submission\(value == 1 ? "" : "s")" : nil
        }
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            return "\(minutes) min"
        }
        return "\(seconds)s"
    }
}

/// Which features came from a real Zoom feed rather than a stand-in.
///
/// Zoom's REST API reports none of the in-meeting state, so on a REST-only
/// connection most of the vector is placeholder. Tracking that here lets the
/// score be calibrated down instead of presenting a guess as a measurement.
nonisolated struct ObservedSignals: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let mute     = ObservedSignals(rawValue: 1 << 0)
    static let camera   = ObservedSignals(rawValue: 1 << 1)
    static let hand     = ObservedSignals(rawValue: 1 << 2)
    static let speaking = ObservedSignals(rawValue: 1 << 3)
    static let audio    = ObservedSignals(rawValue: 1 << 4)
    static let chat     = ObservedSignals(rawValue: 1 << 5)
    /// Google Classroom matched this student and returned coursework.
    static let academic = ObservedSignals(rawValue: 1 << 6)
    /// The course has graded work, so `gradeAverage` means something.
    static let grades   = ObservedSignals(rawValue: 1 << 7)
}

// MARK: - Feature vector

nonisolated struct StruggleFeatures: Hashable, Sendable {
    var isMuted: Int = 0
    var timeUnmuted: Int = 0
    var isSpeaking: Int = 0
    var speakingDuration: Int = 0
    var cameraOn: Int = 0
    var handRaised: Int = 0
    var handRaiseCount: Int = 0
    var messageLength: Int = 0
    var hesitationCount: Int = 0
    var hasQuestion: Int = 0
    var confidenceLevel: Int = 50

    // MARK: Academic
    //
    // All default to the value a student in good standing would have, so a class
    // with no Classroom connection is never penalised for the absence. Whether
    // they were actually measured is recorded in `observed`.

    var missingAssignments: Int = 0
    /// Grade average as a whole percentage, 0...100.
    var gradeAverage: Int = 80
    /// Grade trend in percentage points, **offset by +100** so the column is a
    /// non-negative Int like every other feature: 100 = no change, 88 = down 12
    /// points, 105 = up 5. CreateML's tabular classifier is fed Int64 columns
    /// and a negative value here would need a signed schema for one feature
    /// alone.
    var gradeTrend: Int = 100
    var daysSinceSubmission: Int = 0
    var lateSubmissions: Int = 0

    /// Which of the above are real readings. Not a model input.
    var observed: ObservedSignals = []
    /// How long the meeting has been running. Not a model input — kept so
    /// `confidenceLevel` can be re-derived when another feature is changed.
    var meetingElapsed: TimeInterval = 0

    subscript(feature: StruggleFeature) -> Int {
        get {
            switch feature {
            case .isMuted:          isMuted
            case .timeUnmuted:      timeUnmuted
            case .isSpeaking:       isSpeaking
            case .speakingDuration: speakingDuration
            case .cameraOn:         cameraOn
            case .handRaised:       handRaised
            case .handRaiseCount:   handRaiseCount
            case .messageLength:    messageLength
            case .hesitationCount:  hesitationCount
            case .hasQuestion:      hasQuestion
            case .confidenceLevel:  confidenceLevel
            case .missingAssignments:  missingAssignments
            case .gradeAverage:        gradeAverage
            case .gradeTrend:          gradeTrend
            case .daysSinceSubmission: daysSinceSubmission
            case .lateSubmissions:     lateSubmissions
            }
        }
        set {
            switch feature {
            case .isMuted:          isMuted = newValue
            case .timeUnmuted:      timeUnmuted = newValue
            case .isSpeaking:       isSpeaking = newValue
            case .speakingDuration: speakingDuration = newValue
            case .cameraOn:         cameraOn = newValue
            case .handRaised:       handRaised = newValue
            case .handRaiseCount:   handRaiseCount = newValue
            case .messageLength:    messageLength = newValue
            case .hesitationCount:  hesitationCount = newValue
            case .hasQuestion:      hasQuestion = newValue
            case .confidenceLevel:  confidenceLevel = newValue
            case .missingAssignments:  missingAssignments = newValue
            case .gradeAverage:        gradeAverage = newValue
            case .gradeTrend:          gradeTrend = newValue
            case .daysSinceSubmission: daysSinceSubmission = newValue
            case .lateSubmissions:     lateSubmissions = newValue
            }
        }
    }

    /// The dictionary handed to MLDictionaryFeatureProvider, filtered to the
    /// inputs the loaded model actually declares.
    ///
    /// Verified against the shipped model: it *does* tolerate extra keys and
    /// ignores them, so this filtering is not working around a crash. It is kept
    /// because tolerance of undeclared inputs is a property of this particular
    /// converted pipeline rather than a documented Core ML guarantee, and
    /// because sending only what the model declares is what makes
    /// `StruggleDetectionService.usesAcademicFeatures` an honest answer to
    /// "is the model actually using Classroom data?" — which is the flag that
    /// switches the rule-based escalation off.
    func modelInputs(accepting declared: Set<String>) -> [String: Int64] {
        var inputs: [String: Int64] = [:]
        for feature in StruggleFeature.allCases where declared.contains(feature.rawValue) {
            inputs[feature.rawValue] = Int64(self[feature])
        }
        return inputs
    }

    /// Every column, for CSV export and training.
    var allInputs: [String: Int64] {
        var inputs: [String: Int64] = [:]
        for feature in StruggleFeature.allCases {
            inputs[feature.rawValue] = Int64(self[feature])
        }
        return inputs
    }

    /// Names a candidate model **must** declare to be usable.
    ///
    /// Only the 11 engagement features. The academic five are deliberately not
    /// required: the model shipped today predates them, and requiring all 16
    /// would make `StruggleDetectionService` reject it and silently drop the
    /// whole app to heuristic scoring. A retrained 16-feature model still
    /// satisfies this — a superset passes the same subset check — so it drops in
    /// without a code change.
    static let requiredFeatureNames = Set(StruggleFeature.engagementFeatures.map(\.rawValue))

    /// Every column, including academic. Used for CSV export and for feeding a
    /// model that declares them.
    static let allFeatureNames = Set(StruggleFeature.allCases.map(\.rawValue))

    /// The five Google Classroom columns.
    static let academicFeatureNames = Set(StruggleFeature.academicFeatures.map(\.rawValue))

    /// Recomputes `confidenceLevel` from the current values of the other
    /// features. Needed after changing a feature by hand — confidence_level is
    /// a summary of the rest, so leaving it stale would make the vector describe
    /// a student who cannot exist.
    /// Folds the academic columns in. Kept separate from the Zoom half so the
    /// two data sources never overwrite each other's `observed` flags.
    mutating func applyClassroomFeatures(_ academic: FeatureCalculator.ClassroomFeatures) {
        missingAssignments = academic.missingAssignments
        gradeAverage = academic.gradeAverage
        gradeTrend = academic.gradeTrend
        daysSinceSubmission = academic.daysSinceSubmission
        lateSubmissions = academic.lateSubmissions
        observed.formUnion(academic.observed)
    }

    /// True when Google Classroom data is part of this vector.
    var hasAcademicSignals: Bool { observed.contains(.academic) }

    mutating func refreshConfidenceLevel() {
        confidenceLevel = FeatureCalculator.confidenceLevel(
            for: self,
            meetingElapsed: meetingElapsed
        )
    }
}

// MARK: - Cross-poll accumulators

/// State that only exists by watching a participant over time.
///
/// Zoom hands us "is muted *now*" and "hand is raised *now*"; the model wants
/// "seconds spent unmuted" and "how many times a hand went up". This integrates
/// the former into the latter, one poll at a time.
nonisolated struct StruggleSignalHistory: Hashable, Sendable {
    var unmutedSeconds: Int = 0
    /// Fallback for speaking_duration when Zoom doesn't report a total.
    var talkingSeconds: Int = 0
    var handRaiseCount: Int = 0
    var wasHandRaised: Bool = false
    var lastSampledAt: Date?

    /// How long Anchor has actually watched this student, in seconds.
    ///
    /// Not the same as the meeting's elapsed time: a student who joins late, or
    /// a bot that joins a class already in progress, has been *observed* for far
    /// less than the class has been running. Scores ramp off this — see
    /// `ObservationRamp` — so a judgement is never presented before there is
    /// anything to judge.
    var observedSeconds: Int = 0

    /// The same engagement counters, exponentially decayed so recent seconds
    /// count for more than old ones.
    ///
    /// The plain totals above can only ever grow, which means a student who
    /// talked twice in the first five minutes reads as engaged for the rest of
    /// the hour however quiet they go. These decay with a half-life of about
    /// five minutes, so they describe the student *now*.
    var recentUnmutedSeconds: Double = 0
    var recentTalkingSeconds: Double = 0

    /// Last time this student did something active — spoke or raised a hand.
    /// Nil until they do it once, which is what separates "went quiet" from
    /// "was never audible in the first place".
    var lastEngagementAt: Date?

    /// Longest gap credited to a single poll. Guards against a laptop that slept
    /// for an hour coming back and crediting the whole hour as "unmuted".
    private static let maximumSampleGap: TimeInterval = 300

    /// Decay constant for the `recent…` counters. At 300s a signal is worth
    /// ~37% of its original weight five minutes later, ~14% after ten.
    private static let recencyTau: Double = 300

    func advanced(with participant: ZoomParticipant, now: Date) -> StruggleSignalHistory {
        var next = self

        // Two different intervals, deliberately.
        //
        // `elapsed` is the real wall-clock time since the last poll. `gap` is
        // that clamped to `maximumSampleGap`, and the clamp exists so a laptop
        // that slept for an hour cannot come back and credit the whole hour as
        // unmuted. Crediting must be clamped; the two are not the same question.
        let elapsed = lastSampledAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let gap = Int(min(Self.maximumSampleGap, elapsed))

        next.observedSeconds += gap

        let isUnmuted = participant.isMuted == false
        let isTalking = (participant.audioLevel ?? 0) > 0

        if isUnmuted {
            next.unmutedSeconds += gap
        }
        if isTalking {
            next.talkingSeconds += gap
        }

        // Decay first, then credit this interval — crediting first would let a
        // long gap decay the seconds it just added.
        //
        // Decay uses `elapsed`, not `gap`. Reusing the clamped value here meant a
        // laptop closed for an hour came back with e^-1 ≈ 37% of its pre-sleep
        // counters intact instead of e^-12 ≈ 0, so a student who was talking
        // before lunch still read as recently engaged after it. The clamp answers
        // "how much credit did they earn"; decay answers "how long ago was that",
        // and an hour really was an hour.
        let decay = exp(-elapsed / Self.recencyTau)
        next.recentUnmutedSeconds = recentUnmutedSeconds * decay + (isUnmuted ? Double(gap) : 0)
        next.recentTalkingSeconds = recentTalkingSeconds * decay + (isTalking ? Double(gap) : 0)

        // Rising edge only — a hand held up across three polls is one raise.
        let handRaised = participant.handRaised ?? false
        if handRaised, !wasHandRaised {
            next.handRaiseCount += 1
        }
        // Level, not edge — and the distinction matters more than it looks.
        //
        // `handRaiseCount` above is edge-counted, correctly: a hand held up
        // across three polls is one raise. `lastEngagementAt` answers a
        // different question — when did this student last do something active —
        // and a hand that is still up is still active. Sharing the edge
        // condition meant a student who raised their hand and waited to be
        // called on stopped counting as engaged the instant the edge passed,
        // aged out of EngagementDrift's five-minute grace period, and began
        // accruing a drift penalty while their hand was still raised. Anchor
        // would then offer the teacher "hasn't spoken in 8 min — ask them a
        // direct question" about the one student in the room already asking for
        // precisely that.
        if isTalking || handRaised {
            next.lastEngagementAt = now
        }

        next.wasHandRaised = handRaised
        next.lastSampledAt = now

        return next
    }
}

// MARK: - Calculator

nonisolated struct FeatureCalculator: Sendable {

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    /// Builds the model input vector for one participant.
    ///
    /// Unknown signals fall back to `unobservedDefault` rather than failing:
    /// the model has no concept of a missing column. Those fallbacks are
    /// recorded in `observed` so the caller can shrink the resulting score
    /// toward "unknown" instead of trusting it.
    /// `includesCamera` is Settings' "Include camera-off in scoring".
    func calculateFeatures(
        from participant: ZoomParticipant,
        chat: [ZoomChat] = [],
        meetingElapsed: TimeInterval = 0,
        history: StruggleSignalHistory = StruggleSignalHistory(),
        academic: AcademicSnapshot? = nil,
        includesCamera: Bool = true
    ) -> StruggleFeatures {
        var features = StruggleFeatures()

        // MARK: Mic
        if let isMuted = participant.isMuted {
            features.isMuted = isMuted ? 1 : 0
            features.observed.insert(.mute)
        } else {
            // Muted is the modal state in a class, so it is the least
            // distorting stand-in — and it is paired with timeUnmuted = 0,
            // which is what we have actually observed (nothing).
            features.isMuted = 1
        }
        features.timeUnmuted = history.unmutedSeconds

        // MARK: Voice
        if let level = participant.audioLevel {
            features.isSpeaking = level > 0 ? 1 : 0
            features.observed.insert(.audio)
        }
        if let speaking = participant.speakingSeconds {
            features.speakingDuration = max(0, speaking)
            features.observed.insert(.speaking)
        } else {
            features.speakingDuration = history.talkingSeconds
            if history.talkingSeconds > 0 { features.observed.insert(.speaking) }
        }

        // MARK: Camera
        //
        // With the setting off, a reported camera is treated exactly as an
        // unreported one: the benign default, and `.camera` kept out of
        // `observed` so neither the confidence estimate nor the fallback
        // calculator's 0.20 weighting counts it. That is the case the toggle
        // exists for — a class where cameras are off by school policy or for
        // bandwidth, where scoring students as disengaged for following the
        // rules is exactly the wrong reading.
        if let hasVideo = participant.hasVideo, includesCamera {
            features.cameraOn = hasVideo ? 1 : 0
            features.observed.insert(.camera)
        } else {
            // Benign default: an unknown camera must not invent a red flag.
            features.cameraOn = 1
        }

        // MARK: Hands
        if let handRaised = participant.handRaised {
            features.handRaised = handRaised ? 1 : 0
            features.observed.insert(.hand)
        }
        features.handRaiseCount = history.handRaiseCount

        // MARK: Chat
        let mine = messages(of: participant, in: chat)
        if !chat.isEmpty {
            features.observed.insert(.chat)
        }
        features.messageLength = mine.reduce(0) { $0 + Self.wordCount($1) }
        features.hesitationCount = mine.reduce(0) { $0 + Self.hesitationCount(in: $1) }
        features.hasQuestion = mine.contains(where: Self.isQuestion) ? 1 : 0

        // MARK: Academic
        if let academic {
            // `asOf: now`, not the default. The one time-dependent academic
            // column reads a gap in days, and this calculator is constructed
            // with an injected clock precisely so that gap can be pinned.
            features.applyClassroomFeatures(
                Self.extractClassroomFeatures(from: academic, asOf: now)
            )
        }

        // MARK: Derived confidence
        features.meetingElapsed = meetingElapsed
        features.refreshConfidenceLevel()

        return features
    }

    // MARK: - Classroom features

    /// The academic half of the vector, derived from one student's Classroom
    /// standing.
    ///
    /// Missing data is left at the in-good-standing defaults rather than zeroed:
    /// a course with nothing graded yet must not read as a student with no
    /// grades. `observed` records which of these were actually measured, exactly
    /// as it does for the Zoom signals.
    ///
    /// `asOf` is defaulted for call sites that genuinely mean "right now", but
    /// `calculateFeatures` must pass its own clock. Reaching the no-argument
    /// `snapshot.daysSinceSubmission` here read `Date()` directly and threw the
    /// injected clock away — the identical defect `daysSinceSubmission(asOf:)`
    /// was added to fix in `AcademicEscalation`, one layer up. Live scoring
    /// barely noticed, since `now` is usually the wall clock anyway; the export
    /// path is where it bites. `allInputs` exists to write training rows, and
    /// rebuilding historical rows stamped every one of them with the gap as of
    /// the day of the export rather than the gap on the day the row happened,
    /// which is a column of pure hindsight fed straight back into training.
    static func extractClassroomFeatures(
        from snapshot: AcademicSnapshot,
        asOf now: Date = Date()
    ) -> ClassroomFeatures {
        var features = ClassroomFeatures()
        features.observed.insert(.academic)

        features.missingAssignments = snapshot.missingCount
        features.lateSubmissions = snapshot.lateCount

        if let average = snapshot.averageGrade {
            features.gradeAverage = Int((average * 100).rounded())
            features.observed.insert(.grades)
        }

        if let trend = snapshot.gradeTrend {
            // Offset by +100 to keep the column non-negative — see
            // StruggleFeatures.gradeTrend.
            features.gradeTrend = 100 + Int((trend * 100).rounded())
        }

        // Only meaningful once the course has past-due work. In a brand new
        // course "nothing submitted" is the correct and unremarkable state.
        if snapshot.pastDueCount > 0 {
            features.daysSinceSubmission = snapshot.daysSinceSubmission(asOf: now) ?? 30
        }

        return features
    }

    /// The five academic columns, kept as their own value so
    /// `extractClassroomFeatures` can be read and tested on its own.
    nonisolated struct ClassroomFeatures: Hashable, Sendable {
        var missingAssignments = 0
        var gradeAverage = 80
        var gradeTrend = 100
        var daysSinceSubmission = 0
        var lateSubmissions = 0
        var observed: ObservedSignals = []
    }

    // MARK: - Chat parsing

    private func messages(of participant: ZoomParticipant, in chat: [ZoomChat]) -> [String] {
        chat.filter { message in
            // When both sides carry an id, the ids settle it — including when
            // they disagree.
            //
            // This used to fall through to the name comparison after a failed
            // id match, so a message whose sender was known and *different*
            // could still be claimed on a display-name collision. Two students
            // who both go by "Ada" is ordinary in a class. So is one student
            // joining twice, from a laptop and a phone: Zoom reports two
            // participants sharing a name, and every message got attributed to
            // both, doubling message_length and hesitation_count for the pair
            // while the real second device sat there looking silent.
            //
            // Safe because the two ids are the same namespace wherever both
            // exist — ZoomChat is only ever built by the Meeting SDK bridge,
            // which stringifies the same in-meeting user id it puts on the
            // participant. The name path is for the REST feed, which reports no
            // chat at all and no ids worth comparing; it is a fallback for a
            // missing answer, not an override for an answer we already have.
            if let userID = participant.userID, let senderID = message.senderID {
                return senderID == userID
            }
            return message.senderName == participant.name
        }
        .map(\.message)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func wordCount(_ text: String) -> Int {
        words(in: text).count
    }

    /// Filler words. The training feature counts spoken hesitations; with no
    /// transcript feed the closest available proxy is the same fillers typed in
    /// chat.
    ///
    /// "like" and "so" are ordinary English as well as hesitations, and this
    /// cannot tell the two apart: "so I finished the homework" scores a
    /// hesitation. The set is kept as-is anyway because it is the set the model
    /// was trained against, and quietly narrowing it here would move the column
    /// out from under the weights without retraining. Worth revisiting on the
    /// next retrain, not before — the penalty it feeds is capped at 15 points
    /// (see `confidenceLevel`), which bounds how wrong this can be.
    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "erm", "hmm", "like", "so"]

    static func hesitationCount(in text: String) -> Int {
        words(in: text).filter { fillers.contains($0) }.count
    }

    private static let questionOpeners: Set<String> = [
        "what", "why", "how", "when", "where", "who", "which",
        "can", "could", "does", "do", "did", "is", "are", "should", "would", "will"
    ]

    static func isQuestion(_ text: String) -> Bool {
        if text.contains("?") { return true }
        // Look past any leading fillers for the opener.
        //
        // Students rarely open a chat question with the interrogative. "so how
        // do we do part b" and "um what page are we on" are the normal register,
        // and matching only the literal first word read both as statements. The
        // cost landed twice on the same student: has_question stayed 0 *and*
        // hesitation_count went up for the very word that made it miss, so
        // asking for help the way students actually ask for help scored as
        // disengaged and hesitant. No filler is also an opener, so skipping them
        // cannot swallow the word being looked for.
        guard let opener = words(in: text).first(where: { !fillers.contains($0) }) else {
            return false
        }
        return questionOpeners.contains(opener)
    }

    // MARK: - confidence_level

    /// A 0...100 proxy for how confident the student appears.
    ///
    /// Nothing Zoom reports measures this directly, so it is assembled from the
    /// participation signals — which is what the training column stands in for.
    ///
    /// **The scale matters more than the shape.** This is by far the model's
    /// heaviest input (−0.28 logits per point, against a +4.47 intercept), so
    /// the decision boundary sits near 16/100. A proxy that only ranges over,
    /// say, 28...100 would never cross it and every student would score as
    /// coping. It is therefore built as a participation *share* — a student with
    /// none of the observable engagement signals lands at 0, one with all of
    /// them at 100 — rather than as nudges around a midpoint.
    ///
    /// Only observed signals are averaged in. A participant we know nothing
    /// about scores 50 (genuinely unknown) instead of 0 (measured as completely
    /// disengaged), which is the difference between "no data" and "in trouble".
    static func confidenceLevel(
        for features: StruggleFeatures,
        meetingElapsed: TimeInterval
    ) -> Int {
        var total = 0.0        // Σ weight of the components we could measure
        var earned = 0.0       // Σ weight × how much of it the student earned

        func add(_ share: Double, weight: Double) {
            total += weight
            earned += weight * min(1, max(0, share))
        }

        if features.observed.contains(.speaking) || features.observed.contains(.audio) {
            let expected = max(30.0, meetingElapsed * 0.04)      // ~4% of the session
            add(Double(features.speakingDuration) / expected, weight: 0.30)
        }
        if features.observed.contains(.mute) {
            let expected = max(60.0, meetingElapsed * 0.10)      // ~10% of the session
            add(Double(features.timeUnmuted) / expected, weight: 0.15)
        }
        if features.observed.contains(.camera) {
            add(Double(features.cameraOn), weight: 0.20)
        }
        if features.observed.contains(.hand) {
            add(Double(features.handRaiseCount) / 2, weight: 0.10)
        }
        if features.observed.contains(.chat) {
            add(Double(features.messageLength) / 30, weight: 0.15)
            add(Double(features.hasQuestion), weight: 0.10)
        }

        guard total > 0 else { return 50 }                       // nothing observed

        var value = earned / total
        // Hesitation reads as uncertainty, and only means anything if we have a
        // feed to have counted it in.
        if features.observed.contains(.chat) {
            value -= min(0.15, Double(features.hesitationCount) * 0.03)
        }

        return Int((100 * min(1, max(0, value))).rounded())
    }
}
