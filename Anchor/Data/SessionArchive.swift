//
//  SessionArchive.swift
//  Anchor
//
//  Durable history: every monitored class, kept after the meeting ends.
//
//  `EngagementStore` is deliberately amnesiac — it drops the roster the moment a
//  meeting stops so nothing stale can sit under a live header. This is where the
//  record survives instead, and it is what the Home tab reads.
//
//  Storage is a single JSON file in Application Support. That is a deliberate
//  choice over SwiftData/Core Data: the archive is small (a session is a few KB),
//  the app has no other persistent store to share a container with, and a plain
//  file stays inspectable with `cat` when a teacher reports that last Tuesday
//  looks wrong.
//
//  Threading: the models are MainActor-isolated like the rest of the app, so
//  encoding happens on the main actor and only the resulting `Data` crosses to a
//  background task for the actual disk write.
//

import Combine
import Foundation
import os

final class SessionArchive: ObservableObject {

    /// Shared with the window; the live store writes into this one.
    static let shared = SessionArchive()

    // MARK: - Published state

    /// Newest first.
    @Published private(set) var classrooms: [Classroom] = []
    /// Newest first.
    @Published private(set) var sessions: [ClassSession] = []

    /// True once anything has ever been recorded. Drives the empty state.
    var hasHistory: Bool { !sessions.isEmpty }

    // MARK: - Private

    /// The session currently being written to, if a class is running.
    private var currentSessionID: UUID?
    private var saveTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.anchor.archive", category: "SessionArchive")

    /// Bumped only for changes the decoder can't absorb.
    ///
    /// 2 — archived records moved off Zoom's meeting-local participant id onto
    /// a durable identity. See `migrateIdentities`.
    private static let currentVersion = 2

    private struct ArchiveFile: Codable {
        var version: Int
        var classrooms: [Classroom]
        var sessions: [ClassSession]
    }

    // MARK: - Init

    init(loadsFromDisk: Bool = true) {
        // Before `load()`, and outside its early return: the window has to be
        // right for the Settings UI even on a Mac with no archive yet.
        loadRetention()
        guard loadsFromDisk else { return }
        load()
    }

    deinit {
        saveTask?.cancel()
    }

