//
//  Student.swift
//  Anchor
//
//  A monitored participant plus the signals behind their struggle score.
//

import SwiftUI

/// What the student is doing right now, as reported by the meeting platform.
enum ParticipationStatus: String, Hashable, CaseIterable {
    case silent
    case unmuted
    case speaking
    case chatting
    case cameraOff
    case away

    var label: String {
        switch self {
        case .silent: "Silent"
        case .unmuted: "Unmuted"
        case .speaking: "Speaking"
        case .chatting: "Chatting"
        case .cameraOff: "Camera off"
        case .away: "Away"
        }
    }

    var symbolName: String {
        switch self {
        case .silent: "mic.slash"
        case .unmuted: "mic"
        case .speaking: "waveform"
        case .chatting: "bubble.left"
        case .cameraOff: "video.slash"
        case .away: "moon.zzz"
        }
    }
}

/// Aggregate signals for the current session.
struct EngagementMetrics: Hashable {
    var speakingSeconds: Int
    var chatMessages: Int
    var cameraOnRatio: Double      // 0...1
    var pollResponses: Int
    var pollsAsked: Int
    var questionsAsked: Int
    var averageResponseSeconds: Int
    var attentionRatio: Double     // 0...1, share of session with the meeting focused

    var speakingDisplay: String {
        if speakingSeconds >= 60 {
            let minutes = speakingSeconds / 60
            let seconds = speakingSeconds % 60
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }
        return "\(speakingSeconds)s"
    }
}

struct Student: Identifiable, Hashable {

    /// What produced `struggleScore`. Surfaced in the detail view so a teacher
    /// can tell a model prediction from the fallback arithmetic.
    enum ScoreSource: String, Hashable {
        case model
        case heuristic
        /// Model prediction plus the labelled academic adjustment. Distinct from
        /// `.model` so a partly rule-derived number is never read as a pure
        /// prediction — see AcademicEscalation.
        case modelWithAcademic
        case heuristicWithAcademic

        var label: String {
            switch self {
            case .model: "Core ML model"
            case .heuristic: "Signal heuristics"
            case .modelWithAcademic: "Core ML model + academic rules"
            case .heuristicWithAcademic: "Signal heuristics + academic rules"
            }
        }

        var symbolName: String {
            switch self {
            case .model: "brain"
            case .heuristic: "function"
            case .modelWithAcademic, .heuristicWithAcademic: "brain.head.profile"
            }
        }

        /// True when part of the score came from the rule layer rather than the
        /// model.
        var includesAcademic: Bool {
            self == .modelWithAcademic || self == .heuristicWithAcademic
        }

        /// The equivalent source once academic data is folded in.
        var withAcademic: ScoreSource {
            switch self {
            case .model, .modelWithAcademic: .modelWithAcademic
            case .heuristic, .heuristicWithAcademic: .heuristicWithAcademic
            }
        }
    }

    let id: UUID
    /// Stable across meetings, unlike `id` — the archive uses this to recognise
    /// the same person in next week's session.
    ///
    /// Prefers the Zoom account identity (email, then user ID) and falls back to
    /// the display name. The fallback is genuinely weaker: a student who dials in
    /// as "iPhone" one week is a different person to the archive, and two
    /// students sharing a name collapse into one. Both are visible in the UI as
    /// odd history rather than silently wrong scores, and neither can affect a
    /// live score — this key is only ever read after the fact.
    var identityKey: String
    var name: String
    var struggleScore: Double          // 0...1
    var status: ParticipationStatus
    var statusSince: Date
    var metrics: EngagementMetrics
    var trend: [Double]                // recent struggle samples, oldest first
    var activity: [ActivityEvent]      // newest first
    var recommendations: [String]
    var note: String?
    /// How much of the scoring model the available signals cover (0...1).
    /// REST-only data covers very little; a joined bot covers nearly all of it.
    var confidence: Double
    var scoreSource: ScoreSource
    /// The vector handed to the model, kept so the detail view can ask *why*
    /// without re-deriving it from a participant that may have gone away.
    var features: StruggleFeatures?
    /// Cross-poll accumulators, carried forward by ZoomStudentMapper.
    var signals: StruggleSignalHistory
    /// Google Classroom standing, when this student was matched by verified
    /// email. Nil for guests and for classes with no Classroom connection.
    ///
    /// Deliberately not persisted: `SessionArchive` records the score and the
    /// Zoom signals, never a student's grades.
    var academic: AcademicSnapshot?
    /// The itemised academic adjustment behind `struggleScore`, when one was
    /// applied. Kept so the detail view can show the split without re-deriving it.
    var academicEscalation: AcademicEscalationResult?

    init(
        id: UUID = UUID(),
        identityKey: String? = nil,
        name: String,
        struggleScore: Double,
        status: ParticipationStatus,
        statusSince: Date,
        metrics: EngagementMetrics,
        trend: [Double],
        activity: [ActivityEvent],
        recommendations: [String],
        note: String? = nil,
        confidence: Double = 1.0,
        scoreSource: ScoreSource = .heuristic,
        features: StruggleFeatures? = nil,
        signals: StruggleSignalHistory = StruggleSignalHistory(),
        academic: AcademicSnapshot? = nil,
        academicEscalation: AcademicEscalationResult? = nil
    ) {
        self.id = id
        // Defaults to the name so existing call sites keep compiling; the mapper
        // passes the real account identity when Zoom supplies one.
        self.identityKey = identityKey ?? Student.identityKey(forName: name)
        self.name = name
        self.struggleScore = struggleScore
        self.status = status
        self.statusSince = statusSince
        self.metrics = metrics
        self.trend = trend
        self.activity = activity
        self.recommendations = recommendations
        self.note = note
        self.confidence = confidence
        self.scoreSource = scoreSource
        self.features = features
        self.signals = signals
        self.academic = academic
        self.academicEscalation = academicEscalation
    }

    /// True when Google Classroom matched this student.
    var hasAcademicData: Bool { academic?.isEmpty == false }

    /// Name-based identity, normalised so casing and stray whitespace don't
    /// split one student into two rows of history.
    nonisolated static func identityKey(forName name: String) -> String {
        "name:" + name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when this student is only identified by display name, so the UI can
    /// be careful about presenting their cross-session history as certain.
    var hasAccountIdentity: Bool { !identityKey.hasPrefix("name:") }

    var scorePercent: Int { Int((struggleScore * 100).rounded()) }

    /// Below this, the score is a guess and the UI must not present it as a
    /// measurement — it shows "—" instead of a percentage.
    var hasReliableScore: Bool { confidence >= 0.4 }

    /// What to render where a percentage would normally go.
    var scoreDisplay: String { hasReliableScore ? "\(scorePercent)%" : "—" }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var firstName: String { String(name.split(separator: " ").first ?? "") }

    func risk(sensitivity: Double) -> RiskLevel {
        RiskLevel.level(for: struggleScore, sensitivity: sensitivity)
    }

    /// e.g. "Silent 8 min"
    func statusDescription(now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(statusSince) / 60))
        if minutes < 1 { return "\(status.label) just now" }
        return "\(status.label) \(minutes) min"
    }

    /// Direction of travel across the trend samples.
    var trendDelta: Double {
        guard let first = trend.first, let last = trend.last else { return 0 }
        return last - first
    }
}
