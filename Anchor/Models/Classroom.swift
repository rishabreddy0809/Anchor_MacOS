//
//  Classroom.swift
//  Anchor
//
//  The long-term record: what happened in a class after the meeting ended.
//
//  Everything live in Anchor is thrown away when a meeting stops — the roster is
//  cleared so nothing stale can sit under a live-looking header. These types are
//  the opposite end of that: the durable, after-the-fact account a teacher opens
//  the next morning to see who was struggling.
//
//  Design rules carried over from the live path:
//
//    * Scores are stored raw. Risk bands are *derived at read time* from the
//      sensitivity setting in force when the teacher looks, so moving the slider
//      re-reads history consistently instead of leaving every past session
//      classified by whatever setting happened to be active that day.
//    * Confidence travels with the score. A session recorded over REST-only
//      data is mostly unscored, and the archive says so rather than showing a
//      confident-looking number a teacher could act on.
//

import Foundation

// MARK: - Classroom

/// A recurring class, grouped by its Zoom meeting ID.
///
/// The meeting ID is stable across every occurrence of a recurring Zoom meeting,
/// which makes it the one identifier that survives the teacher renaming the
/// meeting or Zoom reissuing instance UUIDs.
struct Classroom: Identifiable, Codable, Hashable {
    let id: UUID
    /// Numeric Zoom meeting ID. The grouping key — never changes for a series.
    var zoomMeetingID: String
    /// Most recent topic Zoom reported for this meeting.
    var zoomTopic: String
    /// Teacher's own name for the class, when they've set one.
    var customName: String?
    /// Google Classroom course this recorded class belongs to, when the teacher
    /// has said so. Zoom meetings and Classroom courses share no identifier, so
    /// the tie is one a person makes — never one Anchor infers and stores.
    /// Optional so archives written before linking existed still decode.
    var googleCourseID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        zoomMeetingID: String,
        zoomTopic: String,
        customName: String? = nil,
        googleCourseID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.zoomMeetingID = zoomMeetingID
        self.zoomTopic = zoomTopic
        self.customName = customName
        self.googleCourseID = googleCourseID
        self.createdAt = createdAt
    }

    /// True once the teacher has tied this class to a Classroom course.
    var isLinkedToCourse: Bool { googleCourseID?.trimmed.isEmpty == false }

    /// What the UI shows. A renamed class keeps its own name even when Zoom's
    /// topic changes underneath it.
    var displayName: String {
        if let customName, !customName.trimmed.isEmpty { return customName.trimmed }
        let topic = zoomTopic.trimmed
        return topic.isEmpty ? "Meeting \(zoomMeetingID)" : topic
    }

    /// Shown under the name when the teacher has renamed the class, so the Zoom
    /// meeting it maps to stays discoverable.
    var subtitle: String? {
        guard customName?.trimmed.isEmpty == false else { return nil }
        let topic = zoomTopic.trimmed
        return topic.isEmpty ? "Meeting \(zoomMeetingID)" : topic
    }

    /// Two-letter monogram for the classroom card.
    var initials: String {
        let words = displayName.split { !$0.isLetter && !$0.isNumber }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "#" : String(letters).uppercased()
    }
}

// MARK: - Per-student outcome

/// How one student did in one session.
///
/// A flattened summary rather than the full `Student`: the archive keeps what a
/// teacher would want to review afterwards, not the machinery (feature vectors,
/// accumulators) that produced it.
struct StudentSessionRecord: Identifiable, Codable, Hashable {
    /// Stable across sessions — see `Student.identityKey`.
    var identityKey: String
    var name: String

    /// Score when the session ended.
    var finalScore: Double
    /// Worst reading observed during the session. A student who spent twenty
    /// minutes in the red and recovered by the bell is invisible in `finalScore`
    /// alone, and is exactly who this archive exists to surface.
    var peakScore: Double
    var averageScore: Double
    /// How much of the scoring model the signals covered. See `Student.confidence`.
    var confidence: Double
    /// "model" or "heuristic" — mirrors `Student.ScoreSource`.
    var scoreSource: String

    var speakingSeconds: Int
    var chatMessages: Int
    var handRaiseCount: Int
    var cameraOnRatio: Double
    var minutesPresent: Double
    /// Final `ParticipationStatus` raw value.
    var lastStatus: String
    /// Struggle samples across the session, oldest first.
    var trend: [Double]

    var id: String { identityKey }

    /// Same 0.4 floor the live UI uses: below it the score is a guess and must
    /// not be rendered as a measurement.
    var hasReliableScore: Bool { confidence >= 0.4 }

    var scoreDisplay: String {
        hasReliableScore ? "\(Int((finalScore * 100).rounded()))%" : "—"
    }