    // MARK: - Location

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Anchor", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("session-archive.json")
    }

    // MARK: - Load

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let file = try Self.makeDecoder().decode(ArchiveFile.self, from: data)
            classrooms = file.classrooms
            sessions = file.sessions.sorted { $0.startedAt > $1.startedAt }

            if file.version < Self.currentVersion {
                migrateIdentities()
            }

            // A session left open by a crash or a force-quit would otherwise
            // show as "in progress" forever. Close it at its last known sample
            // rather than at launch time, which would invent hours of class.
            closeOrphanedSessions()

            // After closing orphans, so a session the last run left open is
            // given its real end date before being measured against the window
            // — otherwise a crashed session would sit at `endedAt == nil` and
            // outlive the policy forever.
            pruneExpiredSessions()
            pruneStaleSidecarFiles()

            logger.info("Loaded \(self.sessions.count) sessions, \(self.classrooms.count) classrooms")
        } catch {
            // A corrupt archive must not take the app down with it. Keep the bad
            // file for diagnosis rather than silently overwriting the teacher's
            // only copy of the term's history.
            logger.error("Archive unreadable: \(error.localizedDescription, privacy: .public)")
            quarantineArchive()
        }
    }

    /// Re-files records written while the archive still stored Zoom's
    /// meeting-local participant id as a durable identity.
    ///
    /// Every record carries the display name it was recorded under, so each is
    /// re-keyed on its own name rather than on the `user:` id that grouped it —
    /// which is the whole point, because that id never identified a person: in
    /// the archive this migration was written against, one id covered three
    /// different names across thirteen sessions.
    ///
    /// Records sharing a normalised name inside one session are left alone, on
    /// the same reasoning as `durableIdentityKeys`. Verified addresses are
    /// already durable and are never touched.
    private func migrateIdentities() {
        var rewritten = 0

        for index in sessions.indices {
            var counts: [String: Int] = [:]
            for record in sessions[index].students {
                guard let key = Self.durableKey(forRecordedName: record.name) else { continue }
                counts[key, default: 0] += 1
            }

            for studentIndex in sessions[index].students.indices {
                let record = sessions[index].students[studentIndex]
                guard !record.identityKey.hasPrefix("email:"),
                      let key = Self.durableKey(forRecordedName: record.name),
                      key != record.identityKey,
                      counts[key] == 1
                else { continue }
                sessions[index].students[studentIndex].identityKey = key
                rewritten += 1
            }
        }

        logger.info("Migrated \(rewritten) archived records onto durable identities")
        if rewritten > 0 { saveNow() }
    }

    private static func durableKey(forRecordedName name: String) -> String? {
        ClassroomNameKey.make(name).map { "name:" + $0 }
    }

    /// Closes sessions the previous run left open.
    ///
    /// The end time is the last refresh that made it to disk — a lower bound on
    /// when the class actually finished, and the most we can honestly claim.
    /// Marked as interrupted so the UI shows it as approximate rather than
    /// implying Anchor watched the meeting end.
    private func closeOrphanedSessions() {
        for index in sessions.indices where sessions[index].endedAt == nil {
            sessions[index].endedAt = sessions[index].lastSampledAt ?? sessions[index].startedAt
            sessions[index].endedUnexpectedly = true
        }
    }

    private func quarantineArchive() {
        let url = Self.fileURL
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("session-archive.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        classrooms = []
        sessions = []
    }

    // MARK: - Retention

    /// How long a finished session is kept before Anchor deletes it.
    ///
    /// This exists because "kept until you delete it" is not a retention policy,
    /// and a school's reviewer will say so. What the archive holds is a named
    /// child and a behavioural score, which is an education record whatever else
    /// it is; an unbounded one accumulating on a teacher's laptop is the single
    /// hardest thing to defend about how Anchor stores data.
    ///
    /// A term is the default because it is the unit the data is actually useful
    /// over — a teacher looks back across the term they are teaching, not across
    /// years — and because a bounded default is the only kind worth having. An
    /// unbounded default with a setting nobody opens is the same policy with
    /// extra steps.
    enum RetentionWindow: String, CaseIterable, Identifiable, Sendable {
        case term
        case year
        case forever

        var id: String { rawValue }

        var label: String {
            switch self {
            case .term: "One term (120 days)"
            case .year: "One school year (365 days)"
            case .forever: "Keep everything"
            }
        }

        /// Nil means never delete.
        var days: Int? {
            switch self {
            case .term: 120
            case .year: 365
            case .forever: nil
            }
        }

        /// Sessions that ended before this are past the window. Nil when the
        /// window is unbounded.
        func cutoff(from now: Date) -> Date? {
            days.map { now.addingTimeInterval(-Double($0) * 86_400) }
        }

        /// Shown wherever Anchor has to state its own policy in a sentence.
        var policySentence: String {
            switch self {
            case .term:
                "Anchor deletes a session's record 120 days after the class ends."
            case .year:
                "Anchor deletes a session's record 365 days after the class ends."
            case .forever:
                "Anchor keeps session records until you delete them."
            }
        }
    }

    private static let retentionKey = "anchor.archive.retention"

    /// Changing this prunes immediately rather than at the next launch — a
    /// teacher who shortens the window has almost certainly just been asked to.
    @Published var retention: RetentionWindow = .term {
        didSet {
            guard retention != oldValue else { return }
            UserDefaults.standard.set(retention.rawValue, forKey: Self.retentionKey)
            pruneExpiredSessions()
            pruneStaleSidecarFiles()
        }
    }

    private func loadRetention() {
        guard let raw = UserDefaults.standard.string(forKey: Self.retentionKey),
              let stored = RetentionWindow(rawValue: raw)
        else { return }
        // Assigned through the backing store so loading a preference does not
        // trigger the prune-on-change side effect; `load()` prunes explicitly.
        _retention = Published(initialValue: stored)
    }

    /// Drops sessions whose class ended before the retention cutoff.
    ///
    /// A session still in progress is never dropped, however old its start time
    /// looks — `endedAt` is nil until `closeOrphanedSessions` or
    /// `finalizeCurrentSession` sets it, and deleting a live class mid-lesson
    /// would be the worst possible expression of a retention policy.
    func pruneExpiredSessions(now: Date = Date()) {
        guard let cutoff = retention.cutoff(from: now) else { return }

        let before = sessions.count
        sessions = Self.sessionsSurvivingRetention(sessions, cutoff: cutoff)
        let dropped = before - sessions.count
        guard dropped > 0 else { return }

        pruneEmptyClassrooms()
        logger.info("Retention dropped \(dropped) session(s) older than \(self.retention.days ?? 0) days")
        saveNow()
    }

    /// Which sessions survive a given cutoff.
    ///
    /// Extracted from `pruneExpiredSessions` on 2026-08-20 so that the deletion
    /// rule can be tested at all. It could not be before, and the reason is
    /// worth stating because it is a trap rather than an oversight:
    /// `pruneExpiredSessions` ends in `saveNow()`, which writes to the real
    /// `~/Library/Application Support/Anchor/session-archive.json`. **A test
    /// that drove the method directly would have overwritten the running
    /// developer's own class history** — so "just call it and assert" was never
    /// available, and the checklist's note that the mechanics were untested was
    /// describing a real obstacle, not laziness.
    ///
    /// Pure and static, the same shape as `CredentialSeed` and
    /// `ZoomOAuthConfig.canCompleteTokenExchange`: no disk, no MainActor, no
    /// preferences. What the caller keeps is the counting, the logging, the
    /// classroom sweep and the save — none of which is the rule.
    ///
    /// The rule itself is one line longer than it looks, and the extra line is
    /// the important one: **a session still in progress is never dropped**,
    /// however old its start time looks. `endedAt` is nil until
    /// `closeOrphanedSessions` or `finalizeCurrentSession` sets it, and
    /// deleting a live class mid-lesson would be the worst possible expression
    /// of a retention policy. `<` rather than `<=` because a session that ended
    /// exactly on the boundary has not yet outlived the window a teacher was
    /// promised.
    nonisolated static func sessionsSurvivingRetention(
        _ sessions: [ClassSession],
        cutoff: Date
    ) -> [ClassSession] {
        sessions.filter { session in
            guard let endedAt = session.endedAt else { return true }
            return endedAt >= cutoff
        }
    }

    /// Deletes Anchor's own leftover copies of the archive once they age out.
    ///
    /// `quarantineArchive` writes `session-archive.corrupt-<stamp>.json` and
    /// nothing ever removes it, so a corruption a teacher never noticed leaves a
    /// full copy of the term's records beside the live file indefinitely.
    /// Manual pre-migration backups have the same shape. They hold exactly the
    /// data the window above governs, so they are governed by it too.
    ///
    /// Deliberately narrow: only Anchor's two known sidecar patterns, never the
    /// live archive, and never anything else in the directory.
    private func pruneStaleSidecarFiles(now: Date = Date()) {
        guard let cutoff = retention.cutoff(from: now) else { return }

        let live = Self.fileURL.lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Self.directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for url in entries {
            let name = url.lastPathComponent
            guard Self.isPrunableSidecar(name, liveArchiveName: live) else { continue }

            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }

            try? FileManager.default.removeItem(at: url)
            logger.info("Removed archive sidecar past retention: \(name, privacy: .public)")
        }
    }

    /// Whether a file in Anchor's Application Support directory is one of its
    /// own aged-out archive copies.
    ///
    /// Extracted 2026-08-20 for the same reason as
    /// `sessionsSurvivingRetention`, and with more at stake: the caller calls
    /// `FileManager.removeItem`, so this predicate is the only thing standing
    /// between the retention sweep and **deleting a file that is not Anchor's
    /// to delete**. Application Support directories accumulate other people's
    /// data, and a predicate that widened by accident would take it silently —
    /// the sweep runs on every launch and logs only what it removed.
    ///
    /// Two properties are worth stating because both are easy to lose in a
    /// tidy-up. The live archive is excluded **by name passed in** rather than
    /// by a constant, so a test can prove the exclusion without the real path
    /// existing. And the match is `hasPrefix` on Anchor's two known sidecar
    /// shapes only — never a suffix, never `contains`, never "anything starting
    /// with session-archive" — because `session-archive.json` itself starts
    /// that way and a stray `contains` would match a file merely *mentioning*
    /// the name.
    nonisolated static func isPrunableSidecar(_ name: String, liveArchiveName: String) -> Bool {
        guard name != liveArchiveName else { return false }
        return name.hasPrefix("session-archive.corrupt-")
            || name.hasPrefix("session-archive.backup-")
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    // MARK: - Recording

    /// Folds one live refresh into the archive.
    ///
    /// Called on every ingest rather than only at the end, so a class that ends
    /// in a crash, a closed lid or a force-quit still leaves a usable record.
    func record(
        meeting: ZoomMeeting,
        students: [Student],
        capabilities: ZoomCapabilities,
        now: Date = Date()
    ) {
        guard !students.isEmpty else { return }

        let classroom = classroom(forMeetingID: meeting.id, topic: meeting.topic)
        let instanceKey = Self.instanceKey(for: meeting)
        let startedAt = meeting.startTime ?? now

        // A different instance key means a new occurrence of the class — close
        // the old one before opening the next.
        if let currentSessionID,
           let existing = sessions.first(where: { $0.id == currentSessionID }),
           existing.instanceKey != instanceKey {
            finalizeCurrentSession(at: now)
        }

        let index: Int
        if let currentSessionID, let found = sessions.firstIndex(where: { $0.id == currentSessionID }) {
            index = found
        } else if let found = sessions.firstIndex(where: { $0.instanceKey == instanceKey }) {
            // Resuming a session already on file — reconnecting mid-class must
            // extend the existing record, not start a second one for the same hour.
            index = found
            self.currentSessionID = sessions[found].id
        } else {
            let session = ClassSession(
                classroomID: classroom.id,
                instanceKey: instanceKey,
                topic: meeting.topic,
                startedAt: startedAt
            )
            sessions.insert(session, at: 0)
            sessions.sort { $0.startedAt > $1.startedAt }
            index = sessions.firstIndex { $0.id == session.id } ?? 0
            self.currentSessionID = session.id
        }

        // The identity a student is filed under here is not the one the live
        // roster joins on — see `durableIdentityKeys`.
        let durableKeys = Self.durableIdentityKeys(for: students)

        let previousByKey = Dictionary(
            sessions[index].students.map { ($0.identityKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        sessions[index].topic = meeting.topic
        sessions[index].lastSampledAt = now
        sessions[index].unavailableSignals = capabilities.unavailableSignals
        sessions[index].students = students.map { student in
            let key = durableKeys[student.identityKey] ?? student.identityKey
            return Self.record(
                for: student,
                key: key,
                previous: previousByKey[key],
                meeting: meeting,
                now: now
            )
        }

        scheduleSave()
    }

    /// The identity each live student is filed under in the archive, keyed by
    /// the identity they carry live.
    ///
    /// `Student.identityKey` falls back to Zoom's participant id when the
    /// Meeting SDK gives no address, and that id is unique only *within* one
    /// meeting — Zoom recycles the numbers, so `user:16784384` is a different
    /// person next week. It is the right key to join one meeting's refreshes on
    /// and the wrong one to keep: nothing else in the app ever forms a `user:`
    /// key, so a record filed under one can never be matched back to a roster
    /// student, and a term of history silently merges whoever drew that id.
    /// ManualRosterLinks already refuses to persist these, for this reason.
    ///
    /// So the archive re-files them under the durable identity: the verified
    /// address where Zoom gave one, otherwise the normalised display name — the
    /// same `name:` key AcademicMatchTable and CourseHistoryMatch match on.
    ///
    /// Two participants in one meeting whose names normalise the same keep
    /// their meeting-local ids. There, the id genuinely does tell them apart,
    /// and collapsing two people into one row of history is worse than leaving
    /// both unmatched.
    static func durableIdentityKeys(for students: [Student]) -> [String: String] {
        var proposed: [String: String] = [:]
        var counts: [String: Int] = [:]

        for student in students {
            let key: String
            if student.identityKey.hasPrefix("email:") {
                key = student.identityKey
            } else if let nameKey = ClassroomNameKey.make(student.name) {
                key = "name:" + nameKey
            } else {
                key = student.identityKey
            }
            proposed[student.identityKey] = key
            counts[key, default: 0] += 1
        }

        var resolved: [String: String] = [:]
        for (live, durable) in proposed {
            resolved[live] = counts[durable] == 1 ? durable : live
        }
        return resolved
    }

    private static func record(
        for student: Student,
        key: String,
        previous: StudentSessionRecord?,
        meeting: ZoomMeeting,
        now: Date
    ) -> StudentSessionRecord {
        // Peak and average come from the trend rather than from running maxima:
        // the trend already holds every sample this session, so recomputing is
        // both simpler and self-correcting if a refresh was missed.
        let samples = student.trend.isEmpty ? [student.struggleScore] : student.trend
        let peak = max(previous?.peakScore ?? 0, samples.max() ?? student.struggleScore)
        let average = samples.reduce(0, +) / Double(samples.count)

        let elapsed = meeting.startTime.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let minutesPresent = (student.metrics.attentionRatio * elapsed) / 60

        return StudentSessionRecord(
            identityKey: key,
            name: student.name,
            finalScore: student.struggleScore,
            peakScore: peak,
            averageScore: average,
            confidence: student.confidence,
            scoreSource: student.scoreSource.rawValue,
            speakingSeconds: student.metrics.speakingSeconds,
            chatMessages: student.metrics.chatMessages,
            handRaiseCount: student.signals.handRaiseCount,
            cameraOnRatio: student.metrics.cameraOnRatio,
            minutesPresent: max(previous?.minutesPresent ?? 0, minutesPresent),
            lastStatus: student.status.rawValue,
            trend: student.trend
        )
    }

    /// Closes the running session. Safe to call when nothing is open.
    func finalizeCurrentSession(at date: Date = Date()) {
        guard let currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == currentSessionID })
        else {
            self.currentSessionID = nil
            return
        }

        // A session that never captured a scoreable roster is noise in the
        // history — drop it rather than leaving an empty card the teacher has to
        // interpret.
        if sessions[index].students.isEmpty {
            sessions.remove(at: index)
        } else {
            sessions[index].endedAt = date
        }

        self.currentSessionID = nil
        pruneEmptyClassrooms()
        saveNow()

        // The end of a class is the natural moment to apply the window. Anchor
        // is a menu bar app that can stay running for weeks, so relying on the
        // next launch would let a term's worth of records outlive the policy on
        // a Mac that simply never rebooted.
        pruneExpiredSessions(now: date)
    }

    /// Zoom's instance UUID identifies one *occurrence* of a recurring meeting.
    /// Without it, fall back to the meeting ID plus the start time so two
    /// occurrences on different days still file separately.
    private static func instanceKey(for meeting: ZoomMeeting) -> String {
        if let uuid = meeting.uuid, !uuid.isEmpty { return uuid }
        let start = meeting.startTime ?? Date()
        return "\(meeting.id)@\(Int(start.timeIntervalSince1970))"
    }

    // MARK: - Classrooms

    private func classroom(forMeetingID meetingID: String, topic: String) -> Classroom {
        if let index = classrooms.firstIndex(where: { $0.zoomMeetingID == meetingID }) {
            // Keep the topic current so a renamed Zoom meeting doesn't leave the
            // card showing last term's title — unless the teacher set their own.
            if classrooms[index].zoomTopic != topic, !topic.trimmed.isEmpty {
                classrooms[index].zoomTopic = topic
            }
            return classrooms[index]
        }

        let classroom = Classroom(zoomMeetingID: meetingID, zoomTopic: topic)
        classrooms.append(classroom)
        return classroom
    }

    func classroom(id: UUID) -> Classroom? {
        classrooms.first { $0.id == id }
    }

    /// The recorded class for a Zoom meeting, if one has ever been recorded.
    /// Read-only — recording is what creates them.
    func classroom(forZoomMeetingID meetingID: String) -> Classroom? {
        classrooms.first { $0.zoomMeetingID == meetingID }
    }

    /// Teacher's own name for a class. Passing nil or blank restores the Zoom topic.
    func rename(classroomID: UUID, to name: String?) {
        guard let index = classrooms.firstIndex(where: { $0.id == classroomID }) else { return }
        let trimmed = name?.trimmed
        classrooms[index].customName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        saveNow()
    }

    /// Ties a recorded class to a Google Classroom course, or clears the tie
    /// when `courseID` is nil.
    ///
    /// Stored on the classroom rather than inferred at read time: a name match
    /// is a guess that breaks the moment a Zoom topic is edited, and the teacher
    /// is the only one who actually knows which meeting is which class.
    func link(classroomID: UUID, toCourseID courseID: String?) {
        guard let index = classrooms.firstIndex(where: { $0.id == classroomID }) else { return }
        let trimmed = courseID?.trimmed
        classrooms[index].googleCourseID = (trimmed?.isEmpty ?? true) ? nil : trimmed
        saveNow()
    }

    /// Recorded classes the teacher linked to one Classroom course.
    func classrooms(forCourseID courseID: String) -> [Classroom] {
        classrooms.filter { $0.googleCourseID == courseID }
    }

    private func pruneEmptyClassrooms() {
        let used = Set(sessions.map(\.classroomID))
        classrooms.removeAll { !used.contains($0.id) }
    }

    // MARK: - Queries

    /// Sessions for one class, newest first.
    func sessions(forClassroom classroomID: UUID) -> [ClassSession] {
        sessions.filter { $0.classroomID == classroomID }
    }

    func session(id: UUID) -> ClassSession? {
        sessions.first { $0.id == id }
    }

    /// Every appearance of one student in one class, newest first.
    func history(
        forIdentity identityKey: String,
        inClassroom classroomID: UUID
    ) -> [(session: ClassSession, record: StudentSessionRecord)] {
        sessions(forClassroom: classroomID).compactMap { session in
            guard let record = session.students.first(where: { $0.identityKey == identityKey }) else {
                return nil
            }
            return (session, record)
        }
    }

    // MARK: - Aggregates

    /// Everything the Home tab shows on a classroom card.
    struct ClassroomSummary {
        var classroom: Classroom
        var sessionCount: Int
        var lastSession: ClassSession?
        /// Class average per session, oldest first. Sessions with nothing
        /// scoreable are omitted rather than plotted as zero.
        var averageTrend: [Double]
        /// Distinct students seen across all sessions.
        var studentsTracked: Int
        /// Students who reached high risk in more than one session.
        var recurringConcernCount: Int

        /// Change in class average between the two most recent scoreable
        /// sessions. Nil when there aren't two to compare.
        var trendDelta: Double? {
            guard averageTrend.count >= 2 else { return nil }
            return averageTrend[averageTrend.count - 1] - averageTrend[averageTrend.count - 2]
        }
    }

    func summary(for classroom: Classroom, sensitivity: Double) -> ClassroomSummary {
        let all = sessions(forClassroom: classroom.id)
        let identities = Set(all.flatMap { $0.students.map(\.identityKey) })

        return ClassroomSummary(
            classroom: classroom,
            sessionCount: all.count,
            lastSession: all.first,
            // `sessions` is newest first; a trend line reads oldest to newest.
            averageTrend: all.reversed().compactMap(\.averageScore),
            studentsTracked: identities.count,
            recurringConcernCount: recurringConcerns(
                inClassroom: classroom.id,
                sensitivity: sensitivity
            ).count
        )
    }

    /// A student the class keeps losing.
    struct RecurringConcern: Identifiable {
        var identityKey: String
        var name: String
        /// Sessions in which they reached high risk at any point.
        var highRiskSessions: Int
        /// Sessions they attended and were scoreable in.
        var scoredSessions: Int
        var averagePeak: Double
        /// True when they're only identified by display name — their history
        /// could be two people with the same name, or one person who changed it.
        var isNameOnlyIdentity: Bool

        var id: String { identityKey }
    }

    /// Students who hit high risk in more than one session of a class.
    ///
    /// Keyed on peak rather than final score: a student who spends half of every
    /// lesson in the red and rallies at the end is precisely the pattern a
    /// single session recap hides and a term's history should surface.
    func recurringConcerns(
        inClassroom classroomID: UUID,
        sensitivity: Double
    ) -> [RecurringConcern] {
        let all = sessions(forClassroom: classroomID)
        guard all.count >= 2 else { return [] }

        var byIdentity: [String: [StudentSessionRecord]] = [:]
        for session in all {
            for record in session.scoredStudents {
                byIdentity[record.identityKey, default: []].append(record)
            }
        }

        return byIdentity.compactMap { identityKey, records in
            let flagged = records.filter { $0.peakRisk(sensitivity: sensitivity) == .high }
            guard flagged.count >= 2 else { return nil }

            return RecurringConcern(
                identityKey: identityKey,
                name: records.last?.name ?? "Unknown",
                highRiskSessions: flagged.count,
                scoredSessions: records.count,
                averagePeak: flagged.reduce(0) { $0 + $1.peakScore } / Double(flagged.count),
                isNameOnlyIdentity: identityKey.hasPrefix("name:")
            )
        }
        .sorted {
            if $0.highRiskSessions == $1.highRiskSessions { return $0.averagePeak > $1.averagePeak }
            return $0.highRiskSessions > $1.highRiskSessions
        }
    }

    // MARK: - Deletion

    func delete(sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        if currentSessionID == sessionID { currentSessionID = nil }
        pruneEmptyClassrooms()
        saveNow()
    }

    func delete(classroomID: UUID) {
        sessions.removeAll { $0.classroomID == classroomID }
        classrooms.removeAll { $0.id == classroomID }
        if let currentSessionID, session(id: currentSessionID) == nil {
            self.currentSessionID = nil
        }
        saveNow()
    }

    /// Wipes all stored history. Backs the "Clear session data" button.
    func clearAll() {
        sessions = []
        classrooms = []
        currentSessionID = nil
        saveNow()
    }

    // MARK: - Saving

    /// Coalesces the writes that a 10-second refresh would otherwise trigger.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

#if DEBUG
    private var isDemoArchive = false

    /// Replaces the archive in memory for website screenshots.
    ///
    /// Nothing here is written to disk: `isDemoArchive` short-circuits
    /// `saveNow`, so a screenshot session cannot overwrite the real recorded
    /// history of whoever is running it. The flag is one-way on purpose —
    /// once a process has held fabricated sessions, none of them should ever
    /// be persisted.
    func loadDemo(classrooms demoClassrooms: [Classroom], sessions demoSessions: [ClassSession]) {
        isDemoArchive = true
        classrooms = demoClassrooms
        sessions = demoSessions
    }
#endif

    private func saveNow() {
#if DEBUG
        if isDemoArchive { return }
#endif
        saveTask?.cancel()
        saveTask = nil

        let file = ArchiveFile(
            version: Self.currentVersion,
            classrooms: classrooms,
            sessions: sessions
        )

        // Encode here — the models are MainActor-isolated. Only `Data` and the
        // URL cross to the background task.
        let data: Data
        do {
            data = try Self.makeEncoder().encode(file)
        } catch {
            logger.error("Archive encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let directory = Self.directoryURL
        let url = Self.fileURL

        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                // Atomic so a crash mid-write can't leave a truncated archive.
                try data.write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: "com.anchor.archive", category: "SessionArchive")
                    .error("Archive write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
