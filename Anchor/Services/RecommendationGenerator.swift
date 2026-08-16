//
//  RecommendationGenerator.swift
//  Anchor
//
//  Turns "this student is disengaged" into "ask this student this question".
//
//  Three inputs, and the order they are combined in matters:
//
//  * **The engagement score** decides *whether* a student is worth naming, and
//    how urgently. It is the only input that can put someone on the list.
//  * **The topic** decides what to ask about.
//  * **The topic weakness** decides what to say about why — and, when two
//    students are equally disengaged, which one to put first.
//
//  Note what topic weakness deliberately does *not* do: it never changes the
//  urgency. The dashboard colours a recommendation the same as the student row
//  that produced it, and a card that said "high" beside a row that said "watch"
//  would read as two verdicts about one child. Historical difficulty on the
//  current topic is a reason to ask a better question, not a reason to overrule
//  the live signals — which have already had the student's general academic
//  standing folded in by AcademicEscalation.
//
//  The model writes the words; this type decides the facts. When the model is
//  unavailable, refuses, or times out, `fallback` states the same facts in
//  Anchor's own voice — so the feature degrades in phrasing quality and never in
//  correctness.
//

import Foundation

// MARK: - Candidate

/// One student, reduced to the Sendable facts a recommendation rests on.
///
/// `Student` itself is main-actor-bound and deliberately not Sendable, so the
/// off-main work — topic matching and inference — takes this instead. The
/// reduction happens once, on the main actor, in LiveCoachViewModel.
nonisolated struct RecommendationCandidate: Sendable, Hashable {
    var studentID: UUID
    var name: String
    /// "Silent 8 min"
    var statusSummary: String
    /// 0...1
    var struggleScore: Double
    var urgency: LiveRecommendation.Urgency
    /// The student's Classroom standing, when they were matched to the roster.
    var academic: AcademicSnapshot?

    var strugglePercent: Int { Int((struggleScore * 100).rounded()) }
}

// MARK: - Generator

nonisolated struct RecommendationGenerator: Sendable {

    /// How many recommendations the dashboard will show at once.
    ///
    /// Three, because this is read while teaching. A list of eight is a list
    /// nobody acts on, and the fourth-most-disengaged student in the room is not
    /// the one to interrupt the lesson for.
    static let maximumShown = 3

    /// Below this, the topic weakness is real but too slight to be worth a
    /// sentence in front of the class.
    private static let notableWeakness = 0.25

    var now: Date
    var analyzer: FoundationModelAnalyzer

    init(now: Date = Date(), analyzer: FoundationModelAnalyzer = .shared) {
        self.now = now
        self.analyzer = analyzer
    }

    // MARK: Selection

    /// The students worth naming, most urgent first.
    ///
    /// Low-risk students are excluded outright: a recommendation is an
    /// interruption, and "Ask Marcus about Question 3" when Marcus is engaged
    /// and answering is how a teacher learns to ignore the panel.
    ///
    /// So are students Anchor can't confidently score — their row already reads
    /// "—" rather than a percentage, and a confident instruction built on a
    /// number the UI refuses to show would contradict it.
    static func rank(
        _ candidates: [RecommendationCandidate],
        weaknesses: [UUID: TopicWeakness]
    ) -> [RecommendationCandidate] {
        candidates
            .filter { $0.urgency != .low }
            .sorted { lhs, rhs in
                if lhs.urgency != rhs.urgency { return lhs.urgency < rhs.urgency }

                // Same urgency: the student with a known history of difficulty
                // on *this* topic is the more useful one to call on, because
                // there is something specific to ask them about.
                let lhsWeakness = weaknesses[lhs.studentID]?.weaknessScore ?? 0
                let rhsWeakness = weaknesses[rhs.studentID]?.weaknessScore ?? 0
                if lhsWeakness != rhsWeakness { return lhsWeakness > rhsWeakness }

                if lhs.struggleScore != rhs.struggleScore {
                    return lhs.struggleScore > rhs.struggleScore
                }
                return lhs.name < rhs.name
            }
            .prefix(maximumShown)
            .map { $0 }
    }

    // MARK: Generation

    /// One recommendation, phrased by the model where it can be and by Anchor
    /// where it can't.
    func recommendation(
        for candidate: RecommendationCandidate,
        topic: ClassTopic?,
        weakness: TopicWeakness?
    ) async -> LiveRecommendation {
        let evidence = weakness.flatMap { $0.weaknessScore >= Self.notableWeakness ? $0 : nil }

        let request = PhrasingRequest(
            statusSummary: candidate.statusSummary,
            topic: topic?.topic,
            question: topic?.questionDisplay,
            topicAverage: evidence?.averageFraction,
            topicWorkTitle: evidence?.relatedWork.first(where: { $0.fraction != nil })?.title,
            missingRelatedCount: evidence?.missingCount ?? 0,
            strugglePercent: candidate.strugglePercent
        )

        if let phrased = await analyzer.phrase(request) {
            return LiveRecommendation(
                studentID: candidate.studentID,
                studentName: candidate.name,
                headline: phrased.headline,
                suggestedQuestion: topic?.questionText,
                reason: phrased.reason,
                urgency: candidate.urgency,
                topic: topic?.topic,
                statusSummary: candidate.statusSummary,
                generatedAt: now,
                source: .foundationModel
            )
        }

        return fallback(for: candidate, topic: topic, weakness: evidence)
    }

    // MARK: Fallback

    /// The same recommendation, composed rather than generated.
    ///
    /// This is not a degraded placeholder — on a Mac without Apple Intelligence
    /// it is the whole feature, so it says everything the model would have been
    /// given. The only thing lost is the phrasing being tailored to the case.
    func fallback(
        for candidate: RecommendationCandidate,
        topic: ClassTopic?,
        weakness: TopicWeakness?
    ) -> LiveRecommendation {
        LiveRecommendation(
            studentID: candidate.studentID,
            studentName: candidate.name,
            headline: Self.headline(topic: topic),
            suggestedQuestion: topic?.questionText,
            reason: Self.reason(
                candidate: candidate,
                topic: topic,
                weakness: weakness
            ),
            urgency: candidate.urgency,
            topic: topic?.topic,
            statusSummary: candidate.statusSummary,
            generatedAt: now,
            source: .template
        )
    }

    /// "Ask about Question 3 (Chlorophyll)" — or, with no transcript, something
    /// that doesn't pretend to know what the class is doing.
    private static func headline(topic: ClassTopic?) -> String {
        guard let topic else { return "Check in — no response for a while" }
        return "Ask about \(topic.shortReference)"
    }

    /// The evidence, in the order a teacher would want it: what is happening
    /// now, then what it recalls.
    private static func reason(
        candidate: RecommendationCandidate,
        topic: ClassTopic?,
        weakness: TopicWeakness?
    ) -> String {
        var sentences = ["\(candidate.statusSummary)."]

        if let weakness, let clause = weakness.evidenceClause {
            sentences.append("Earlier work on \(weakness.topic.lowercased()): \(clause).")
        } else if let topic, let academic = candidate.academic, academic.missingCount > 0 {
            // Nothing on this specific topic, but the student is behind
            // generally — worth saying, and worth being clear that it is *not*
            // about the current topic.
            sentences.append(
                "No earlier work on \(topic.topic.lowercased()) to compare, but "
                + "\(academic.missingCount) assignment\(academic.missingCount == 1 ? " is" : "s are") missing overall."
            )
        }

        return sentences.joined(separator: " ")
    }
}
