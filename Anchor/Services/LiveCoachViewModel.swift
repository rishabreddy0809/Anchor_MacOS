//
//  LiveCoachViewModel.swift
//  Anchor
//
//  The live half of the recommendations: what the class is about right now, and
//  who to say what to about it.
//
//  Counterpart to ZoomViewModel and ClassroomViewModel, and driven by the first
//  of them — one pass per Zoom poll, immediately after the scores land, so the
//  recommendations on screen are always about the roster on screen.
//
//  Two clocks, because the two halves move at different speeds:
//
//  * **Scores** change every ten seconds, and a recommendation whose student has
//    gone quiet needs to reflect that.
//  * **The topic** changes every ten minutes or so, and re-reading the
//    transcript costs an inference. So extraction is gated on the transcript
//    having actually moved *and* a minimum interval having passed.
//
//  Recommendations are cached on the facts they were built from, so the model is
//  only asked to write something when there is something new to write. Without
//  that cache this would run an inference per student per ten seconds, for the
//  whole lesson, to re-derive text that had not changed.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class LiveCoachViewModel: ObservableObject {

    static let shared = LiveCoachViewModel()

#if DEBUG
    /// Shows a live topic without a transcript, for website screenshots.
    /// Starts no capture and calls no model.
    func applyDemoTopic() {
        topic = DemoData.topic
        modelAvailability = .ready
        isAnalyzing = false
    }
