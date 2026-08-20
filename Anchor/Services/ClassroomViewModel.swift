//
//  ClassroomViewModel.swift
//  Anchor
//
//  Connection state, which classes are monitored, and the 10-minute sync loop for
//  Google Classroom. Counterpart to ZoomViewModel.
//
//  The sync deliberately runs on its own clock, decoupled from Zoom's 10-second
//  scoring pass: assignment data changes on the order of days, and re-fetching a
//  whole course every 10 seconds would be pure waste. The scorer reads whatever
//  the last sync cached.
//
//  The pass itself is as short as it can be made — classes sync a few at a time,
//  and within a class the roster and coursework calls overlap. That is not about
//  the 10-minute cadence but about the two moments a teacher actually waits on
//  one: signing in, and switching a class on.
//
//  Any number of classes can be monitored, and each is synced and reported on
//  separately. Pooling them would be the easy implementation and the wrong one:
//  a course card must be able to report its own missing work, and a meeting must
//  be scored against the one class it belongs to — the class its recorded class
//  was linked to on Home. Only a meeting Anchor can't place falls back to every
//  monitored roster at once.
//
//  Failure is always non-fatal. If Classroom is unreachable, unauthorised or
//  rate limited, `snapshots` keeps its last good value (or stays empty) and the
//  dashboard falls back to Zoom-only scoring — the class is happening now and a
//  Google outage must not stop it being monitored.
//

import Combine
import Foundation
import SwiftUI
import os

@MainActor
final class ClassroomViewModel: ObservableObject {

    // MARK: - State

