//
//  FoundationModelAnalyzer.swift
//  Anchor
//
//  Apple's on-device language model, doing the two jobs no amount of string
//  processing can: reading a lesson transcript for what is being taught, and
//  phrasing the result as something a teacher can act on mid-sentence.
//
//  Why on-device matters here beyond the marketing: the input is a live
//  recording of children speaking in a classroom, cross-referenced with their
//  grades. There is no version of this feature that would be acceptable if the
//  text left the Mac. FoundationModels runs locally, so it doesn't.
//
//  **No student names are ever sent to the model.** The prompts describe "the
//  student"; the name is spliced in locally afterwards. This is partly privacy
//  hygiene and partly practical — a prompt that names a child and then discusses
//  their poor grades is exactly the shape Apple's safety guardrails are built to
//  refuse, and a refusal here costs the teacher the recommendation.
//
//  An actor, so the model is asked one thing at a time. `LanguageModelSession`
//  throws `concurrentRequests` on overlapping calls, and the poll loop can
//  easily produce two while the first is still running.
//
//  Every failure path returns nil rather than throwing. The caller always has a
//  deterministic fallback — see RecommendationGenerator — and a model that is
//  slow, unavailable or has refused must never cost the teacher the underlying
//  engagement signals.
//

import Foundation
import FoundationModels

// MARK: - Generable payloads

/// What the model reports back about the transcript.
///
/// Every field is a plain `String`/`[String]` with an empty value standing in
/// for "not present", rather than an Optional. Guided generation supports
/// optionals, but an empty string is the one shape that cannot be ambiguous
/// across schema versions, and the conversion into `ClassTopic` normalises it
/// into a real Optional immediately.
@Generable
nonisolated struct ExtractedTopic {

    /// Declared *first* on purpose. Guided generation fills fields in
    /// declaration order, so asking this before the topic makes it a decision
    /// the model commits to rather than a caveat it reconsiders afterwards.
    ///
    /// It exists because "return an empty topic if it isn't clear" does not
    /// work. Given three lines of pre-class housekeeping the model will always
    /// name *something* — observed: "Lesson", "Classroom Management",
    /// "Permission slips" — so there is no list of bad answers to filter. A
    /// yes/no it has to answer is a question it can get right.
    @Guide(description: "True only if the transcript contains actual subject teaching — a concept being explained, a problem being worked, a text being studied. False for greetings, audio checks, waiting for people to join, homework deadlines, room changes, permission slips, or any other classroom logistics.")
    var isTeachingContent: Bool

    // No worked examples in this guide, or in `concepts` below. The originals
    // named "Photosynthesis" and "chlorophyll, sunlight" — and handed three
    // lines of audio-check chatter, the model returned exactly those, inventing
    // a biology lesson out of "can everyone hear me". A concrete example is
    // something to copy when there is nothing real to report.
    @Guide(description: "The single main educational topic being taught, in one to three words, capitalised. Use only wording the transcript itself supports. Empty string if isTeachingContent is false or the transcript does not make the topic clear.")
    var topic: String

    @Guide(description: "The label of the numbered item the teacher is working through, for example 'Question 3' or 'Problem 12'. Empty string if the teacher is not working through numbered items.")
    var questionLabel: String

    @Guide(description: "The exact question the teacher most recently asked the class, rewritten as a single clean sentence. Empty string if the teacher has not asked a question.")
    var questionText: String

    @Guide(description: "Between two and five key subject-matter terms that appear verbatim in the transcript, lowercase. Copy them from the transcript — do not supply terms of your own. Exclude ordinary classroom words. Empty if the transcript contains no subject-matter terms.")
    var concepts: [String]
}

/// The teacher-facing wording for one recommendation.
@Generable
nonisolated struct PhrasedRecommendation {

    // Must name a *subject*. Without the second sentence the model falls back on
    // bare urgency — "Pull back now", "Check in immediately" — which tells a
    // teacher nothing they didn't already know from the score beside it.
    @Guide(description: "An imperative instruction to the teacher of at most eight words, naming the specific topic, question or assignment to ask about. Do not include the student's name. It must name what to ask about — never a bare instruction like 'Check in now' or 'Pull back now'. For example 'Ask about Question 3 (Chlorophyll)' or 'Ask about the photosynthesis worksheet'.")
    var headline: String

    // The pronoun rule is not style. Anchor deliberately never sends the
    // student's name (see this file's header), so the model has no basis
    // whatever for a gender — and given the option it will invent one, which is
    // how a card about a boy came back reading "She has 2 missing assignments".
    // Wrong in front of a class, and about a child. "They" is the only pronoun
    // that can be correct here.
    @Guide(description: "One sentence of at most twenty-five words explaining why this student and why now, using only the facts given. Do not include the student's name. Never use 'she' or 'he' — you have not been told the student's gender. Write impersonally, or use 'they' if a pronoun is unavoidable.")
    var reason: String
}