    var peakDisplay: String {
        hasReliableScore ? "\(Int((peakScore * 100).rounded()))%" : "—"
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// "42 min" / "1 hr 12 min". Raw minutes read as noise past an hour, and a
    /// long or wrongly-timestamped meeting would otherwise print "4320 min".
    var presenceDisplay: String {
        let minutes = Int(minutesPresent.rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    func risk(sensitivity: Double) -> RiskLevel {
        RiskLevel.level(for: finalScore, sensitivity: sensitivity)
    }

    /// Risk at the student's worst point rather than at the bell.
    func peakRisk(sensitivity: Double) -> RiskLevel {
        RiskLevel.level(for: peakScore, sensitivity: sensitivity)
    }
}

// MARK: - Session

/// One occurrence of a class — a single Zoom meeting instance.
struct ClassSession: Identifiable, Codable, Hashable {
    let id: UUID
    var classroomID: UUID
    /// Zoom's meeting *instance* UUID where available, so re-entering the same
    /// recurring meeting on a later date files as a new session rather than
    /// overwriting the last one.
    var instanceKey: String
    /// Topic as it read on the day.
    var topic: String
    var startedAt: Date
    /// Nil while the class is still running.
    var endedAt: Date?
    /// When the last refresh was folded in. Used to close a session that a crash
    /// or a force-quit left open, giving it a real end time rather than one
    /// invented at next launch.
    var lastSampledAt: Date?
    /// Set when crash recovery closed this session instead of the meeting ending
    /// cleanly, so the UI can present the end time as the lower bound it is.
    /// Optional so archives written before this existed still decode.
    var endedUnexpectedly: Bool?
    var students: [StudentSessionRecord]
    /// Signals Zoom could not supply, recorded so a thin session can explain
    /// itself months later instead of just looking like a quiet class.
    var unavailableSignals: [String]

    init(
        id: UUID = UUID(),
        classroomID: UUID,
        instanceKey: String,
        topic: String,
        startedAt: Date,
        endedAt: Date? = nil,
        lastSampledAt: Date? = nil,
        endedUnexpectedly: Bool? = nil,
        students: [StudentSessionRecord] = [],
        unavailableSignals: [String] = []
    ) {
        self.id = id
        self.classroomID = classroomID
        self.instanceKey = instanceKey
        self.topic = topic
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastSampledAt = lastSampledAt
        self.endedUnexpectedly = endedUnexpectedly
        self.students = students
        self.unavailableSignals = unavailableSignals
    }

    var isLive: Bool { endedAt == nil }

    /// True when the end time is a lower bound rather than a real end.
    var wasInterrupted: Bool { endedUnexpectedly == true }

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    var studentCount: Int { students.count }

    // MARK: Derived risk
    //
    // All of these gate on `hasReliableScore`. A session monitored over REST
    // only has almost no signal, and counting those students as "low risk"
    // would turn an absence of evidence into a clean bill of health — the exact
    // failure the live dashboard already refuses to make.

    var scoredStudents: [StudentSessionRecord] {
        students.filter(\.hasReliableScore)
    }

    var unscoredCount: Int {
        students.count - scoredStudents.count
    }

    func highRiskCount(sensitivity: Double) -> Int {
        scoredStudents.filter { $0.risk(sensitivity: sensitivity) == .high }.count
    }

    func elevatedCount(sensitivity: Double) -> Int {
        scoredStudents.filter { $0.risk(sensitivity: sensitivity) == .elevated }.count
    }

    func engagedCount(sensitivity: Double) -> Int {
        scoredStudents.filter { $0.risk(sensitivity: sensitivity) == .low }.count
    }

    /// Anyone who hit high risk at any point, not just at the bell.
    func everAtRisk(sensitivity: Double) -> [StudentSessionRecord] {
        scoredStudents
            .filter { $0.peakRisk(sensitivity: sensitivity) == .high }
            .sorted { $0.peakScore > $1.peakScore }
    }

    /// Nil when nothing in the session was scored well enough to average.
    var averageScore: Double? {
        let scored = scoredStudents
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0) { $0 + $1.finalScore } / Double(scored.count)
    }

    var averageScoreDisplay: String {
        guard let averageScore else { return "—" }
        return "\(Int((averageScore * 100).rounded()))%"
    }

    /// True when Zoom gave us so little that the session can't be read as a
    /// measurement of anything.
    var isThin: Bool { scoredStudents.isEmpty && !students.isEmpty }

    // MARK: Display

    var dateDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(startedAt, equalTo: Date(), toGranularity: .year)
            ? "EEE d MMM"
            : "EEE d MMM yyyy"
        return formatter.string(from: startedAt)
    }

    var timeRangeDisplay: String {
        let start = Theme.clockString(startedAt)
        guard let endedAt else { return "\(start) · in progress" }
        let range = "\(start) – \(Theme.clockString(endedAt))"
        // Don't present a recovered lower bound as if we watched the class end.
        return wasInterrupted ? "\(range) (interrupted)" : range
    }

    var durationDisplay: String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}