    enum ConnectionState: Equatable {
        case notConnected
        case connecting
        case connected(email: String?)
        case failed(ClassroomError)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .notConnected: "Not connected"
            case .connecting: "Connecting…"
            case .connected(let email): email ?? "Connected"
            case .failed: "Disconnected"
            }
        }

        var symbolName: String {
            switch self {
            case .notConnected: "circle.dashed"
            case .connecting: "arrow.triangle.2.circlepath"
            case .connected: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }

    @Published private(set) var state: ConnectionState = .notConnected
    @Published private(set) var courses: [ClassroomCourse] = []
    /// The courses Anchor syncs coursework for.
    ///
    /// A set rather than one course: a teacher takes several classes, and there
    /// is no reason the academic half of Anchor should work for only one of
    /// them. Each meeting still resolves to a *single* class — the one its
    /// recorded class is linked to — so watching more classes never means mixing
    /// two rosters together while scoring. See `matchTable(forCourseID:)`.
    @Published private(set) var monitoredCourseIDs: Set<String> = []
    /// Roster per course id — names and emails only, never grades, and never
    /// written to disk. Home reads it for the "N students" line on every card,
    /// which is why it is kept for *all* courses rather than only the monitored
    /// ones; a card that couldn't say how big the class is would look broken.
    @Published private(set) var rosters: [String: [ClassroomStudent]] = [:]
    /// True while the course list (and its rosters) are being fetched, so Home
    /// can show progress instead of an empty grid.
    @Published private(set) var isLoadingCourses = false
    /// Academic rollups per course id, each keyed by `email:…` — the same key
    /// space as `Student.identityKey`, so matching is a dictionary lookup.
    ///
    /// Kept split by course rather than pooled: a course's card must be able to
    /// report *its* missing work, not the sum of every class the teacher takes.
    @Published private(set) var snapshotsByCourse: [String: [String: AcademicSnapshot]] = [:]
    @Published private(set) var lastSyncedByCourse: [String: Date] = [:]
    /// Why each course's last sync attempt failed, cleared the moment one
    /// succeeds. A course with an entry here and no `lastSyncedByCourse` entry
    /// has never synced and is currently failing — which is a different thing to
    /// tell the teacher than "still working on it".
    @Published private(set) var lastSyncErrorByCourse: [String: ClassroomError] = [:]
    @Published private(set) var syncingCourseIDs: Set<String> = []
    /// Whether the ten-minute loop is alive.
    ///
    /// Distinct from `isSyncing`, which is only true during the seconds a
    /// request is actually in flight. The UI needs both: a course that has never
    /// synced means "any moment now" while the loop is running and "this is
    /// never going to happen" once it has stopped, and those must not look the
    /// same on screen. `handle(_:)` stops the loop on any error that needs the
    /// teacher, so the second case is reachable and was previously invisible.
    @Published private(set) var isSyncActive = false
    @Published private(set) var lastError: ClassroomError?
    /// Students on the monitored rosters with no email — they can never be matched.
    @Published private(set) var unmatchableStudentCount = 0

    /// Students who can only be matched by name and share that name with
    /// someone else on the roster, so Anchor refuses to guess between them.
    /// Separate from `unmatchableStudentCount` because the recovery is
    /// different — this one is a manual link away. See `RosterMatchability`.
    @Published private(set) var ambiguouslyNamedStudentCount = 0
    /// The monitored course the live meeting belongs to, when its recorded class
    /// has been linked to one. Written by `EngagementStore` on each ingest — the
    /// view model has no way to know which Zoom meeting is running.
    @Published private(set) var activeCourseID: String?

    static let shared = ClassroomViewModel()

#if DEBUG
    /// Presents a connected, monitored Google Classroom course without one,
    /// for website screenshots. Performs no network calls and writes nothing.
    private var isDemoClassroom = false

    func applyDemoClassroom(
        course: ClassroomCourse,
        roster demoRoster: [ClassroomStudent],
        snapshots: [String: AcademicSnapshot]
    ) {
        isDemoClassroom = true
        state = .connected(email: DemoData.teacherEmail)
        courses = [course]
        monitoredCourseIDs = [course.id]
        rosters[course.id] = demoRoster
        snapshotsByCourse[course.id] = snapshots
        lastSyncedByCourse[course.id] = Date()
        isLoadingCourses = false
        lastError = nil
    }
#endif

    // MARK: - Dependencies

    private let service: ClassroomDataProviding
    private let credentials: GoogleCredentialsStore
    private let links: ManualRosterLinks
    private let oauth = GoogleOAuthClient()
    private var syncTask: Task<Void, Never>?
    /// The course-list fetch in flight, so concurrent callers wait for it rather
    /// than each starting their own — or, worse, returning as though it was
    /// already done. See `loadCourses()`.
    private var courseLoadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Assignment data moves on the order of days; 10 minutes is already
    /// generous and keeps a full course refresh cheap.
    private static let syncInterval: TimeInterval = 600

    // MARK: - Persisted selection

    /// Only the course *ids* are remembered, in UserDefaults. No student data,
    /// no grades — those never leave memory.
    private static let monitoredCoursesKey = "anchor.classroom.monitoredCourseIDs"
    /// Written by the versions that could only watch one class at a time.
    /// Migrated on first read, then removed.
    private static let legacySelectedCourseKey = "anchor.classroom.selectedCourseID"

    init(
        service: ClassroomDataProviding? = nil,
        credentials: GoogleCredentialsStore = .shared,
        links: ManualRosterLinks = .shared
    ) {
        self.credentials = credentials
        self.links = links
        self.service = service ?? GoogleClassroomService(credentials: credentials)

        if credentials.isConnected {
            state = .connected(email: credentials.tokens?.accountEmail)
        }

        // `isConnected` and `hasClientID` read through to GoogleCredentialsStore,
        // a separate ObservableObject. Views that observe only this view model
        // — the student detail's ACADEMIC panel among them — would otherwise
        // never be invalidated when a sign-in lands, and would sit on a stale
        // "not connected" reading while Settings showed the opposite.
        credentials.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Same reason: `matchTable` reads through to the link store, so a link
        // the teacher just made has to invalidate the panels that show it —
        // otherwise the row keeps saying "Not linked" until the next poll.
        links.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    deinit {
        syncTask?.cancel()
    }

    var isConnected: Bool { credentials.isConnected }
    var hasClientID: Bool { credentials.hasClientID }

    // MARK: - Monitored courses

    /// Monitored courses in the order Google listed them, so the UI never
    /// reshuffles them between launches.
    var monitoredCourses: [ClassroomCourse] {
        courses.filter { monitoredCourseIDs.contains($0.id) }
    }

    func isMonitored(courseID: String) -> Bool {
        monitoredCourseIDs.contains(courseID)
    }

    var isMonitoringAnyCourse: Bool { !monitoredCourseIDs.isEmpty }

    var isSyncing: Bool { !syncingCourseIDs.isEmpty }

    func isSyncing(courseID: String) -> Bool { syncingCourseIDs.contains(courseID) }

    /// Most recent sync across every monitored course.
    var lastSyncedAt: Date? { lastSyncedByCourse.values.max() }

    func lastSynced(courseID: String) -> Date? { lastSyncedByCourse[courseID] }

    /// Why this course's last sync attempt failed, or nil if the last one
    /// worked. A course can have both this and a `lastSynced` date: the data on
    /// screen is real but stale, which is worth saying differently to never
    /// having synced at all.
    func lastSyncError(courseID: String) -> ClassroomError? { lastSyncErrorByCourse[courseID] }

    func snapshots(forCourse courseID: String) -> [String: AcademicSnapshot] {
        snapshotsByCourse[courseID] ?? [:]
    }

    /// Every monitored course's rollups in one dictionary, combining the classes
    /// a student takes more than one of. Course-specific screens read
    /// `snapshots(forCourse:)` instead.
    var snapshots: [String: AcademicSnapshot] {
        var merged: [String: AcademicSnapshot] = [:]
        for courseID in monitoredCourses.map(\.id) {
            for (key, snapshot) in snapshotsByCourse[courseID] ?? [:] {
                merged[key] = merged[key].map { $0.combined(with: snapshot) } ?? snapshot
            }
        }
        return merged
    }

    /// The class the meeting on screen is about: the one its recorded class was
    /// linked to, or the only monitored class when there is just the one. Nil
    /// when several classes are monitored and nothing says which is running —
    /// the UI then talks about "your monitored classes" rather than naming the
    /// wrong one.
    var activeCourse: ClassroomCourse? {
        if let activeCourseID, let course = courses.first(where: { $0.id == activeCourseID }) {
            return course
        }
        return monitoredCourseIDs.count == 1 ? monitoredCourses.first : nil
    }

    /// What to call the class in copy addressed to the teacher.
    var activeCourseLabel: String {
        if let activeCourse { return activeCourse.name }
        let count = monitoredCourseIDs.count
        if count == 0 { return "your classes" }
        return "your \(count) monitored classes"
    }

    /// Told by `EngagementStore` which course the live meeting belongs to.
    func setActiveCourse(id: String?) {
        guard activeCourseID != id else { return }
        activeCourseID = id
    }

    /// Every monitored course's roster, a student who takes two of them counted
    /// once.
    var monitoredRoster: [ClassroomStudent] {
        var seen: Set<String> = []
        var roster: [ClassroomStudent] = []
        for course in monitoredCourses {
            for student in rosters[course.id] ?? [] where seen.insert(student.id).inserted {
                roster.append(student)
            }
        }
        return roster
    }

    // MARK: - Partial grants
    //
    // Google hands back whatever the teacher ticked, and won't offer a scope at
    // all unless the Cloud console project lists it under Data access. Anchor
    // connects with what it was given and switches off only the features that
    // depend on what it wasn't — a class list is worth having even when
    // coursework is out of reach.

    /// Classroom permissions asked for but not granted.
    var missingScopes: [String] { credentials.tokens?.missingClassroomScopes ?? [] }

    /// Coursework, grades and missing-work counts all come from these two calls;
    /// without both scopes there is nothing to score academically.
    var canReadCoursework: Bool {
        let granted = credentials.tokens?.grantedScopes ?? []
        return granted.contains("https://www.googleapis.com/auth/classroom.coursework.students")
            && granted.contains("https://www.googleapis.com/auth/classroom.student-submissions.students.readonly")
    }

    /// What a partial grant actually costs the teacher, in their terms. Nil when
    /// Google granted everything.
    var scopeWarning: String? {
        guard isConnected else { return nil }
        let missing = missingScopes
        guard !missing.isEmpty else { return nil }

        let granted = credentials.tokens?.grantedClassroomScopes.count ?? 0
        let total = GoogleOAuthConfig.classroomScopes.count
        let names = missing.map(GoogleOAuthConfig.shortScopeName).joined(separator: ", ")

        let cost = canReadCoursework
            ? "Your classes and rosters still load."
            : "Your classes and rosters still load, but Anchor can't read assignments, "
                + "grades or missing work, so coursework won't affect any student's score."

        // The instruction here used to be "add the scope in the Google Cloud
        // console under APIs & Services → OAuth consent screen → Data access,
        // then disconnect and reconnect here", and it was wrong twice over.
        //
        // Wrong about the reader: a teacher has no Cloud project and cannot
        // open that console. Neither vocabulary scan caught it — the view scan
        // reads `Anchor/Views` and this is a service; the enum scan reads
        // ZoomError and ClassroomError and this is a computed string.
        //
        // Wrong about the cause, which matters more. Google presents the four
        // Classroom permissions as **separate tick boxes** on its own consent
        // screen, and QA-PROTOCOL.md records that a teacher ticking three of
        // four is likely rather than hypothetical. That is far and away the
        // common way to arrive here, and the app already requests every scope
        // it needs — so nothing in any console is missing. The fix is to
        // reconnect and leave the boxes ticked, which is two clicks away in the
        // window they are already looking at.
        return "Google granted \(granted) of \(total) Classroom permissions — missing "
            + "\(names). \(cost) Google asks for these as separate tick boxes, so the "
            + "usual cause is one being left unticked. Disconnect and connect again, "
            + "and accept all of them."
    }

    // MARK: - Connect

    /// Runs the browser sign-in, then loads the course list.
    func connect() async {
        guard let config = credentials.config() else {
            state = .failed(.missingClientID)
            lastError = .missingClientID
            return
        }

        state = .connecting
        lastError = nil

        do {
            let tokens = try await oauth.authorize(config: config)
            credentials.save(tokens)
            state = .connected(email: tokens.accountEmail)
            await loadCourses()
            restoreMonitoredCourses()
        } catch let error as ClassroomError {
            state = .failed(error)
            lastError = error
        } catch {
            let wrapped = ClassroomError.authorizationFailed(error.localizedDescription)
            state = .failed(wrapped)
            lastError = wrapped
        }
    }

    /// Signs out and drops everything held about students.
    func disconnect() {
        stopSync()
        credentials.disconnect()
        courses = []
        monitoredCourseIDs = []
        activeCourseID = nil
        // Rosters go with the account they came from, not with the meeting —
        // `clearStudentData` deliberately leaves them alone so Home keeps
        // working between classes.
        rosters = [:]
        clearStudentData()
        state = .notConnected
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.monitoredCoursesKey)
        UserDefaults.standard.removeObject(forKey: Self.legacySelectedCourseKey)
    }

    /// Drops every piece of student information held in memory.
    ///
    /// Called on disconnect and when monitoring stops — grades have no reason to
    /// outlive the session that needed them.
    func clearStudentData() {
        snapshotsByCourse = [:]
        lastSyncedByCourse = [:]
        lastSyncErrorByCourse = [:]
        unmatchableStudentCount = 0
        ambiguouslyNamedStudentCount = 0
    }

    // MARK: - Courses

    /// Fetches the course list, or waits for the fetch already running.
    ///
    /// The waiting matters. Two callers race at launch — `restoreIfConnected`
    /// and Home's `.task` — and this used to return immediately when it found
    /// one in flight, which told the caller "loaded" while `courses` was still
    /// empty. `restoreIfConnected` then ran `restoreMonitoredCourses` against an
    /// empty list, so the sync loop started with two monitored *ids* that
    /// resolved to no courses, did nothing, and slept for ten minutes. The cards
    /// meanwhile rendered from the list the other load eventually produced, so
    /// the class sat on "Syncing coursework…" with nothing behind it — and
    /// toggling monitoring was the only way to force a real sync, because that
    /// path syncs a course id directly.
    func loadCourses() async {
#if DEBUG
        // Screenshot mode holds a fabricated course. A real fetch landing on
        // top of it replaces the roster mid-capture and empties the Insights
        // tab — which is exactly what happened before this guard existed.
        if isDemoClassroom { return }
#endif
        if let courseLoadTask {
            await courseLoadTask.value
            return
        }

        let task = Task { [weak self] () -> Void in await self?.performLoadCourses() }
        courseLoadTask = task
        await task.value
        courseLoadTask = nil
    }

    private func performLoadCourses() async {
#if DEBUG
        // Screenshot mode holds a fabricated course. A real fetch landing on
        // top of it replaces the roster mid-capture and empties the Insights
        // tab — which is exactly what happened before this guard existed.
        if isDemoClassroom { return }
#endif
        isLoadingCourses = true
        defer { isLoadingCourses = false }

        do {
            courses = try await service.courses().filter(\.isActive)
            lastError = nil
        } catch let error as ClassroomError {
            handle(error)
            return
        } catch {
            handle(.network(error.localizedDescription))
            return
        }

        await loadRosters()
        pruneMonitoredCourses()
        autoMonitorSoleCourse()
    }

    /// One roster call per course, a few at a time.
    ///
    /// This is what Home waits on at launch, and the calls are independent, so
    /// running them in sequence made a teacher with a dozen courses stare at a
    /// spinner for a dozen round trips. Bounded rather than unbounded — see
    /// `ClassroomConcurrency`.
    ///
    /// A roster that fails is skipped rather than failing the whole load: one
    /// archived course the teacher can't read must not blank out the other
    /// eleven.
    private func loadRosters() async {
        let ids = courses.map(\.id)
        let service = self.service

        let fetched = try? await ClassroomConcurrency.map(ids) { id -> (String, [ClassroomStudent])? in
            guard let students = try? await service.students(courseID: id) else { return nil }
            return (id, students)
        }

        if Task.isCancelled { return }

        var loaded: [String: [ClassroomStudent]] = [:]
        for entry in (fetched ?? []).compactMap({ $0 }) { loaded[entry.0] = entry.1 }

        // Merge rather than replace, then drop rosters for courses that are no
        // longer in the list: a course whose roster call failed keeps the copy
        // it had instead of blanking its card.
        let live = Set(ids)
        rosters = rosters.merging(loaded) { _, new in new }.filter { live.contains($0.key) }
    }

    /// With exactly one active course there is no ambiguity about which class is
    /// being taught, and making the teacher go and pick it in Settings is the
    /// difference between Anchor showing coursework and showing nothing at all.
    ///
    /// With two or more, Anchor stays quiet rather than monitoring the lot:
    /// syncing coursework is one call per assignment per class, and a teacher
    /// with eight courses shouldn't have all eight polled because they signed in.
    private func autoMonitorSoleCourse() {
        guard monitoredCourseIDs.isEmpty, courses.count == 1, let only = courses.first else { return }

        // Only when the teacher has never expressed a preference. Without this,
        // switching the one class off would be undone by the next launch, since
        // the monitored set is empty again at that point.
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.monitoredCoursesKey) == nil,
              defaults.object(forKey: Self.legacySelectedCourseKey) == nil
        else { return }

        // A class the account attends rather than teaches has nothing Anchor can
        // read — monitoring it would only produce 403s.
        guard !only.enrolledAsStudent else { return }
        setMonitored(true, courseID: only.id)
    }

    /// Forgets courses that have left the account, so a stale id can't keep the
    /// sync loop running against a class that no longer exists.
    private func pruneMonitoredCourses() {
        guard !courses.isEmpty else { return }
        let live = Set(courses.map(\.id))
        let kept = monitoredCourseIDs.intersection(live)
        guard kept != monitoredCourseIDs else { return }
        monitoredCourseIDs = kept
        snapshotsByCourse = snapshotsByCourse.filter { live.contains($0.key) }
        lastSyncedByCourse = lastSyncedByCourse.filter { live.contains($0.key) }
        lastSyncErrorByCourse = lastSyncErrorByCourse.filter { live.contains($0.key) }
        persistMonitoredCourses()
        if monitoredCourseIDs.isEmpty { stopSync() }
    }

    /// The roster Anchor holds for a course, empty until it has been loaded.
    func roster(forCourse id: String) -> [ClassroomStudent] {
        rosters[id] ?? []
    }

    func studentCount(forCourse id: String) -> Int? {
        rosters[id]?.count
    }

    /// Starts or stops syncing coursework for one class. Other monitored classes
    /// are untouched.
    func setMonitored(_ isMonitored: Bool, courseID: String) {
        if isMonitored {
            // A class the account attends rather than teaches would only produce
            // 403s — Google shows a student nobody's work but their own.
            guard let course = courses.first(where: { $0.id == courseID }),
                  !course.enrolledAsStudent,
                  monitoredCourseIDs.insert(courseID).inserted
            else { return }

            persistMonitoredCourses()
            startSync()
            // The loop's next tick is up to ten minutes out; a class the
            // teacher just switched on should fill in now.
            Task { [weak self] in await self?.sync(courseID: courseID) }
        } else {
            guard monitoredCourseIDs.remove(courseID) != nil else { return }

            // Grades have no reason to outlive the decision to watch the class.
            snapshotsByCourse[courseID] = nil
            lastSyncedByCourse[courseID] = nil
            lastSyncErrorByCourse[courseID] = nil
            if activeCourseID == courseID { activeCourseID = nil }
            recountUnmatchableStudents()
            persistMonitoredCourses()
            if monitoredCourseIDs.isEmpty { stopSync() }
        }
    }

    func toggleMonitoring(courseID: String) {
        setMonitored(!isMonitored(courseID: courseID), courseID: courseID)
    }

    /// Stops syncing every class at once.
    func stopMonitoringAll() {
        for courseID in monitoredCourseIDs { setMonitored(false, courseID: courseID) }
    }

    private func persistMonitoredCourses() {
        UserDefaults.standard.set(monitoredCourseIDs.sorted(), forKey: Self.monitoredCoursesKey)
    }

    /// Restores the monitored set, carrying over the single course id written by
    /// the versions that could only watch one class.
    private func restoreMonitoredCourses() {
#if DEBUG
        // Screenshot mode holds a fabricated course. A real fetch landing on
        // top of it replaces the roster mid-capture and empties the Insights
        // tab — which is exactly what happened before this guard existed.
        if isDemoClassroom { return }
#endif
        let defaults = UserDefaults.standard
        var saved = defaults.stringArray(forKey: Self.monitoredCoursesKey) ?? []

        if saved.isEmpty, let legacy = defaults.string(forKey: Self.legacySelectedCourseKey) {
            saved = [legacy]
            defaults.removeObject(forKey: Self.legacySelectedCourseKey)
        }

        // An empty course list means the fetch failed, not that the teacher has
        // no classes — dropping the selection there would silently unmonitor
        // everything on a flaky network.
        let known = Set(courses.map(\.id))
        let restored = courses.isEmpty ? saved : saved.filter { known.contains($0) }

        monitoredCourseIDs = Set(restored)
        persistMonitoredCourses()
        if !monitoredCourseIDs.isEmpty { startSync() }
    }

    /// Called at launch so a previously connected teacher picks up where they
    /// left off without touching Settings.
    func restoreIfConnected() async {
#if DEBUG
        // Screenshot mode holds a fabricated course. A real fetch landing on
        // top of it replaces the roster mid-capture and empties the Insights
        // tab — which is exactly what happened before this guard existed.
        if isDemoClassroom { return }
#endif
        guard credentials.isConnected else { return }
        state = .connected(email: credentials.tokens?.accountEmail)
        await loadCourses()
        restoreMonitoredCourses()
    }

    // MARK: - Sync loop

    func startSync() {
        guard syncTask == nil, !monitoredCourseIDs.isEmpty else {
            AnchorDiag.log("""
                classroom: startSync ignored — \
                loopAlive=\(syncTask != nil) monitored=\(monitoredCourseIDs.count)
                """)
            return
        }
        AnchorDiag.log("classroom: sync loop started for \(monitoredCourseIDs.count) course(s)")
        isSyncActive = true
        syncTask = Task { [weak self] in await self?.syncLoop() }
    }

    func stopSync() {
        if syncTask != nil { AnchorDiag.log("classroom: sync loop stopped") }
        syncTask?.cancel()
        syncTask = nil
        isSyncActive = false
    }

    private func syncLoop() async {
        while !Task.isCancelled {
            await sync()

            // Sliced wait so a disconnect takes effect promptly.
            let startedAt = Date()
            while !Task.isCancelled {
                if Date().timeIntervalSince(startedAt) >= Self.syncInterval { break }
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return
                }
            }
        }
    }

    /// One full pass over every monitored course.
    ///
    /// Courses run concurrently, a few at a time. A pass used to be strictly
    /// sequential to stay under Google's per-minute limit, but a course is no
    /// longer dozens of calls — `submissions(courseID:assignmentIDs:)` collapsed
    /// it to about three — so a handful of classes at once is nowhere near the
    /// ceiling, and the teacher gets every card populated in the time the
    /// slowest single class used to take.
    func sync() async {
        // The monitored set is stored as *ids*; resolving them to courses needs
        // the list `loadCourses` fetches. `restoreMonitoredCourses` deliberately
        // restores the saved ids even when that fetch failed — dropping them on
        // a flaky network would silently unmonitor everything — which leaves a
        // launch where the courses call failed with ids that resolve to nothing.
        //
        // Without this the loop then wakes every ten minutes, finds no courses
        // to sync, and does nothing for the rest of the session while the UI
        // still says the class is syncing. Re-fetch instead: the ids are known
        // good, it is only the list that is missing.
        if !monitoredCourseIDs.isEmpty, monitoredCourses.isEmpty {
            // No `!isLoadingCourses` guard: a load already running is precisely
            // the common case at launch, and skipping it here was half the bug —
            // the pass gave up instead of waiting the second it needed.
            // `loadCourses` now waits for the one in flight.
            AnchorDiag.log("classroom: monitored ids don't resolve yet — waiting for the course list")
            logger.info("Monitored courses could not be resolved; reloading the course list.")
            await loadCourses()
        }

        let courses = monitoredCourses
        guard !courses.isEmpty else {
            AnchorDiag.log("""
                classroom: pass did nothing — \
                monitoredIDs=\(monitoredCourseIDs.count) resolvedCourses=\(self.courses.count)
                """)
            return
        }
        AnchorDiag.log("classroom: pass over \(courses.map(\.name).joined(separator: ", "))")

        await withTaskGroup(of: Void.self) { group in
            var next = 0
            let width = min(Self.syncWidth, courses.count)

            while next < width {
                let course = courses[next]
                group.addTask { @MainActor [weak self] in await self?.sync(course: course) }
                next += 1
            }

            while await group.next() != nil {
                if Task.isCancelled { return }
                guard next < courses.count else { continue }
                let course = courses[next]
                group.addTask { @MainActor [weak self] in await self?.sync(course: course) }
                next += 1
            }
        }
    }

    /// How many classes sync at once. Deliberately below the service's own
    /// request width: each class is itself making parallel calls, and the two
    /// multiply.
    private static let syncWidth = 3

    private func sync(courseID: String) async {
        guard let course = courses.first(where: { $0.id == courseID }) else { return }
        await sync(course: course)
    }

    /// One pass now, and re-arm the loop if it had stopped.
    ///
    /// What "Sync Now" is for. An error that needed the teacher stopped the loop
    /// (see `handle(_:)`), so by the time they reach for this button the
    /// ten-minute timer is usually already dead — a one-shot sync would fix the
    /// screen for ten minutes and then quietly stop updating again. Toggling
    /// monitoring off and on was the only thing that actually restarted it.
    func syncNow() async {
        lastError = nil
        if credentials.isConnected, !state.isConnected {
            // Clear a `.failed` left by the error that stopped the loop, so the
            // panel doesn't keep reading "Disconnected" through a good sync.
            state = .connected(email: credentials.tokens?.accountEmail)
        }
        startSync()
        await sync()
    }

    /// One full pass over one course.
    private func sync(course: ClassroomCourse) async {
        guard monitoredCourseIDs.contains(course.id) else {
            AnchorDiag.log("classroom: skipping \(course.name) — not monitored")
            return
        }
        guard syncingCourseIDs.insert(course.id).inserted else {
            // Already in flight. Only ever transient — but if it is *not*, the
            // course is wedged: every later pass returns here, so it can never
            // succeed and can never record a failure either, while the card sits
            // on "Syncing…". Say so rather than returning silently.
            AnchorDiag.log("classroom: \(course.name) already syncing — skipping this pass")
            return
        }
        defer { syncingCourseIDs.remove(course.id) }

        let service = self.service
        let courseID = course.id
        let canReadCoursework = self.canReadCoursework
        let startedAt = Date()
        AnchorDiag.log("classroom: syncing \(course.name) (coursework=\(canReadCoursework))")

        do {
            let fetched = try await Self.fetch(
                service: service,
                courseID: courseID,
                includeCoursework: canReadCoursework
            )

            rosters[courseID] = fetched.students
            recountUnmatchableStudents()

            // A grant without the coursework scopes still gives a roster, and a
            // roster is most of what Home shows — `fetch` skipped the coursework
            // calls rather than spending them on a guaranteed 403, and this is
            // still a successful sync rather than a failed one.
            snapshotsByCourse[courseID] = canReadCoursework
                ? AcademicRollup().snapshots(
                    students: fetched.students,
                    assignments: fetched.assignments,
                    submissions: fetched.submissions
                )
                : [:]

            lastSyncedByCourse[courseID] = Date()
            lastSyncErrorByCourse[courseID] = nil
            lastError = nil
            state = .connected(email: credentials.tokens?.accountEmail)

            let elapsed = String(format: "%.1f", Date().timeIntervalSince(startedAt))
            AnchorDiag.log("""
                classroom: synced \(course.name) in \(elapsed)s — \
                \(fetched.students.count) students, \(fetched.assignments.count) assignments, \
                \(fetched.submissions.count) with submissions
                """)
            logger.info("""
                Synced \(course.name, privacy: .public): \
                \(fetched.students.count, privacy: .public) students, \
                \(fetched.assignments.count, privacy: .public) assignments
                """)

        } catch let error as ClassroomError {
            fail(course: course, with: error)
        } catch {
            fail(course: course, with: .network(error.localizedDescription))
        }
    }

    /// Everything one course's sync needs from Google, fetched off the main
    /// actor and under a deadline.
    ///
    /// `nonisolated` on purpose. The calls touch no view-model state, and
    /// running them from a `@MainActor` method meant the whole fetch was
    /// interleaved with UI work on the main actor's executor for no benefit.
    ///
    /// The deadline is the important part. Every failure Anchor knows how to
    /// report arrives as a thrown `ClassroomError`; a request that simply never
    /// comes back throws nothing, so the course stays in `syncingCourseIDs`, the
    /// card stays on "Syncing coursework…", and no retry can ever get past the
    /// in-flight guard. Bounding it converts that silent wedge into an ordinary
    /// visible error that the next pass retries.
    private nonisolated static func fetch(
        service: ClassroomDataProviding,
        courseID: String,
        includeCoursework: Bool,
        timeout: TimeInterval = 90
    ) async throws -> CourseSyncResult {
        try await withThrowingTaskGroup(of: CourseSyncResult.self) { group in
            group.addTask {
                // Roster and coursework are independent, so they go out together
                // rather than one after the other — the pass costs the slower of
                // the two instead of their sum.
                async let rosterCall = service.students(courseID: courseID)
                async let assignmentCall: [ClassroomAssignment] = includeCoursework
                    ? service.assignments(courseID: courseID)
                    : []

                let students = try await rosterCall
                let assignments = try await assignmentCall

                guard includeCoursework else {
                    return CourseSyncResult(
                        students: students,
                        assignments: [],
                        submissions: [:]
                    )
                }

                // Every submission in the course in one paged call, instead of
                // one call per assignment.
                let submissions = try await service.submissions(
                    courseID: courseID,
                    assignmentIDs: assignments.map(\.id)
                )
                return CourseSyncResult(
                    students: students,
                    assignments: assignments,
                    submissions: submissions
                )
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ClassroomError.network(
                    "The sync took longer than \(Int(timeout))s and was abandoned."
                )
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ClassroomError.network("The sync produced no result.")
            }
            return first
        }
    }

    private struct CourseSyncResult: Sendable {
        var students: [ClassroomStudent]
        var assignments: [ClassroomAssignment]
        var submissions: [String: [ClassroomSubmission]]
    }

    /// Records that this course's sync attempt failed, then applies the
    /// connection-wide handling.
    ///
    /// Per course, not just globally, because the card has to be able to say so.
    /// Without this a course whose sync keeps failing has `lastSynced == nil`
    /// forever, which the UI could only read as "hasn't synced yet" — so a class
    /// that was failing every single attempt sat on "Syncing coursework…"
    /// indefinitely while the loop dutifully retried behind it.
    private func fail(course: ClassroomCourse, with error: ClassroomError) {
        lastSyncErrorByCourse[course.id] = error
        AnchorDiag.log("classroom: sync FAILED for \(course.name) — \(error.localizedDescription)")
        logger.error("""
            Sync failed for \(course.name, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
        handle(error)
    }

    /// Recomputed across every monitored roster rather than tracked per class:
    /// the count is shown once, as one number, in Settings.
    private func recountUnmatchableStudents() {
        // `matchKey == nil` used to be the whole rule and stopped being right on
        // 2026-08-17, when the email scope was dropped and that became true of
        // every entry. The count fed a note claiming the entire class was
        // unmatchable and their coursework counted for nothing — both false, and
        // shown on the first screen after connecting Classroom.
        let roster = monitoredRoster
        unmatchableStudentCount = RosterMatchability.unmatchable(in: roster).count
        ambiguouslyNamedStudentCount = RosterMatchability.ambiguouslyNamed(in: roster).count
    }

    private func handle(_ error: ClassroomError) {
        lastError = error

        // Auth problems are terminal — stop polling and tell the teacher.
        // Everything else keeps the last good snapshot set and tries again.
        if error.requiresUserAction {
            state = .failed(error)
            stopSync()
        }

        logger.error("Classroom sync failed: \(error.localizedDescription, privacy: .public)")
    }

    private let logger = Logger(subsystem: "com.anchor.google", category: "ClassroomViewModel")

    // MARK: - Lookup

    /// Every monitored course's rosters and rollups as one lookup table, in the
    /// key space `Student.identityKey` uses.
    ///
    /// Rebuilt per read rather than cached: a class roster is tens of entries,
    /// and a stale table would silently score a student against the wrong
    /// course after the monitored set changes.
    var matchTable: AcademicMatchTable { matchTable(forCourseID: nil) }

    /// The table for one course — or, passing nil, for every monitored course at
    /// once.
    ///
    /// A meeting that has been linked to a class is scored against *that* class
    /// alone. Pooling rosters is how one student's grades end up under another
    /// student's name, and the more classes are monitored the likelier that gets;
    /// the union is only for a meeting Anchor genuinely can't place.
    func matchTable(forCourseID courseID: String?) -> AcademicMatchTable {
        let courseIDs = courseID.map { [$0] } ?? monitoredCourses.map(\.id)
        guard !courseIDs.isEmpty else { return AcademicMatchTable() }

        var roster: [ClassroomStudent] = []
        var seen: Set<String> = []
        var merged: [String: AcademicSnapshot] = [:]
        var manualLinks: [String: String] = [:]

        for id in courseIDs {
            for student in rosters[id] ?? [] where seen.insert(student.id).inserted {
                roster.append(student)
            }
            // A student in two of these classes has a rollup in each. Combined,
            // so "behind on work" counts every class they're behind in rather
            // than whichever course synced last.
            for (key, snapshot) in snapshotsByCourse[id] ?? [:] {
                merged[key] = merged[key].map { $0.combined(with: snapshot) } ?? snapshot
            }
            manualLinks.merge(links.links(forCourse: id)) { first, _ in first }
        }

        return AcademicMatchTable(roster: roster, snapshots: merged, manualLinks: manualLinks)
    }

    // MARK: - Manual links

    /// Records that this participant *is* this roster student.
    ///
    /// `isDurable` decides whether the link outlives the meeting, and only the
    /// caller can judge it: a name key shared by two people in the room would
    /// resolve to both next week, so those links stay meeting-local. See
    /// ManualRosterLinks.
    func linkParticipant(
        identityKey: String,
        name: String?,
        to student: ClassroomStudent,
        isDurable: Bool
    ) {
        // Links are filed per course, so the one to file under is the course
        // this roster entry came from — not whichever class happens to be first.
        guard let courseID = courseID(holdingStudent: student.id) else { return }
        let keys = AcademicMatchTable.linkKeys(forIdentity: identityKey, name: name)

        // Clear any earlier link first, so re-pointing a participant at a
        // different student can't leave the old one shadowing it. Cleared in
        // every monitored class: a participant linked to the wrong class's
        // student would otherwise keep resolving through that one.
        unlinkParticipant(identityKey: identityKey, name: name)

        // Prefer the durable key when we're allowed one; fall back to the
        // meeting-local identity otherwise.
        let key = isDurable ? (keys.last ?? identityKey) : identityKey
        links.link(key: key, studentID: student.id, course: courseID, isDurable: isDurable)
    }

    func unlinkParticipant(identityKey: String, name: String?) {
        let keys = AcademicMatchTable.linkKeys(forIdentity: identityKey, name: name)
        for course in monitoredCourses {
            links.unlink(keys: keys, course: course.id)
        }
    }

    /// Which monitored course holds this roster entry, preferring the class the
    /// live meeting belongs to when the student is in more than one.
    private func courseID(holdingStudent studentID: String) -> String? {
        let holds: (String) -> Bool = { [rosters] courseID in
            rosters[courseID]?.contains { $0.id == studentID } == true
        }
        if let activeCourse, holds(activeCourse.id) { return activeCourse.id }
        return monitoredCourses.map(\.id).first(where: holds)
    }

    /// The academic snapshot for a student — by verified email where Zoom gave
    /// one, by unambiguous display name where it did not.
    ///
    /// The name route exists because Zoom frequently reports no email at all:
    /// the macOS Meeting SDK has no API for it, and the Dashboard REST API
    /// blanks it for participants outside your Zoom account. Without it the
    /// academic half of the app is dark for most classes. Anchor still refuses
    /// to *guess*: a name shared by two students on the roster matches neither.
    func snapshot(forIdentity identityKey: String, name: String? = nil) -> AcademicSnapshot? {
        activeMatchTable.snapshot(forIdentity: identityKey, name: name)
    }

    /// The table the live meeting is being scored against — its own class where
    /// the teacher linked one, every monitored class otherwise. The panels read
    /// through this so they can't disagree with the score on screen.
    private var activeMatchTable: AcademicMatchTable {
        matchTable(forCourseID: activeCourseID)
    }

    /// The monitored course's roster entry for a Zoom identity, and how it was
    /// matched — the UI shows an email match and a name match differently.
    ///
    /// Separate from `snapshot(forIdentity:)` on purpose. A snapshot only exists
    /// once *coursework* has synced, so using its absence to mean "not on the
    /// roster" reported every student in the class as unmatched whenever the
    /// coursework scope was withheld — or whenever the class simply had no
    /// graded or overdue work yet. Roster membership needs neither.
    func rosterMatch(forIdentity identityKey: String, name: String? = nil) -> AcademicMatchTable.Match? {
        activeMatchTable.match(forIdentity: identityKey, name: name)
    }

    func rosterStudent(forIdentity identityKey: String, name: String? = nil) -> ClassroomStudent? {
        rosterMatch(forIdentity: identityKey, name: name)?.student
    }

    /// The roster entries whose names collide with this participant's, which is
    /// why `rosterMatch` refused them. Empty unless that is the actual reason.
    ///
    /// Only meaningful after `rosterMatch` has returned nil — see
    /// `AcademicMatchTable.rosterTwins`.
    func rosterTwins(forIdentity identityKey: String, name: String? = nil) -> [ClassroomStudent] {
        activeMatchTable.rosterTwins(forIdentity: identityKey, name: name)
    }

    /// How many students Anchor holds across the monitored classes. Zero means
    /// no roster has loaded — which is not the same as an empty class.
    var monitoredRosterCount: Int { monitoredRoster.count }

    var hasAcademicData: Bool { !snapshots.isEmpty }

    /// One line for Settings and the dashboard footer.
    var summary: String {
        guard isConnected else { return "Not connected" }

        let monitored = monitoredCourses
        guard !monitored.isEmpty else { return "Connected · no classes monitored" }

        let names = monitored.count <= 2
            ? monitored.map(\.name).joined(separator: ", ")
            : "\(monitored.count) classes"

        guard let lastSyncedAt else { return "\(names) · waiting for first sync" }
        return "\(names) · \(monitoredRosterCount) students · "
            + "synced \(Theme.relativeString(from: lastSyncedAt, to: Date()).lowercased())"
    }
}
