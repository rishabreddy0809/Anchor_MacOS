//
//  StruggleScoreCalculator.swift
//  Anchor
//
//  Turns Zoom participant signals into the 0...1 struggle score the dashboard
//  renders. This is the seam the ML model will replace: swap the body of
//  `score(for:)` and everything upstream keeps working.
//
//  Design rule: only score signals that are actually present. Optionals that
//  come back nil are *excluded* from the weighted average rather than treated as
//  zero, so a missing mute feed can't manufacture a struggling student.
//

import Foundation

nonisolated struct StruggleScoreCalculator: Sendable {

    /// One contributing signal: a 0...1 severity and how much it counts.
    private struct Signal {
        let severity: Double
        let weight: Double
    }

    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    // MARK: - Scoring

    func score(
        for participant: ZoomParticipant,
        chat: [ZoomChat],
        meetingElapsed: TimeInterval
    ) -> Double {
        var signals: [Signal] = []

        // Silence: no speaking time recorded over a meaningful stretch.
        if let speaking = participant.speakingSeconds {
            let expected = max(30, meetingElapsed * 0.04)   // ~4% of the session
            let ratio = min(1, Double(speaking) / expected)
            signals.append(Signal(severity: 1 - ratio, weight: 0.30))
        }

        if let isMuted = participant.isMuted {
            signals.append(Signal(severity: isMuted ? 0.6 : 0.1, weight: 0.15))
        }

        if let hasVideo = participant.hasVideo {
            signals.append(Signal(severity: hasVideo ? 0.05 : 0.7, weight: 0.15))
        }

        if let handRaised = participant.handRaised, handRaised {
            // A raised hand is engagement, not struggle.
            signals.append(Signal(severity: 0.0, weight: 0.10))
        }

        if let level = participant.audioLevel {
            signals.append(Signal(severity: 1 - (Double(level) / 100), weight: 0.10))
        }

        // Chat participation, when we have a chat feed at all.
        if !chat.isEmpty {
            let mine = chat.filter { message in
                message.senderID == participant.userID || message.senderName == participant.name
            }
            let expected = max(1.0, meetingElapsed / 600)   // ~1 message per 10 min
            let ratio = min(1, Double(mine.count) / expected)
            signals.append(Signal(severity: 1 - ratio, weight: 0.20))
        }

        // Presence: joining late or dropping out is itself a signal, and it is
        // the one thing REST always gives us.
        signals.append(Signal(severity: presenceSeverity(for: participant, meetingElapsed: meetingElapsed), weight: 0.25))

        guard !signals.isEmpty else { return 0.5 }   // no signal → genuinely unknown

        let totalWeight = signals.reduce(0) { $0 + $1.weight }
        let weighted = signals.reduce(0) { $0 + ($1.severity * $1.weight) }
        return min(0.97, max(0.02, weighted / totalWeight))
    }

    private func presenceSeverity(
        for participant: ZoomParticipant,
        meetingElapsed: TimeInterval
    ) -> Double {
        guard participant.isInMeeting else { return 0.95 }   // left the meeting
        guard meetingElapsed > 0, let joinTime = participant.joinTime else { return 0.4 }

        let attended = max(0, now.timeIntervalSince(joinTime))
        let ratio = min(1, attended / meetingElapsed)
        return 1 - ratio                                     // joined late → higher
    }

    /// The score the dashboard should actually display.
    ///
    /// With REST-only data the single available signal (presence) drives every
    /// student to ~0.02 — which reads as "the whole class is thriving" when the
    /// truth is "we have almost no evidence". Shrinking toward 0.5 in proportion
    /// to how much of the model is covered keeps a low-evidence score from
    /// masquerading as a confident all-clear.
    func calibratedScore(
        for participant: ZoomParticipant,
        chat: [ZoomChat],
        meetingElapsed: TimeInterval
    ) -> Double {
        let raw = score(for: participant, chat: chat, meetingElapsed: meetingElapsed)
        let weight = confidence(for: participant, hasChat: !chat.isEmpty)
        return (raw * weight) + (0.5 * (1 - weight))
    }

    // MARK: - Confidence

    /// How much of the scoring model the available signals actually cover, so
    /// the UI can flag low-confidence scores rather than presenting a guess as
    /// a measurement.
    func confidence(for participant: ZoomParticipant, hasChat: Bool) -> Double {
        var covered = 0.25   // presence is always available
        if participant.speakingSeconds != nil { covered += 0.30 }
        if participant.isMuted != nil { covered += 0.15 }
        if participant.hasVideo != nil { covered += 0.15 }
        if participant.audioLevel != nil { covered += 0.10 }
        if hasChat { covered += 0.20 }
        return min(1, covered)
    }

    // MARK: - Status

    /// Best available participation status given what Zoom told us.
    func status(for participant: ZoomParticipant) -> ParticipationStatus {
        if !participant.isInMeeting { return .away }
        if let isMuted = participant.isMuted { return isMuted ? .silent : .unmuted }
        if participant.hasVideo == false { return .cameraOff }
        if participant.handRaised == true { return .unmuted }
        return .silent
    }
}
