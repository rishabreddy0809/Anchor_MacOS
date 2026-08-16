//
//  ZoomStudentMapper.swift
//  Anchor
//
//  Converts Zoom participants into the Student objects the dashboard renders,
//  carrying forward per-student history (trend samples, timeline) across polls
//  so the UI shows continuity rather than resetting every two minutes.
//

import Foundation

nonisolated struct ZoomStudentMapper: Sendable {

    /// Struggle samples retained per student for the sparkline and trend arrow.
    static let trendSampleLimit = 60

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func students(
        from participants: [ZoomParticipant],
        chat: [ZoomChat],
        meeting: ZoomMeeting,
        previous: [Student],
        capabilities: ZoomCapabilities,
        /// Google Classroom roster and rollups. Empty when Classroom is not
        /// connected, in which case scoring is Zoom-only exactly as before.
        academic: AcademicMatchTable = AcademicMatchTable(),
        /// True once a retrained model consumes the academic features itself,
        /// which switches the rule-based escalation off.
        modelUsesAcademicFeatures: Bool = false,
        /// Settings' "Include camera-off in scoring". Off, the camera signal is
        /// left out of the vector entirely — see `FeatureCalculator`.
        includesCameraSignal: Bool = true
    ) -> [Student] {
        let calculator = StruggleScoreCalculator(now: now)
        let elapsed = meeting.elapsed
        // Keyed on account identity where Zoom gives us one, so a student who
        // drops and rejoins with a fresh participant id keeps their trend and
        // timeline instead of restarting as a stranger.
        let previousByKey = Dictionary(
            previous.map { ($0.identityKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return participants.map { participant in
            let confidence = calculator.confidence(for: participant, hasChat: !chat.isEmpty)
            let status = calculator.status(for: participant)
            let identityKey = Self.identityKey(for: participant)
            let prior = previousByKey[identityKey]

            // Integrate the instantaneous readings into the accumulators the
            // model needs (seconds unmuted, hand raises) before scoring.
            let signals = (prior?.signals ?? StruggleSignalHistory())
                .advanced(with: participant, now: now)

            // Matched on verified email where Zoom reported one, on an
            // unambiguous display name where it did not. Anyone the roster
            // can't place gets nil and is scored on Zoom signals alone — see
            // AcademicMatchTable.
            let snapshot = academic.snapshot(
                forIdentity: identityKey,
                name: participant.name
            )

            let features = FeatureCalculator(now: now).calculateFeatures(
                from: participant,
                chat: chat,
                meetingElapsed: elapsed,
                history: signals,
                academic: snapshot,
                includesCamera: includesCameraSignal
            )

            // The model is the scorer; the hand-written calculator is the
            // fallback for when it can't be loaded or a prediction throws.
            let modelScore = StruggleDetectionService.shared.probability(for: features)
            let rawScore = modelScore ?? calculator.score(
                for: participant,
                chat: chat,
                meetingElapsed: elapsed
            )

            // Same calibration either way: shrink toward "unknown" in proportion
            // to how little of the signal set we actually observed, so a vector
            // built mostly from placeholders can't read as a confident verdict.
            let calibrated = (rawScore * confidence) + (0.5 * (1 - confidence))

            // Academic escalation goes on *after* calibration. Missing coursework
            // is a fact about the student, not an inference from a thin Zoom
            // feed, so it should not be shrunk toward "unknown" along with the
            // in-meeting signals.
            let escalation = AcademicEscalation(now: now).apply(
                to: calibrated,
                snapshot: snapshot,
                modelUsesAcademicFeatures: modelUsesAcademicFeatures
            )

            // Then the time layers the model has no columns for: a student who
            // was participating and has gone quiet, and the ramp that keeps any
            // of it from being asserted before there's enough session to judge.
            // Ramp goes last so it holds down the whole composite, academic
            // escalation included — a red flag at minute one is a red flag
            // about nothing.
            let drift = EngagementDrift(now: now).apply(
                to: escalation.adjustedScore,
                history: signals
            )

            // And the same layer in reverse: a student who has started talking
            // again should come back down. Drift alone can only stop *adding*
            // points, which leaves the score where it was before they spoke.
            //
            // Mutually exclusive by construction — recovery is gated on the
            // student having engaged within `EngagementDrift.graceSeconds`, and
            // drift only fires past it. One layer owns each regime, so they
            // cannot pull against each other.
            let recovery = EngagementRecovery().apply(
                to: drift.adjustedScore,
                history: signals,
                now: now
            )

            let ramp = ObservationRamp.factor(observedSeconds: signals.observedSeconds)
            let score = recovery.adjustedScore * ramp

            let baseSource: Student.ScoreSource = modelScore == nil ? .heuristic : .model
            let scoreSource = escalation.didEscalate ? baseSource.withAcademic : baseSource

            // One sample per refresh. At the 10-second cadence 60 samples is the
            // last ten minutes; keeping the old 12 would have shrunk the trend
            // to a two-minute window and made "up 20 pts this session" a claim
            // about almost nothing.
            let trend = Array(((prior?.trend ?? []) + [score]).suffix(Self.trendSampleLimit))

            // Only stamp a new status time when the status actually changed.
            let statusSince: Date = {
                guard let prior, prior.status == status else { return now }
                return prior.statusSince
            }()

            var activity = prior?.activity ?? []
            if let event = event(for: participant, previous: prior, status: status) {
                activity.insert(event, at: 0)
            }
            if activity.isEmpty, let joinTime = participant.joinTime {
                activity = [
                    ActivityEvent(
                        kind: .joined,
                        title: "Joined the meeting",
                        detail: nil,
                        timestamp: joinTime
                    )
                ]
            }

            return Student(
                id: prior?.id ?? UUID(),
                identityKey: identityKey,
                name: participant.name,
                struggleScore: score,
                status: status,
                statusSince: statusSince,
                metrics: metrics(for: participant, chat: chat, elapsed: elapsed),
                trend: trend,
                activity: Array(activity.prefix(20)),
                recommendations: AcademicEscalation.recommendations(
                    engagement: [
                        EngagementDrift.recommendation(for: drift, name: participant.name.firstWord)
                    ].compactMap { $0 } + recommendations(
                        score: score,
                        participant: participant,
                        capabilities: capabilities
                    ),
                    snapshot: snapshot,
                    score: score
                ),
                // Recovery is stated before the generic notes: a score that drops
                // without explanation puzzles a teacher exactly as much as one
                // that rises without explanation, and this is the good news.
                note: ObservationRamp.note(observedSeconds: signals.observedSeconds)
                    ?? EngagementRecovery.note(for: recovery, name: participant.name.firstWord)
                    ?? note(for: participant, capabilities: capabilities, calculator: calculator, hasChat: !chat.isEmpty),
                confidence: confidence,
                scoreSource: scoreSource,
                features: features,
                signals: signals,
                academic: snapshot,
                academicEscalation: escalation.didEscalate ? escalation : nil
            )
        }
    }

    // MARK: - Identity

    /// The key the archive uses to recognise this person next week.
    ///
    /// Email first: it survives a display-name change and is the only identifier
    /// a teacher could reconcile against a roster. Then the Zoom user ID, which
    /// is stable per account but opaque. Guests have neither, so they fall back
    /// to their display name — see `Student.identityKey` for what that costs.
    ///
    /// `participant.id` is deliberately not used: it is unique per meeting
    /// *instance*, so keying on it would file every week as a new student.
    static func identityKey(for participant: ZoomParticipant) -> String {
        if let email = participant.email?.trimmed, !email.isEmpty {
            return "email:" + email.lowercased()
        }
        if let userID = participant.userID?.trimmed, !userID.isEmpty {
            return "user:" + userID
        }
        return Student.identityKey(forName: participant.name)
    }

    // MARK: - Metrics

    private func metrics(
        for participant: ZoomParticipant,
        chat: [ZoomChat],
        elapsed: TimeInterval
    ) -> EngagementMetrics {
        let mine = chat.filter {
            $0.senderID == participant.userID || $0.senderName == participant.name
        }

        let cameraRatio: Double
        if let hasVideo = participant.hasVideo {
            cameraRatio = hasVideo ? 1 : 0
        } else {
            cameraRatio = 0        // unknown; the UI labels this "—"
        }

        return EngagementMetrics(
            speakingSeconds: participant.speakingSeconds ?? 0,
            chatMessages: mine.count,
            cameraOnRatio: cameraRatio,
            pollResponses: 0,
            pollsAsked: 0,
            questionsAsked: 0,
            averageResponseSeconds: 0,
            attentionRatio: elapsed > 0
                ? min(1, participant.sessionDuration / elapsed)
                : 0
        )
    }

    // MARK: - Timeline

    private func event(
        for participant: ZoomParticipant,
        previous: Student?,
        status: ParticipationStatus
    ) -> ActivityEvent? {
        guard let previous else {
            return participant.joinTime.map { joinTime in
                ActivityEvent(
                    kind: .joined,
                    title: "Joined the meeting",
                    detail: nil,
                    timestamp: joinTime
                )
            }
        }

        guard previous.status != status else { return nil }

        let kind: ActivityEvent.Kind
        let title: String
        switch status {
        case .silent: kind = .muted; title = "Muted"
        case .unmuted: kind = .unmuted; title = "Unmuted"
        case .speaking: kind = .spoke; title = "Started speaking"
        case .chatting: kind = .chat; title = "Sent a chat message"
        case .cameraOff: kind = .cameraOff; title = "Camera off"
        case .away: kind = .idle; title = "Left the meeting"
        }

        return ActivityEvent(kind: kind, title: title, detail: nil, timestamp: now)
    }

    // MARK: - Guidance

    private func recommendations(
        score: Double,
        participant: ZoomParticipant,
        capabilities: ZoomCapabilities
    ) -> [String] {
        var items: [String] = []

        if !participant.isInMeeting {
            items.append("\(participant.name.firstWord) has left the meeting — check whether they dropped or disconnected.")
            return items
        }

        if score >= 0.70 {
            items.append("Send a private chat check-in rather than cold-calling.")
            items.append("Offer a low-stakes way back in: a poll, a reaction, or a yes/no question.")
        } else if score >= 0.45 {
            items.append("Invite a short verbal response and see whether they take it.")
            items.append("Check in again after the next activity before escalating.")
        } else {
            items.append("Engagement signals look healthy — no action needed.")
        }

        if !capabilities.unavailableSignals.isEmpty {
            items.append(
                "Scored without \(capabilities.unavailableSignals.joined(separator: ", ")) — "
                + "connect the Meeting SDK for a fuller picture."
            )
        }

        return items
    }

    private func note(
        for participant: ZoomParticipant,
        capabilities: ZoomCapabilities,
        calculator: StruggleScoreCalculator,
        hasChat: Bool
    ) -> String? {
        let confidence = calculator.confidence(for: participant, hasChat: hasChat)
        guard confidence < 0.6 else { return nil }
        return String(
            format: "Low confidence (%.0f%%): Zoom's REST API exposes only presence data for this participant.",
            confidence * 100
        )
    }
}

private extension String {
    var firstWord: String { String(split(separator: " ").first ?? "They") }
}
