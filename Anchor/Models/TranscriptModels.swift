//
//  TranscriptModels.swift
//  Anchor
//
//  What the class is currently *about*, and what to do about it.
//
//  Anchor's struggle score answers "who is disengaged". These models answer the
//  question a teacher actually acts on — "so what do I say, and to whom" — by
//  pairing the live transcript with what the roster already knows about each
//  student.
//
//  Every type here is a value type conforming to Sendable, which under this
//  target's `-default-isolation MainActor` is what keeps them usable from the
//  off-main analysis path. The same rule is why `Student` is deliberately *not*
//  Sendable: it never leaves the main actor.
//
//  Privacy: none of this is Codable to disk. A transcript is a recording of
//  minors speaking in a classroom and it stays in memory for the length of the
//  session, exactly like the grades in AcademicSnapshot. See
//  TranscriptCaptureService for the retention rules.
//

import Foundation

// MARK: - Transcript

/// One utterance from Zoom's live transcription.
///
/// Zoom revises a line several times as the speech recogniser firms it up, so
/// `id` is the SDK's own message id and later versions of the same id replace
/// earlier ones rather than appending. `isFinal` marks the version Zoom says it
/// is done with: the analysis window includes unfinalised lines, because they
/// are the freshest speech in the room, but only finalised ones move the
/// fingerprint that decides when to re-run the model — otherwise every
/// keystroke-level revision of "photo… photosyn… photosynthesis" would spend an
/// inference.
nonisolated struct TranscriptLine: Identifiable, Hashable, Sendable {

    /// Who said it, as far as Anchor can tell.
    enum Speaker: Hashable, Sendable {
        case teacher
        case student(name: String)
        /// Anchor's own bot, which never speaks — present only because Zoom
        /// occasionally attributes a caption to it during a reconnect.
        case anchorBot
        /// Zoom gave a name Anchor could not place against the participant list.
        case unknown(name: String)

        var displayName: String {
            switch self {
            case .teacher: "Teacher"
            case .student(let name), .unknown(let name): name
            case .anchorBot: MeetingRoles.botDisplayName
            }
        }

        /// Whether this line is worth showing the model as *instruction*. The
        /// teacher's speech is what carries the topic and the questions; a
        /// student's answer is evidence of engagement, not of curriculum.
        var isInstruction: Bool {
            if case .teacher = self { return true }
            return false
        }
    }

    let id: String
    var speakerID: String?
    var speaker: Speaker
    var text: String
    var timestamp: Date
    /// False while Zoom is still revising the line.
    var isFinal: Bool

    /// "Teacher: So photosynthesis is when plants…"
    var attributed: String { "\(speaker.displayName): \(text)" }
}

// MARK: - Transcript availability

/// Why the transcript is or isn't flowing, in terms a teacher can act on.
///
/// Live transcription is the one part of this feature Anchor cannot switch on by
/// itself in every meeting: Zoom gates it on the account's plan and, in meetings
/// without multi-language transcription, on being the host. A silent empty panel
/// would read as a bug, so each refusal carries its own fix.
nonisolated enum TranscriptAvailability: Equatable, Sendable {
    /// The bot hasn't joined, or has joined and not asked yet.
    case notStarted
    /// `startLiveTranscription` accepted; waiting for Zoom to connect it.
    case starting
    /// Lines are arriving.
    case live(lines: Int)
    /// Zoom's transcription feature is off for this account or meeting.
    case unsupported
    /// Only the host can start it and Anchor's bot is not the host.
    case needsHost
    /// Zoom refused for some other reason, carried verbatim.
    case refused(String)
    /// The teacher supplied the topic by hand instead — see `ClassTopic.manual`.
    case manual

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    /// True when there is nothing more Anchor can do on its own.
    var isBlocked: Bool {
        switch self {
        case .unsupported, .needsHost, .refused: true
        case .notStarted, .starting, .live, .manual: false
        }
    }

    var headline: String {
        switch self {
        case .notStarted: "Live transcript hasn't started."
        case .starting: "Connecting to Zoom's live transcript…"
        case .live(let lines): "Live transcript running · \(lines) line\(lines == 1 ? "" : "s")."
        case .unsupported: "Zoom live transcription isn't available in this meeting."
        case .needsHost: "Only the host can turn on live transcription."
        case .refused(let reason): "Zoom refused live transcription: \(reason)"
        case .manual: "Using the topic you entered."
        }
    }

    var detail: String? {
        switch self {
        case .notStarted, .starting, .live:
            nil
        case .unsupported:
            "Zoom's live transcription is a paid-plan feature and has to be enabled "
            + "for the account in the Zoom web portal under Settings → In Meeting "
            + "(Advanced) → Automated captions. Until then, enter the topic by hand "
            + "and Anchor will still match it against each student's coursework."
        case .needsHost:
            "Anchor's bot joined as a participant, and this meeting only lets the "
            + "host start transcription. Start captions yourself in Zoom and Anchor "
            + "will pick them up, or enter the topic by hand."
        case .refused:
            "Anchor will keep scoring engagement from the meeting signals — only "
            + "the topic-aware half of the recommendations is affected."
        case .manual:
            nil
        }
    }
}

