//
//  EngagementStore.swift
//  Anchor
//
//  Single source of truth for the popover and the window.
//
//  There is no generated data in Anchor. If Zoom has not delivered a roster,
//  the store is empty and the UI says so — a dashboard that invents students is
//  worse than one that shows nothing, because a teacher can act on it.
//

import Combine
import SwiftUI

final class EngagementStore: ObservableObject {

    /// One source of truth shared by the main window and the menu bar popover,
    /// so both always show the same session.
    static let shared = EngagementStore()

    enum SessionState {
        case running
        case paused

        var isRunning: Bool { self == .running }
    }

    /// Where the dashboard's data comes from.
    enum DataSource: String {
        case none
        case zoom

        var isLive: Bool { self == .zoom }
    }

    // MARK: - Published state

    @Published private(set) var students: [Student] = []
    @Published private(set) var meeting: Meeting?
    @Published private(set) var dataSource: DataSource = .none
    /// One-line connection summary supplied by ZoomViewModel, shown in the UI.
    @Published private(set) var connectionSummary: String?
    @Published private(set) var capabilities = ZoomCapabilities()
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var sessionState: SessionState = .paused
    /// Wall-clock length of the whole session, not of the current poll or of
    /// the stretch since monitoring was last resumed.
    @Published private(set) var elapsed: TimeInterval = 0
    /// When this session began.
    ///
    /// Set on the first ingest and only ever moved *earlier* afterwards: a later
    /// poll that learns the meeting's true start time corrects the clock
    /// backwards, but a fresh `startTime` from Zoom can never push it forward
    /// and restart the count mid-class. Cleared only when the session ends.
    @Published private(set) var sessionStartedAt: Date?
    /// True from the moment a refresh starts until the new scores are in.
    /// Drives the "Updating scores…" indicator on the dashboard.
    @Published private(set) var isScoring = false
    /// Whether the Core ML model loaded, refreshed on every ingest.
    @Published private(set) var modelState: StruggleModelState = .notLoaded
    /// Ticks every second while the popover is open so relative times stay fresh.
    @Published private(set) var now: Date = Date()

    @Published var settings = AppSettings()

    private var scopeObserver: Any?