// MARK: - Request

/// The facts a recommendation is phrased from — deliberately name-free.
nonisolated struct PhrasingRequest: Sendable, Hashable {
    /// "Silent 8 min"
    var statusSummary: String
    var topic: String?
    /// "Question 3 — What is the chlorophyll process?"
    var question: String?
    /// Mean grade on work related to this topic, 0...1.
    var topicAverage: Double?
    /// The single most relevant piece of past work, for the model to name.
    var topicWorkTitle: String?
    var missingRelatedCount: Int
    /// The engagement score. Kept on the request — it is part of what a
    /// recommendation is *about*, and `LiveCoachViewModel.cacheKey` bands it to
    /// decide when the wording needs rewriting — but deliberately never put in
    /// the prompt. See `prompt(for:)`.
    var strugglePercent: Int
}

// MARK: - Analyzer

actor FoundationModelAnalyzer {

    static let shared = FoundationModelAnalyzer()

    /// Ceilings, not targets. Generation usually lands well inside these; the
    /// point is that a wedged inference can never hold up the next scoring pass.
    ///
    /// Both are generous enough to be reached only when something is wrong,
    /// because the cost of timing out early is a *worse* recommendation, while
    /// the cost of timing out late is only that the topic on screen is one poll
    /// stale.
    private static let extractionTimeout: TimeInterval = 10
    private static let phrasingTimeout: TimeInterval = 8

    private var cachedAvailability: LiveCoachAvailability = .checking

    // MARK: Availability

    /// Whether the model can run right now.
    ///
    /// Re-read rather than cached across calls: Apple Intelligence can finish
    /// downloading, or be switched off in System Settings, in the middle of a
    /// lesson, and a cached "unavailable" would keep the feature dark for the
    /// rest of the class.
    func availability() -> LiveCoachAvailability {
        let resolved: LiveCoachAvailability
        switch SystemLanguageModel.default.availability {
        case .available:
            resolved = .ready
        case .unavailable(.deviceNotEligible):
            resolved = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            resolved = .notEnabled
        case .unavailable(.modelNotReady):
            resolved = .modelNotReady
        case .unavailable:
            // A reason added after this was written. Reported as a generic
            // failure rather than silently mapped onto one of the known cases,
            // whose remedies would then be wrong.
            resolved = .failed("Apple Intelligence is unavailable on this Mac.")
        }
        cachedAvailability = resolved
        return resolved
    }

    // MARK: Topic extraction

    /// Reads the transcript excerpt for what is being taught.
    ///
    /// Returns nil when the model is unavailable, times out, refuses, or reports
    /// no discernible topic — all of which the caller treats identically, by
    /// keeping whatever topic is already on screen.
    func extractTopic(from excerpt: String, now: Date = Date()) async -> ClassTopic? {
        guard availability().isReady else { return nil }

        let trimmed = excerpt.trimmed
        guard trimmed.count >= 40 else {
            // Two words of caption is not a lesson. Asking anyway produces a
            // confident topic drawn from the model's priors rather than the
            // room, which is the worst possible failure for this feature.
            return nil
        }

        let session = LanguageModelSession(
            instructions: """
                You read transcripts of live school lessons and report what is \
                being taught, for a dashboard the teacher glances at while \
                teaching.

                Report only what the transcript itself supports. If it does not \
                make the topic clear, return an empty topic rather than \
                guessing. Never report a question that was not asked. Prefer the \
                most recent subject discussed when the transcript covers more \
                than one.
                """
        )

        let prompt = """
            Transcript of the last few minutes of a lesson. Lines are labelled \
            with who spoke; the teacher's lines carry the lesson.

            \(trimmed)
            """

        do {
            let response = try await withTimeout(seconds: Self.extractionTimeout) {
                try await session.respond(
                    to: prompt,
                    generating: ExtractedTopic.self,
                    options: GenerationOptions(temperature: 0.2)
                )
            }
            return Self.topic(from: response.content, excerpt: trimmed, now: now)
        } catch {
            AnchorDiag.log("topic extraction failed: \(Self.describe(error))")
            return nil
        }
    }

    /// Words that name no subject.
    ///
    /// Matched against the *whole* topic, not as substrings — "Lesson" is a
    /// non-answer, "Lesson 4: Photosynthesis" is a topic.
    private static let vacuousTopics: Set<String> = [
        "lesson", "class", "classroom", "lecture", "school", "session",
        "meeting", "discussion", "introduction", "intro", "general",
        "general discussion", "housekeeping", "announcements", "review",
        "unknown", "none", "n/a", "topic", "the lesson", "the class",
        "current lesson", "today's lesson", "class discussion"
    ]

    /// How many of the model's concepts must actually appear in the transcript
    /// before its reading is believed.
    ///
    /// Two, because one is reachable by accident — a transcript about permission
    /// slips yields the single "concept" *textbook* — while two subject terms
    /// quoted from the room is a lesson happening.
    private static let requiredGroundedConcepts = 2

    /// Normalises the model's output, discarding anything it left empty.
    private static func topic(
        from extracted: ExtractedTopic,
        excerpt: String,
        now: Date
    ) -> ClassTopic? {
        // The model's own verdict on whether this is a lesson at all. Cheap, and
        // right sometimes — but not trusted on its own: it answered `true` for
        // an audio check, so the grounding check below is what actually holds.
        guard extracted.isTeachingContent else { return nil }

        let topic = extracted.topic.trimmed
        guard !topic.isEmpty else { return nil }

        // The model was asked for one to three words and mostly obliges; a long
        // answer means it has written a sentence instead of a topic, which is
        // not something to render in a headline.
        guard topic.count <= 60 else { return nil }

        // Backstop behind `isTeachingContent`, for the shapes that slip past it.
        // A wrong topic is not a cosmetic problem: it puts a bogus chip on
        // screen, feeds "the class is currently working on: Lesson" to the
        // phrasing prompt, and — worst — a non-nil topic is what lifts
        // `LiveCoachViewModel.regenerate`'s high-urgency-only filter, so every
        // elevated student starts generating recommendations built on nothing.
        guard !Self.vacuousTopics.contains(topic.lowercased()) else { return nil }

        let concepts = extracted.concepts
            .map { $0.trimmed.lowercased() }
            .filter { !$0.isEmpty && $0.count <= 40 }

        // The check that actually works: does the answer appear in the room?
        //
        // Every softer guard here failed against a live model. "Return an empty
        // topic if unclear" was ignored; an explicit `isTeachingContent` flag
        // came back `true` for an audio check; a denylist of vacuous words was
        // outrun by a model that simply picks a different word each time. What
        // does not fail is arithmetic: a lesson on Faraday's law says "Faraday's
        // law" out loud, and a transcript about permission slips does not
        // contain the word "chlorophyll".
        //
        // So the model's reading is only believed when the transcript
        // corroborates it. This costs nothing when the reading is right, and it
        // is the only guard here that does not depend on the model choosing to
        // behave.
        // Concepts only — deliberately not "or the topic appears in the text".
        // That disjunct was here and it was the hole: asked to read a topic out
        // of an audio check the model answers "AUDIO", which does appear, so the
        // check waved through the exact case it existed to stop. Measured, a
        // real lesson grounds three or more concepts and classroom logistics
        // grounds one, so the concept count separates them cleanly and the topic
        // string adds nothing but a way through.
        let haystack = excerpt.lowercased()
        let grounded = concepts.filter { haystack.contains($0) }
        guard grounded.count >= Self.requiredGroundedConcepts else {
            AnchorDiag.log(
                "topic \"\(topic)\" rejected — only \(grounded.count) of "
                + "\(concepts.count) concepts appear in the transcript"
            )
            return nil
        }

        return ClassTopic(
            topic: topic,
            questionLabel: extracted.questionLabel.trimmed.nonEmpty,
            questionText: extracted.questionText.trimmed.nonEmpty,
            concepts: Array(concepts.prefix(5)),
            capturedAt: now,
            source: .foundationModel
        )
    }

    // MARK: Recommendation phrasing

    /// Writes the headline and reason for one recommendation.
    ///
    /// Returns nil on any failure, including a guardrail refusal. A refusal is
    /// not an error condition worth surfacing: the facts are still true and
    /// RecommendationGenerator will state them in its own words.
    func phrase(_ request: PhrasingRequest) async -> PhrasedRecommendation? {
        guard availability().isReady else { return nil }

        let session = LanguageModelSession(
            instructions: """
                You write one short note to a teacher about one student in their \
                class, to be read at a glance in the middle of a lesson.

                Be concrete and practical. Use only the facts you are given — \
                never infer a grade, a topic or a behaviour that is not stated. \
                Never name the student, and never guess their gender: you have \
                not been told it, so use "they" rather than "she" or "he". \
                Describe what the student is doing in plain words, and never quote \
                Anchor's concern level back at the teacher. Every number you write \
                must come from the facts you were given — never carry one over \
                from these instructions. Do not open with a greeting, do not \
                explain your reasoning, and do not offer general teaching advice.
                """
        )

        do {
            let response = try await withTimeout(seconds: Self.phrasingTimeout) {
                try await session.respond(
                    to: Self.prompt(for: request),
                    generating: PhrasedRecommendation.self,
                    options: GenerationOptions(temperature: 0.4)
                )
            }

            let phrased = PhrasedRecommendation(
                headline: response.content.headline.trimmed,
                reason: response.content.reason.trimmed
            )
            guard !phrased.headline.isEmpty, !phrased.reason.isEmpty else { return nil }
            return phrased
        } catch {
            AnchorDiag.log("recommendation phrasing failed: \(Self.describe(error))")
            return nil
        }
    }

    /// Builds the prompt as a fact list rather than prose.
    ///
    /// A list is harder to misread than a sentence, and — more to the point —
    /// omitting a line is how "no grade information" is expressed. Writing
    /// "previously scored unknown%" would invite the model to fill the gap in.
    private static func prompt(for request: PhrasingRequest) -> String {
        // Anchor's own concern level is deliberately *not* here, in any form.
        // Three attempts to pass it leaked three different ways: as a number
        // ("their engagement concern is 40 out of 100"), as advice the model
        // reused as a headline ("Pull back now"), and finally as a claim about
        // the child ("They are very concerned about the topic") — that last one
        // being a statement about a student's state of mind that Anchor has no
        // basis for at all.
        //
        // Nothing is lost by dropping it. Urgency reaches the teacher through
        // `LiveRecommendation.urgency`, which colours the card and orders the
        // list; it never needed restating in the prose. The model's job is to
        // say what to ask about, and the facts below are what it needs for that.
        var facts: [String] = [
            "Right now, the student is: \(request.statusSummary)"
        ]

        if let topic = request.topic {
            facts.append("The class is currently working on: \(topic)")
        }
        if let question = request.question {
            facts.append("The question the teacher just put to the class: \(question)")
        }
        if let average = request.topicAverage {
            let percent = Int((average * 100).rounded())
            if let title = request.topicWorkTitle {
                facts.append("This student previously scored \(percent)% on earlier work on this same topic (\(title))")
            } else {
                facts.append("This student previously scored \(percent)% on earlier work on this same topic")
            }
        }
        if request.missingRelatedCount > 0 {
            facts.append(
                "This student has \(request.missingRelatedCount) missing "
                + "assignment\(request.missingRelatedCount == 1 ? "" : "s") on this same topic"
            )
        }

        return """
            Facts:
            \(facts.map { "- \($0)" }.joined(separator: "\n"))

            Write the note.
            """
    }

    // MARK: Diagnostics

    /// Turns a generation failure into one readable line.
    ///
    /// Worth spelling out because these are the errors a teacher will never see
    /// and a developer will need: a guardrail refusal and a context overflow
    /// both surface as "no recommendation" on screen, and they need completely
    /// different fixes.
    private static func describe(_ error: any Error) -> String {
        guard let generation = error as? LanguageModelSession.GenerationError else {
            if error is TimedOut { return "timed out" }
            return error.localizedDescription
        }

        return switch generation {
        case .exceededContextWindowSize: "the prompt exceeded the model's context window"
        case .assetsUnavailable: "the model assets are unavailable"
        case .guardrailViolation: "the safety guardrails refused the prompt"
        case .unsupportedGuide: "a @Guide in the schema is unsupported"
        case .unsupportedLanguageOrLocale: "the transcript language is unsupported"
        case .decodingFailure: "the model's output did not fit the schema"
        case .rateLimited: "the model is rate limiting requests"
        case .concurrentRequests: "another request was already in flight"
        case .refusal: "the model refused to answer"
        @unknown default: generation.localizedDescription
        }
    }
}

// MARK: - Timeout

/// Thrown when an inference outruns its ceiling.
private struct TimedOut: Error {}

/// Races an async operation against a deadline.
///
/// FoundationModels exposes no timeout of its own, and a generation that never
/// returns would wedge the analyzer actor — and with it every later request,
/// since the actor serialises them. The losing branch is cancelled, so a
/// timed-out inference stops consuming the Neural Engine rather than finishing
/// into a result nobody is waiting for.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimedOut()
        }

        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimedOut() }
        return first
    }
}

// MARK: - Helpers

extension String {
    /// Nil for an empty string, so the model's "not present" sentinel becomes a
    /// real Optional at the boundary rather than propagating as `""`.
    nonisolated var nonEmpty: String? { isEmpty ? nil : self }
}