// MARK: - Topic

/// What is being taught right now, as extracted from the transcript.
nonisolated struct ClassTopic: Hashable, Sendable {

    /// Where this reading came from — shown in the UI, because a topic the
    /// teacher typed is a fact and a topic a model inferred is a reading.
    enum Source: String, Hashable, Sendable {
        case foundationModel
        case manual

        var label: String {
            switch self {
            case .foundationModel: "On-device model"
            case .manual: "Entered by you"
            }
        }
    }

    /// e.g. "Photosynthesis"
    var topic: String
    /// e.g. "Question 3" — nil when the teacher isn't working through numbered
    /// items, which is most of the time.
    var questionLabel: String?
    /// e.g. "What is the chlorophyll process?"
    var questionText: String?
    /// e.g. ["photosynthesis", "chlorophyll", "sunlight"]
    var concepts: [String]
    var capturedAt: Date
    var source: Source

    /// "Question 3 — What is the chlorophyll process?", or whichever half exists.
    var questionDisplay: String? {
        switch (questionLabel, questionText) {
        case (let label?, let text?): "\(label) — \(text)"
        case (let label?, nil): label
        case (nil, let text?): text
        case (nil, nil): nil
        }
    }

    /// The short form used inside a recommendation headline: "Question 3
    /// (Chlorophyll)" where both are known, the topic alone otherwise.
    var shortReference: String {
        guard let questionLabel else { return topic }
        let subject = concepts.first.map { $0.capitalizedFirst } ?? topic
        return "\(questionLabel) (\(subject))"
    }

    /// Everything worth matching a student's coursework against — the topic plus
    /// the concepts, deduplicated.
    var matchTerms: [String] {
        var seen: Set<String> = []
        return ([topic] + concepts)
            .map { $0.trimmed }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

// MARK: - Topic weakness

/// How a student has fared on this topic before.
///
/// The evidence is carried alongside the score rather than reduced to it: a
/// teacher deciding whether to call on a quiet student deserves to see "65% on
/// the photosynthesis quiz" rather than "weakness 0.7".
nonisolated struct TopicWeakness: Hashable, Sendable {

    /// One piece of past coursework Anchor considers to be about this topic.
    nonisolated struct RelatedWork: Hashable, Sendable, Identifiable {
        var id: String { assignmentID }
        var assignmentID: String
        var title: String
        /// 0...1 where graded. Nil for work that is missing rather than marked.
        var fraction: Double?
        var isMissing: Bool
        var dueDate: Date?
        /// 0...1 — how confident Anchor is that this assignment is about the
        /// topic at all. Below `TopicMatcher.minimumRelevance` it isn't kept.
        var relevance: Double

        var scoreDisplay: String {
            guard let fraction else { return isMissing ? "Missing" : "Ungraded" }
            return "\(Int((fraction * 100).rounded()))%"
        }
    }

    var topic: String
    /// Graded work on this topic, most relevant first.
    var relatedWork: [RelatedWork]
    /// Mean grade across the graded related work, 0...1. Nil when none of the
    /// matched work carries a grade.
    var averageFraction: Double?
    /// Related work that is past due with nothing turned in.
    var missingCount: Int
    /// 0...1. Zero means "nothing on this topic looks like a problem"; it does
    /// *not* mean "no data" — that case is `isEmpty`.
    var weaknessScore: Double

    /// True when the roster had nothing about this topic to say. Kept distinct
    /// from a zero score so the UI can stay quiet rather than claiming the
    /// student is fine on a topic it knows nothing about.
    var isEmpty: Bool { relatedWork.isEmpty }

    var averageDisplay: String {
        guard let averageFraction else { return "—" }
        return "\(Int((averageFraction * 100).rounded()))%"
    }

    /// One clause naming the evidence: "65% on Photosynthesis Quiz".
    var evidenceClause: String? {
        guard !isEmpty else { return nil }
        var parts: [String] = []
        if let averageFraction, let first = relatedWork.first(where: { $0.fraction != nil }) {
            let percent = Int((averageFraction * 100).rounded())
            parts.append(relatedWork.filter { $0.fraction != nil }.count == 1
                ? "\(percent)% on \(first.title)"
                : "\(percent)% average across \(relatedWork.filter { $0.fraction != nil }.count) assignments on this topic")
        }
        if missingCount > 0 {
            parts.append("\(missingCount) missing assignment\(missingCount == 1 ? "" : "s") on it")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func empty(topic: String) -> TopicWeakness {
        TopicWeakness(
            topic: topic,
            relatedWork: [],
            averageFraction: nil,
            missingCount: 0,
            weaknessScore: 0
        )
    }
}

// MARK: - Recommendation

/// One thing the teacher could do right now, about one student.
nonisolated struct LiveRecommendation: Identifiable, Hashable, Sendable {

    /// How loudly to say it. Mirrors `RiskLevel` one-for-one so the dashboard
    /// can colour a recommendation the same as the student row that produced it
    /// — two different palettes for the same student would read as two
    /// different verdicts.
    enum Urgency: String, Hashable, Sendable, Comparable {
        case high
        case elevated
        case low

        var rank: Int {
            switch self {
            case .high: 0
            case .elevated: 1
            case .low: 2
            }
        }

        static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rank < rhs.rank }
    }

    /// What phrased the text. A model-written line and a template-written line
    /// are both honest, but only one of them should be described as generated.
    enum Source: String, Hashable, Sendable {
        case foundationModel
        case template

        var label: String {
            switch self {
            case .foundationModel: "Written on-device by Apple Foundation Models"
            case .template: "Composed from the matched signals"
            }
        }
    }

    let id: UUID
    /// `Student.id`, so the dashboard can route straight to the detail view.
    var studentID: UUID
    var studentName: String
    /// The imperative line: "Ask about Question 3 (Chlorophyll)".
    var headline: String
    /// The question to actually put to them, when the transcript gave one.
    var suggestedQuestion: String?
    /// Why this student, why now — the evidence, in one sentence.
    var reason: String
    var urgency: Urgency
    /// The topic this was built against. Nil for recommendations that rest on
    /// engagement signals alone, which is what happens with no transcript.
    var topic: String?
    var statusSummary: String
    var generatedAt: Date
    var source: Source

    init(
        id: UUID = UUID(),
        studentID: UUID,
        studentName: String,
        headline: String,
        suggestedQuestion: String? = nil,
        reason: String,
        urgency: Urgency,
        topic: String? = nil,
        statusSummary: String,
        generatedAt: Date = Date(),
        source: Source
    ) {
        self.id = id
        self.studentID = studentID
        self.studentName = studentName
        self.headline = headline
        self.suggestedQuestion = suggestedQuestion
        self.reason = reason
        self.urgency = urgency
        self.topic = topic
        self.statusSummary = statusSummary
        self.generatedAt = generatedAt
        self.source = source
    }
}

// MARK: - Foundation model availability

/// Whether the on-device model can run, and if not, what the teacher can do.
///
/// Mirrors `SystemLanguageModel.Availability` rather than re-exporting it, so
/// the model layer and the views don't have to import FoundationModels — and so
/// a future second backend doesn't have to pretend to be Apple's enum.
nonisolated enum LiveCoachAvailability: Equatable, Sendable {
    case checking
    case ready
    /// The Mac can't run Apple Intelligence at all.
    case deviceNotEligible
    /// Apple Intelligence is off in System Settings.
    case notEnabled
    /// Enabled, but the assets are still downloading.
    case modelNotReady
    /// The framework threw something unexpected on first use.
    case failed(String)

    var isReady: Bool { self == .ready }

    var headline: String {
        switch self {
        case .checking: "Checking the on-device model…"
        case .ready: "Recommendations are generated on-device."
        case .deviceNotEligible: "This Mac can't run Apple Intelligence."
        case .notEnabled: "Apple Intelligence is turned off."
        case .modelNotReady: "Apple Intelligence is still downloading its model."
        case .failed(let reason): "The on-device model failed: \(reason)"
        }
    }

    var detail: String? {
        switch self {
        case .checking, .ready:
            nil
        case .deviceNotEligible:
            "Anchor will still match the topic against each student's coursework "
            + "and write the recommendation from the matched signals — only the "
            + "phrasing is affected."
        case .notEnabled:
            "Turn it on in System Settings → Apple Intelligence & Siri. Until then "
            + "Anchor composes recommendations from the matched signals instead."
        case .modelNotReady:
            "Anchor will start using it as soon as the download finishes. Until "
            + "then recommendations are composed from the matched signals."
        case .failed:
            "Anchor has fallen back to composing recommendations from the matched "
            + "signals. Everything else is unaffected."
        }
    }
}

// MARK: - Helpers

extension String {
    /// "chlorophyll" → "Chlorophyll", leaving the rest of the string alone so an
    /// acronym or a proper noun mid-phrase isn't flattened.
    nonisolated var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