    init(archive: SessionArchive = .shared) {
        self.archive = archive
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// Takes the previous teacher's class off the screen when the account
    /// changes.
    ///
    /// Deliberately **not** `clear()`. That finalizes the running session into
    /// the archive, and by the time this runs `SessionArchive` may already have
    /// swapped to the incoming teacher's file — the class would be filed under
    /// the wrong person, which is a worse outcome than the one this fixes. An
    /// interrupted session is closed at its last known sample by
    /// `closeOrphanedSessions` the next time its own teacher signs in, which is
    /// exactly the case that path was written for.
    private func accountDidChange() {
        students = []
        meeting = nil
        dataSource = .none
        connectionSummary = nil
        capabilities = ZoomCapabilities()
        lastRefresh = nil
        sessionState = .paused
        elapsed = 0
        sessionStartedAt = nil
        isScoring = false
        liveMeetingIdentifier = nil
        settings.selectedMeetingID = nil
    }

#if DEBUG
    /// Fills the store with the fabricated classroom in `DemoData`, for
    /// photographing the app for the website.
    ///
    /// Writes only to the published properties the dashboard reads, and
    /// deliberately never touches `archive` — a screenshot session must not
    /// leave invented students in the on-disk history of whoever ran it.
    ///
    /// Debug-only for the reason given at the top of DemoData.swift: this
    /// manufactures exactly the kind of data Anchor exists to report honestly,
    /// so no build a teacher runs should be able to reach it.
    func loadDemoData() {
        let demoMeeting = DemoData.meeting
        students = DemoData.students
        meeting = demoMeeting
        dataSource = .zoom
        sessionState = .running
        sessionStartedAt = demoMeeting.startedAt
        elapsed = Date().timeIntervalSince(demoMeeting.startedAt)
        lastRefresh = Date()
        connectionSummary = "Zoom Meeting SDK · 6 participants"
        capabilities = ZoomCapabilities(
            liveMeetingList: true,
            liveParticipants: true,
            muteState: true,
            videoState: true,
            handRaised: true,
            audioLevel: true,
            chat: true
        )
    }
#endif

    // MARK: - Private

    /// Durable history. The store itself stays amnesiac — everything that has to
    /// outlive the meeting is written here on the way past.
    private let archive: SessionArchive

    private var tickTimer: Timer?
    /// How many views currently need the per-second clock. The timer runs while
    /// this is above zero, so the window and the popover can each ask for it
    /// without either one switching the other off.
    private var tickObservers = 0
    private var liveMeetingIdentifier: UUID?
    private var scoringIndicatorTask: Task<Void, Never>?

    deinit {
        tickTimer?.invalidate()
        scoringIndicatorTask?.cancel()
    }

    // MARK: - Derived state

    var hasData: Bool { !students.isEmpty }

    /// Most-struggling first: red flags, then medium, then low.
    ///
    /// Students Anchor has too little signal to score sit below every scored
    /// student regardless of their placeholder number, so the top of the list is
    /// always the students a teacher can actually act on.
    var rankedStudents: [Student] {
        students.sorted { lhs, rhs in
            if lhs.hasReliableScore != rhs.hasReliableScore { return lhs.hasReliableScore }
            if lhs.struggleScore == rhs.struggleScore { return lhs.name < rhs.name }
            return lhs.struggleScore > rhs.struggleScore
        }
    }

    /// The 5 shown on the dashboard before "See All Students".
    var topStudents: [Student] {
        Array(rankedStudents.prefix(5))
    }

    var highRiskCount: Int {
        students.filter { $0.risk(sensitivity: settings.sensitivity) == .high }.count
    }

    var elevatedCount: Int {
        students.filter { $0.risk(sensitivity: settings.sensitivity) == .elevated }.count
    }

    var engagedCount: Int {
        students.filter { $0.risk(sensitivity: settings.sensitivity) == .low }.count
    }

    var classAverageScore: Double {
        guard !students.isEmpty else { return 0 }
        return students.reduce(0) { $0 + $1.struggleScore } / Double(students.count)
    }

    /// Students whose score Anchor does not have enough signal to trust.
    var unscoredCount: Int {
        students.filter { !$0.hasReliableScore }.count
    }

    func student(id: UUID) -> Student? {
        students.first { $0.id == id }
    }

    func risk(for student: Student) -> RiskLevel {
        student.risk(sensitivity: settings.sensitivity)
    }

    var meetingTitle: String { meeting?.title ?? "No meeting" }

    var lastUpdatedDescription: String {
        guard let lastRefresh else { return "Never" }
        return Theme.relativeString(from: lastRefresh, to: now)
    }

    // MARK: - Session control

    func toggleSession() {
        sessionState = sessionState.isRunning ? .paused : .running
    }

    func setSessionState(_ state: SessionState) {
        sessionState = state
    }

    // MARK: - Clock lifecycle

    /// Starts the per-second clock if it isn't already running.
    ///
    /// Balance every call with `removeTickObserver()`. Without this the window
    /// showed frozen relative times — "Silent 3 min" and the elapsed counter
    /// only advanced while the menu bar popover happened to be open.
    func addTickObserver() {
        tickObservers += 1
        guard tickObservers == 1 else { return }
        now = Date()
        startTickTimer()
    }

    func removeTickObserver() {
        tickObservers = max(0, tickObservers - 1)
        guard tickObservers == 0 else { return }
        tickTimer?.invalidate()
        tickTimer = nil
    }

    func popoverDidOpen() { addTickObserver() }

    func popoverDidClose() { removeTickObserver() }

    private func startTickTimer() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        now = Date()
        // Deliberately not gated on `sessionState.isRunning`: pausing stops
        // Anchor scoring, it doesn't stop the class. A teacher who pauses for
        // five minutes and comes back should see how long the session has been
        // running, not a clock that lost the gap.
        guard let startedAt = sessionStartedAt else { return }
        elapsed = max(0, now.timeIntervalSince(startedAt))
    }

    // MARK: - Live ingestion