#endif

    // MARK: - Tuning

    /// Floor between transcript re-reads. The topic does not change on a
    /// ten-second cadence, and each read costs an on-device inference.
    private static let minimumExtractionInterval: TimeInterval = 30

    /// How long an extracted topic stays believable once the transcript stops
    /// moving.
    ///
    /// Captions drop out for all sorts of reasons mid-lesson. Holding the last
    /// reading forever would leave "Photosynthesis" on screen through the whole
    /// of the next unit; expiring it falls back to whatever the teacher typed,
    /// and failing that to topic-free recommendations, both of which are honest.
    private static let topicLifetime: TimeInterval = 600

    // MARK: - Published state

    /// What the class is working on. Nil when neither the transcript nor the
    /// teacher has said.
    @Published private(set) var topic: ClassTopic?
    @Published private(set) var recommendations: [LiveRecommendation] = []
    /// Per-student topic history, for the detail view. Keyed by `Student.id`.
    @Published private(set) var weaknesses: [UUID: TopicWeakness] = [:]
    @Published private(set) var modelAvailability: LiveCoachAvailability = .checking

    /// Whether an inference is in flight, so the UI can say "reading the
    /// transcript…" rather than appearing to have nothing to say.
    @Published private(set) var isAnalyzing = false

    // MARK: - Dependencies

    let transcript: TranscriptCaptureService
    private let analyzer: FoundationModelAnalyzer
    private let notifier: MeetingNotifier
    private let alertPolicy = RecommendationAlertPolicy()

    /// When each student was last announced, so the same silence isn't reported
    /// on every ten-second pass. See RecommendationAlertPolicy.
    private var notifiedStudents: [UUID: Date] = [:]

    private var extractionTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// The transcript fingerprint the current topic was read from, so an
    /// unchanged transcript is never re-read.
    private var lastExtractionFingerprint: String?
    private var lastExtractionAt: Date?

    /// Recommendations keyed by the facts behind them — see `cacheKey`.
    private var cache: [String: LiveRecommendation] = [:]

    init(
        transcript: TranscriptCaptureService = .shared,
        analyzer: FoundationModelAnalyzer = .shared,
        notifier: MeetingNotifier = .shared
    ) {
        self.transcript = transcript
        self.analyzer = analyzer
        self.notifier = notifier

        // The transcript service is a separate ObservableObject, so a view that
        // observes only this one would never be invalidated when captions start
        // arriving — the same wiring ClassroomViewModel needs for its
        // credentials store.
        transcript.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Task { [weak self] in
            guard let self else { return }
            let availability = await self.analyzer.availability()
            self.modelAvailability = availability
        }
    }

    deinit {
        extractionTask?.cancel()
        generationTask?.cancel()
    }

    // MARK: - Derived

    /// The topic to reason with: the transcript's reading while it is current,
    /// the teacher's own entry otherwise.
    ///
    /// The extracted topic wins while it is fresh because it is a reading of
    /// what is happening *now*, where a typed topic is an assertion about the
    /// lesson as a whole. Once it goes stale the typed one is the better answer.
    var effectiveTopic: ClassTopic? {
        if let topic, Date().timeIntervalSince(topic.capturedAt) < Self.topicLifetime {
            return topic
        }
        return transcript.manualTopic
    }

    var transcriptAvailability: TranscriptAvailability {
        transcript.manualTopic != nil && !transcript.availability.isLive
            ? .manual
            : transcript.availability
    }

    func recommendation(forStudentID id: UUID) -> LiveRecommendation? {
        recommendations.first { $0.studentID == id }
    }

    func weakness(forStudentID id: UUID) -> TopicWeakness? {
        weaknesses[id]
    }

    /// One line explaining why there are no recommendations, when there are
    /// none. Nil when the panel has something to show.
    var emptyStateExplanation: String? {
        guard recommendations.isEmpty else { return nil }

        // A blocked transcript is not a "wait and see" — Zoom's automated
        // captions are a paid-plan feature and a refusal from an account without
        // one will never resolve on its own. Saying only *why* it is blocked
        // left the teacher watching a screen that was never going to fill in, so
        // name the way out: the topic can simply be typed, and that is enough to
        // put the on-device model to work.
        if transcriptAvailability.isBlocked, effectiveTopic == nil {
            return "\(transcriptAvailability.headline) Set the lesson topic and Anchor "
                + "will work from your students' coursework instead."
        }

        if effectiveTopic == nil, !transcript.hasUsableTranscript {
            return "Listening for the topic — or set it yourself and Anchor will start now."
        }

        return "No one needs pulling back in right now."
    }

    // MARK: - The pass

    /// Called once per Zoom poll, after the scores have landed.
    ///
    /// `sensitivity` comes from settings and decides the risk bands, so the
    /// urgency of a recommendation always agrees with the colour of the student
    /// row it came from.
    ///
    /// `notifiesOnHighRisk` is Settings' "Notify when a student crosses high
    /// risk". Passed in rather than read from a shared store, matching the way
    /// `sensitivity` already arrives: the caller owns settings, this owns the
    /// pass. Until it was threaded through, the toggle was wired to nothing and
    /// a teacher who switched notifications off kept receiving them.
    func refresh(
        students: [Student],
        sensitivity: Double,
        notifiesOnHighRisk: Bool,
        now: Date = Date()
    ) {
        scheduleExtractionIfNeeded(now: now)

        let candidates = students.compactMap { student -> RecommendationCandidate? in
            // A score the UI itself refuses to show as a number must not become
            // an instruction to interrupt the lesson — see `Student.hasReliableScore`.
            guard student.hasReliableScore else { return nil }

            return RecommendationCandidate(
                studentID: student.id,
                name: student.name,
                statusSummary: student.statusDescription(now: now),
                struggleScore: student.struggleScore,
                urgency: Self.urgency(
                    for: student.risk(sensitivity: sensitivity)
                ),
                academic: student.academic
            )
        }

        regenerate(
            candidates: candidates,
            topic: effectiveTopic,
            notifiesOnHighRisk: notifiesOnHighRisk,
            now: now
        )
    }

    /// Mirrors `RiskLevel` exactly. Kept as a conversion rather than reusing the
    /// type because `RiskLevel` carries SwiftUI colours and is main-actor bound,
    /// while candidates cross to a background task.
    private static func urgency(for level: RiskLevel) -> LiveRecommendation.Urgency {
        switch level {
        case .high: .high
        case .elevated: .elevated
        case .low: .low
        }
    }

    // MARK: - Topic extraction

    /// Starts a transcript read, if one is warranted.
    private func scheduleExtractionIfNeeded(now: Date) {
        guard extractionTask == nil else { return }
        guard transcript.hasUsableTranscript else { return }

        let fingerprint = transcript.analysisFingerprint

        // Nothing new has been said since the last read.
        guard fingerprint != lastExtractionFingerprint else { return }

        // Something has, but not long enough ago to be worth an inference —
        // unless there is no topic on screen at all, in which case the first
        // reading of the lesson should not wait out the interval.
        if let lastExtractionAt,
           now.timeIntervalSince(lastExtractionAt) < Self.minimumExtractionInterval,
           topic != nil {
            return
        }

        let excerpt = transcript.analysisExcerpt(now: now)
        guard !excerpt.isEmpty else { return }

        lastExtractionFingerprint = fingerprint
        lastExtractionAt = now
        isAnalyzing = true

        extractionTask = Task { [weak self, analyzer] in
            let extracted = await analyzer.extractTopic(from: excerpt, now: now)
            let availability = await analyzer.availability()

            guard let self else { return }

            // Released before anything can return early. `scheduleExtractionIfNeeded`
            // refuses to start a read while this slot is occupied, so leaking it
            // on a cancellation would leave the topic frozen for the rest of the
            // lesson — and the spinner turning forever with it.
            self.extractionTask = nil
            self.isAnalyzing = false

            guard !Task.isCancelled else { return }
            self.modelAvailability = availability

            guard let extracted else {
                // Keep whatever is on screen. A failed read is not evidence that
                // the topic changed, and blanking the panel on a single timeout
                // would make the feature flicker.
                AnchorDiag.log("topic extraction produced nothing; keeping \(self.topic?.topic ?? "no topic")")
                return
            }

            let changed = self.topic?.topic.lowercased() != extracted.topic.lowercased()
            self.topic = extracted

            if changed {
                // A new topic invalidates every cached recommendation: they were
                // all written about the old one.
                self.cache.removeAll()
                AnchorDiag.log("topic is now \"\(extracted.topic)\" (\(extracted.concepts.joined(separator: ", ")))")
            }
        }
    }

    // MARK: - Recommendation generation

    /// Rebuilds the recommendation list.
    ///
    /// Skipped outright while a previous pass is still running rather than
    /// cancelling it: passes are ten seconds apart and inference is the
    /// expensive part, so cancelling one that is nearly finished to start an
    /// almost identical one is pure waste. The next poll picks it up.
    private func regenerate(
        candidates: [RecommendationCandidate],
        topic: ClassTopic?,
        notifiesOnHighRisk: Bool,
        now: Date
    ) {
        guard generationTask == nil else { return }

        guard !candidates.isEmpty else {
            recommendations = []
            weaknesses = [:]
            return
        }

        generationTask = Task { [weak self, analyzer] in
            // Topic matching walks every student's coursework and can reach into
            // NLEmbedding's vector space, so it goes off the main actor — this
            // runs while the dashboard is on screen and animating.
            let matched: [UUID: TopicWeakness] = await Task.detached {
                guard let topic else { return [:] }
                let matcher = TopicMatcher(now: now)
                return candidates.reduce(into: [:]) { result, candidate in
                    let weakness = matcher.weakness(topic: topic, snapshot: candidate.academic)
                    guard !weakness.isEmpty else { return }
                    result[candidate.studentID] = weakness
                }
            }.value

            guard let self else { return }

            // Released up front, for the same reason the extraction slot is:
            // `regenerate` refuses to start while it is occupied, so leaking it
            // would freeze the recommendation list for the rest of the lesson.
            defer { self.generationTask = nil }

            guard !Task.isCancelled else { return }

            // With no topic, only the students in real trouble are worth a card.
            // "Check in — no response for a while" next to a row that already
            // says "Silent 8 min" is duplication, and duplication is what
            // teaches a teacher to stop reading the panel. The section header
            // explains why the topic is missing.
            let eligible = topic == nil
                ? candidates.filter { $0.urgency == .high }
                : candidates

            let ranked = RecommendationGenerator.rank(eligible, weaknesses: matched)
            let generator = RecommendationGenerator(now: now, analyzer: analyzer)

            var built: [LiveRecommendation] = []
            for candidate in ranked {
                if Task.isCancelled { break }

                let weakness = matched[candidate.studentID]
                let key = Self.cacheKey(candidate: candidate, topic: topic, weakness: weakness)

                if let cached = self.cache[key] {
                    built.append(cached)
                    continue
                }

                let recommendation = await generator.recommendation(
                    for: candidate,
                    topic: topic,
                    weakness: weakness
                )
                self.cache[key] = recommendation
                built.append(recommendation)
            }

            // A cancelled pass publishes nothing: `built` is a partial list, and
            // showing two of three recommendations as though they were the whole
            // picture is worse than showing the previous complete one.
            guard !Task.isCancelled else { return }

            self.weaknesses = matched
            self.recommendations = built
            self.trimCache()
            if notifiesOnHighRisk {
                self.announce(built, now: now)
            }
        }
    }

    // MARK: - Notifications

    /// Sends the one recommendation worth a banner this pass, if there is one.
    ///
    /// Posted from here rather than from the view, because a teacher watching
    /// the lesson rather than the dashboard is exactly the case this feature
    /// exists for — the panel they aren't looking at can't tell them anything.
    ///
    /// Which recommendation, and whether to send anything at all, is
    /// `RecommendationAlertPolicy`'s decision; this only carries it out.
    private func announce(_ built: [LiveRecommendation], now: Date) {
        guard notifier.isAuthorized else { return }
        guard let recommendation = alertPolicy.next(
            from: built,
            alreadyNotified: notifiedStudents,
            now: now
        ) else { return }

        notifiedStudents[recommendation.studentID] = now
        notifiedStudents = alertPolicy.pruned(notifiedStudents, now: now)
        notifier.notifyRecommendation(recommendation)

        AnchorDiag.log(
            "notified about \(recommendation.studentName): \(recommendation.headline) "
            + "[\(recommendation.source.rawValue)]"
        )
    }

    /// What a recommendation is "about". Two passes that produce the same key
    /// produce the same words, so the model is not asked twice.
    ///
    /// The struggle score is bucketed to the nearest ten points on purpose: it
    /// drifts by a point or two between polls without the situation changing,
    /// and keying on the raw value would defeat the cache entirely.
    private static func cacheKey(
        candidate: RecommendationCandidate,
        topic: ClassTopic?,
        weakness: TopicWeakness?
    ) -> String {
        let band = candidate.strugglePercent / 10
        let weaknessBand = Int(((weakness?.weaknessScore ?? 0) * 10).rounded())
        return [
            candidate.studentID.uuidString,
            candidate.statusSummary,
            String(band),
            candidate.urgency.rawValue,
            topic?.topic.lowercased() ?? "no-topic",
            topic?.questionLabel ?? "",
            String(weaknessBand)
        ].joined(separator: "|")
    }

    /// The cache is keyed partly on a status string that ticks every minute
    /// ("Silent 8 min" → "Silent 9 min"), so it grows over a lesson. Bounded
    /// here rather than made cleverer: the entries are small and the ceiling is
    /// only there to stop a three-hour session accumulating thousands.
    private func trimCache() {
        let limit = 200
        guard cache.count > limit else { return }
        let keep = cache
            .sorted { $0.value.generatedAt > $1.value.generatedAt }
            .prefix(limit)
        cache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    // MARK: - Manual topic

    /// Records the topic the teacher typed, and drops the cached wording built
    /// without it.
    func setManualTopic(topic: String) {
        transcript.setManualTopic(topic: topic)
        cache.removeAll()
    }

    func clearManualTopic() {
        transcript.clearManualTopic()
        cache.removeAll()
    }

    // MARK: - Lifecycle

    /// Drops everything derived from a meeting: the transcript, the extracted
    /// topic and every recommendation.
    ///
    /// Keeps the topic the teacher typed, so this is safe to call on the
    /// between-meetings path — which Anchor sits in for the whole period before
    /// a class, exactly when a teacher would be entering one.
    func clearLiveState() {
        extractionTask?.cancel()
        extractionTask = nil
        generationTask?.cancel()
        generationTask = nil

        // Pull down any banner still on screen before the list is dropped —
        // afterwards there is nothing left to say which students to clear, and a
        // suggestion about a lesson that has ended is noise.
        notifier.clearRecommendations(studentIDs: recommendations.map(\.studentID))
        notifiedStudents.removeAll()

        topic = nil
        recommendations = []
        weaknesses = [:]
        cache.removeAll()
        lastExtractionFingerprint = nil
        lastExtractionAt = nil
        isAnalyzing = false

        transcript.clearTranscript()
    }

    /// The full reset, typed topic included. For when the session is over rather
    /// than merely between meetings — see `TranscriptCaptureService.clear`.
    func clear() {
        clearLiveState()
        transcript.clearManualTopic()
    }
}