    func setDataSource(_ source: DataSource) {
        guard dataSource != source else { return }
        dataSource = source
        if source == .none { clear() }
    }

    func setConnectionSummary(_ summary: String?) {
        connectionSummary = summary
    }

    /// Called by ZoomViewModel when a poll starts.
    ///
    /// The indicator is delayed rather than shown immediately: on the bot path a
    /// whole refresh takes milliseconds, and at a 10-second cadence an
    /// undelayed spinner would strobe six times a minute. Only a refresh slow
    /// enough to be worth waiting on — a REST round-trip, a stalled request —
    /// ever surfaces one.
    func beginRefresh() {
        scoringIndicatorTask?.cancel()
        scoringIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.isScoring = true
        }
    }

    func endRefresh() {
        scoringIndicatorTask?.cancel()
        scoringIndicatorTask = nil
        isScoring = false
    }

    /// Drops the roster. Called when the meeting ends or Zoom disconnects, so
    /// stale students never linger under a live-looking header.
    ///
    /// This is also where a class is declared over: the archive closes the
    /// running session here, which is the only reason any of it survives.
    func clear() {
        archive.finalizeCurrentSession()
        // Deliberately does *not* drop the Classroom rollups.
        //
        // It used to, on the reasoning that grades have no reason to outlive the
        // class that needed them. The reasoning is sound; the moment was wrong.
        // This runs on **every poll** while Zoom is waiting for a meeting — the
        // state Anchor sits in for all the hours between lessons — so a
        // coursework sync was wiped roughly ten seconds after it landed, and
        // Home's course cards fell back to "Syncing coursework…" until the next
        // sync ten minutes later, which was then wiped in its turn. Those cards
        // exist to be read *between* classes; tying their data to a live meeting
        // left them empty almost all the time.
        //
        // The privacy boundary that actually matters is still enforced, in the
        // two places a teacher would expect: `ClassroomViewModel.disconnect()`
        // drops everything when they sign out of Google, and `setMonitored(false)`
        // drops a class's rollups when they stop watching it. Nothing here is
        // ever written to disk — see `snapshotsByCourse`.
        ClassroomViewModel.shared.setActiveCourse(id: nil)
        // Meeting-local links go with the meeting: Zoom reuses in-meeting
        // participant ids, so keeping one would eventually point a student's
        // grades at a stranger. Durable links (email/name) survive.
        ManualRosterLinks.shared.clearSession()
        students = []
        meeting = nil
        elapsed = 0
        sessionStartedAt = nil
        sessionState = .paused
        capabilities = ZoomCapabilities()
        liveMeetingIdentifier = nil
        settings.selectedMeetingID = nil
    }

    /// Replaces the roster with live Zoom data, preserving per-student history.
    func ingest(
        meeting zoomMeeting: ZoomMeeting,
        participants: [ZoomParticipant],
        chat: [ZoomChat],
        capabilities newCapabilities: ZoomCapabilities
    ) {
        dataSource = .zoom
        capabilities = newCapabilities

        let timestamp = Date()
        let mapper = ZoomStudentMapper(now: timestamp)

        // Academic data is read live rather than passed in, so a Classroom sync
        // that lands between Zoom polls is picked up on the next refresh without
        // the Zoom path having to know Classroom exists.
        let classroom = ClassroomViewModel.shared
        let usesAcademicFeatures = StruggleDetectionService.shared.usesAcademicFeatures

        // Which of the monitored classes this meeting *is*, when the teacher has
        // said so on Home. With several classes monitored this is what keeps one
        // class's coursework off another class's meeting; unlinked, the scorer
        // falls back to every monitored roster at once.
        let linkedCourseID = archive.classroom(forZoomMeetingID: zoomMeeting.id)?.googleCourseID
        classroom.setActiveCourse(id: linkedCourseID)

        Self.traceIdentities(
            participants: participants,
            classroom: classroom,
            courseID: linkedCourseID
        )

        students = mapper.students(
            from: participants,
            chat: chat,
            meeting: zoomMeeting,
            previous: students,
            capabilities: newCapabilities,
            academic: classroom.matchTable(forCourseID: linkedCourseID),
            modelUsesAcademicFeatures: usesAcademicFeatures,
            includesCameraSignal: settings.includesCameraSignal
        )

        let identifier = liveMeetingIdentifier ?? UUID()
        liveMeetingIdentifier = identifier

        meeting = Meeting(
            id: identifier,
            title: zoomMeeting.topic,
            platform: .zoom,
            isLive: zoomMeeting.isLive,
            startedAt: zoomMeeting.startTime ?? timestamp,
            participantCount: participants.filter(\.isInMeeting).count,
            hostName: zoomMeeting.hostEmail ?? "Host"
        )
        settings.selectedMeetingID = identifier

        // Earliest known start wins — see `sessionStartedAt`. Zoom's own start
        // time is preferred when it has one, so a bot that joins ten minutes
        // into a class reports the class's elapsed time rather than its own.
        let reportedStart = zoomMeeting.startTime ?? timestamp
        sessionStartedAt = min(sessionStartedAt ?? reportedStart, reportedStart)
        elapsed = max(0, timestamp.timeIntervalSince(sessionStartedAt ?? timestamp))
        sessionState = zoomMeeting.isLive ? .running : .paused
        lastRefresh = timestamp
        now = timestamp
        modelState = StruggleDetectionService.shared.state
        isScoring = false

        // Fold this refresh into the durable record. Done on every ingest rather
        // than only at the end, so a class that dies with a closed lid or a
        // crashed app still leaves the teacher something to review.
        archive.record(
            meeting: zoomMeeting,
            students: students,
            capabilities: newCapabilities,
            now: timestamp
        )
    }

    /// Students whose score came from the Core ML model rather than the fallback.
    var modelScoredCount: Int {
        students.filter { $0.scoreSource == .model }.count
    }

    // MARK: - Identity tracing

    /// Prints both sides of the Classroom match — what Zoom said, what the
    /// roster holds, and the verdict for each participant.
    ///
    /// "Not linked" is the one failure a teacher can see but not diagnose: the
    /// panel can't say whether Zoom withheld the address, the roster spells the
    /// name differently, or two students collided. This puts all three in the
    /// console. Debug builds only — see AnchorDiag.
    private static func traceIdentities(
        participants: [ZoomParticipant],
        classroom: ClassroomViewModel,
        courseID: String?
    ) {
        let table = classroom.matchTable(forCourseID: courseID)

        // Which rosters are in play is half the diagnosis once several classes
        // are monitored: a name that matches nothing may simply be in a class
        // this meeting was never linked to.
        let scope = courseID
            .flatMap { id in classroom.courses.first { $0.id == id }?.name }
            ?? (classroom.isMonitoringAnyCourse
                ? "all \(classroom.monitoredCourseIDs.count) monitored classes"
                : "no classes monitored")

        let roster = courseID.map { classroom.rosters[$0] ?? [] } ?? classroom.monitoredRoster

        AnchorDiag.logIfChanged(
            key: "roster",
            "roster[\(scope)]: "
            + (roster.isEmpty
                ? "not loaded"
                : roster
                    .map { "\"\($0.name)\" → nameKey=\($0.nameMatchKey ?? "nil") "
                        + "email=\($0.email ?? "withheld by Google")" }
                    .joined(separator: " | "))
        )

        let lines = participants.map { participant -> String in
            let identityKey = ZoomStudentMapper.identityKey(for: participant)
            let verdict: String
            switch table.match(forIdentity: identityKey, name: participant.name) {
            case .verified(let student): verdict = "LINKED (email) → \(student.name)"
            case .byName(let student): verdict = "LINKED (name, unverified) → \(student.name)"
            case .manual(let student): verdict = "LINKED (manual) → \(student.name)"
            case nil: verdict = "NOT LINKED"
            }
            return "\"\(participant.name)\" zoomEmail=\(participant.email ?? "none") "
                + "identity=\(identityKey) "
                + "nameKey=\(ClassroomNameKey.make(participant.name) ?? "nil") → \(verdict)"
        }

        AnchorDiag.logIfChanged(key: "identities", "match: " + lines.joined(separator: " | "))
    }
}
