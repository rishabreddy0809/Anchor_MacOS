//
//  HomeView.swift
//  Anchor
//
//  The landing tab: your classes, and what happened in them.
//
//  This is the half of Anchor that outlives a meeting. The Live tab answers
//  "who needs me right now"; this answers "who has been struggling", which is
//  the question a teacher can actually act on between lessons.
//
//  Two things make a class appear here, and they are kept visually distinct:
//
//    * A Google Classroom course — the teacher's own classes, shown as a card
//      grid that mirrors classroom.google.com so they are recognisable before a
//      word is read. Present as soon as Classroom is connected, before Anchor
//      has ever monitored a meeting.
//    * A recorded class — a Zoom meeting Anchor has actually sat in and scored.
//      This is the history half, and it is the only place scores appear.
//
//  There is still no sample data: a course card claims nothing about engagement
//  until a session backs it up — see ZOOM_INTEGRATION.md §6.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var archive = SessionArchive.shared
    @ObservedObject private var monitor = MeetingMonitorCoordinator.shared
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var googleCredentials = GoogleCredentialsStore.shared
    @ObservedObject private var profile = TeacherProfileStore.shared

    /// Jumps to the Live tab.
    let onOpenLive: () -> Void

    @State private var path: [HomeRoute] = []
    @State private var isConnecting = false

    enum HomeRoute: Hashable {
        case classroom(UUID)
        case session(UUID)
        case course(String)
        case courseStudent(courseID: String, studentID: String)
    }

    private var sensitivity: Double { store.settings.sensitivity }

    /// Anything at all to show: a connected Classroom account counts, even
    /// before its first course loads, because the teacher just connected it and
    /// an empty state would read as the connection having failed.
    private var hasAnything: Bool {
        classroom.isConnected || archive.hasHistory || store.hasData
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasAnything {
                    populated
                } else {
                    HomeEmptyState(onOpenLive: onOpenLive, onConnectClassroom: connect)
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .classroom(let id):
                    ClassroomDetailView(classroomID: id) { path.append(.session($0)) }
                case .session(let id):
                    SessionRecapView(sessionID: id)
                case .course(let id):
                    CourseDetailView(courseID: id)
                case .courseStudent(let courseID, let studentID):
                    CourseStudentHistoryView(courseID: courseID, studentID: studentID)
                }
            }
        }
        // Courses are loaded on connect and at launch; this covers the case
        // where the window is opened long after either, with a stale list.
        .task {
            guard classroom.isConnected, classroom.courses.isEmpty else { return }
            await classroom.loadCourses()
        }
    }

    // MARK: - Populated

    private var populated: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                title

                if store.hasData {
                    LiveNowBanner(onOpenLive: onOpenLive)
                }

                if classroom.isConnected {
                    coursesSection
                } else {
                    ClassroomConnectBanner(isConnecting: isConnecting, onConnect: connect)
                }

                if !unlinkedSummaries.isEmpty {
                    recordedSection
                }

                if !recentSessions.isEmpty {
                    recentSection
                }

                if !archive.hasHistory, store.hasData {
                    firstSessionNotice
                }
            }
            .padding(22)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AnchorGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, height: 20)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(.system(size: 22, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if classroom.isConnected {
                HStack(spacing: 7) {
                    // Only the course-list load, and only while there is nothing
                    // on screen yet. A coursework sync never spins: it runs on
                    // its own clock every ten minutes, and a spinner appearing
                    // over a populated grid reads as the app doing something the
                    // teacher has to wait for, when they don't.
                    if classroom.isLoadingCourses, classroom.courses.isEmpty {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }

                    Button {
                        Task { await classroom.loadCourses() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .disabled(classroom.isLoadingCourses)
                }
            }
        }
    }

    private var titleText: String {
        guard let first = profile.firstName else { return "Your classes" }
        return "\(first)'s classes"
    }

    private var subtitle: String {
        var parts: [String] = []

        if classroom.isConnected {
            let courses = classroom.courses.count
            parts.append(courses == 0
                ? "Google Classroom connected"
                : "\(courses) Classroom \(courses == 1 ? "class" : "classes")")
#if DEBUG
            if DemoData.isEnabled {
                parts.append(DemoData.teacherEmail)
            } else if let email = googleCredentials.tokens?.accountEmail {
                parts.append(email)
            }
#else
            if let email = googleCredentials.tokens?.accountEmail {
                parts.append(email)
            }
#endif
        }

        let sessions = archive.sessions.count
        if sessions > 0 {
            parts.append("\(sessions) recorded \(sessions == 1 ? "session" : "sessions")")
        } else if parts.isEmpty {
            return "Anchor is monitoring. This fills in once the class ends."
        }

        return parts.joined(separator: " · ")
    }

    private func connect() {
        Task {
            isConnecting = true
            defer { isConnecting = false }
            await classroom.connect()
        }
    }

    /// Google won't re-prompt for a scope it thinks it has already settled, so
    /// a partial grant is repaired by dropping the token first and signing in
    /// afresh — not by asking again on top of the existing one.
    private func reconnect() {
        classroom.disconnect()
        connect()
    }

    // MARK: - Google Classroom courses

    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Google Classroom", trailingText: monitoringSummary)

            if let error = classroom.lastError {
                ClassroomErrorRow(error: error, onRetry: connect)
            }

            // A partial grant is a working connection with a hole in it, and
            // reads as amber rather than red for exactly that reason.
            if let warning = classroom.scopeWarning {
                ScopeWarningRow(text: warning, onReconnect: reconnect)
            }

            if classroom.courses.isEmpty {
                emptyCoursesRow
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(classroom.courses) { course in
                        CourseCard(
                            course: course,
                            studentCount: classroom.studentCount(forCourse: course.id),
                            isMonitored: classroom.isMonitored(courseID: course.id),
                            detail: detail(for: course),
                            linkedClasses: linkedClasses(for: course),
                            onOpen: { path.append(.course(course.id)) },
                            // Monitoring a class you attend rather than teach
                            // would only produce 403s from Google.
                            onMonitor: course.enrolledAsStudent
                                ? nil
                                : { classroom.setMonitored(true, courseID: course.id) },
                            onOpenLinked: { path.append(.classroom($0)) }
                        )
                        .contextMenu {
                            if course.enrolledAsStudent {
                                EmptyView()
                            } else if classroom.isMonitored(courseID: course.id) {
                                Button("Stop monitoring") {
                                    classroom.setMonitored(false, courseID: course.id)
                                }
                            } else {
                                Button("Monitor this class") {
                                    classroom.setMonitored(true, courseID: course.id)
                                }
                            }
                            Button("Open") { path.append(.course(course.id)) }

                            let linked = archive.classrooms(forCourseID: course.id)
                            if !linked.isEmpty {
                                Divider()
                                ForEach(linked) { recorded in
                                    Button("Unlink \(recorded.displayName)") {
                                        link(classroomID: recorded.id, to: nil)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// What the Google Classroom header says on the right.
    private var monitoringSummary: String {
        let monitored = classroom.monitoredCourses
        switch monitored.count {
        case 0: return "Monitor a class to sync coursework"
        case 1: return "Monitoring \(monitored[0].name)"
        default: return "Monitoring \(monitored.count) classes"
        }
    }

    /// The middle line of a card. Only a monitored course has coursework, so
    /// every other card says what it is rather than inventing a statistic.
    ///
    /// Every figure here is that course's own — with several classes monitored,
    /// reading the pooled rollups would print one class's missing work on
    /// another class's card.
    private func detail(for course: ClassroomCourse) -> CourseCardDetail {
        if course.enrolledAsStudent { return .enrolledAsStudent }
        guard classroom.isMonitored(courseID: course.id) else {
            // Not synced, but a linked class still has real history behind it.
            let linked = linkedClasses(for: course)
            guard !linked.isEmpty else { return .notSynced }
            return .linkedHistory(
                classes: linked.count,
                sessions: linked.reduce(0) { $0 + $1.sessionCount }
            )
        }
        if !classroom.canReadCoursework { return .rosterOnly }

        let snapshots = classroom.snapshots(forCourse: course.id).values
        if snapshots.isEmpty {
            // Nothing known yet. The sync itself is never announced — it is
            // background work on a ten-minute clock that the teacher didn't ask
            // for and isn't waiting on — so a pass in flight looks exactly like
            // one that hasn't started. What *is* announced is anything that
            // needs them:
            if classroom.lastSynced(courseID: course.id) == nil {
                // Tried and failed. The loop will retry, but the teacher can't
                // wait out a cause that needs fixing.
                if let error = classroom.lastSyncError(courseID: course.id) {
                    return .syncFailed(reason: error.localizedDescription)
                }
                // Nothing is going to try — the loop is dead.
                guard classroom.isSyncActive else { return .syncStalled }
                // Simply hasn't been read yet. Quiet.
                return .awaitingCoursework
            }

            return .noCoursework
        }

        return .academic(
            missingStudents: snapshots.filter { $0.missingCount > 0 }.count,
            missingItems: snapshots.reduce(0) { $0 + $1.missingCount },
            sessions: sessionCount(matching: course)
        )
    }

    /// Zoom meetings and Classroom courses share no identifier, so a recorded
    /// class belongs to a course because the teacher said so — or, failing that,
    /// because the names happen to match.
    private func sessionCount(matching course: ClassroomCourse) -> Int {
        recordedClassrooms(for: course)
            .reduce(0) { $0 + archive.sessions(forClassroom: $1.id).count }
    }

    /// A link the teacher made wins over a name match, and a class linked
    /// elsewhere is never claimed by a coincidence of naming.
    private func recordedClassrooms(for course: ClassroomCourse) -> [Classroom] {
        let name = course.name.lowercased().trimmed
        return archive.classrooms.filter { recorded in
            if let linkedID = recorded.googleCourseID { return linkedID == course.id }
            return recorded.displayName.lowercased().trimmed == name
        }
    }

    /// Only the explicit links — these are the ones the card lists by name, and
    /// the ones that have moved out of "Recorded by Anchor".
    private func linkedClasses(for course: ClassroomCourse) -> [LinkedRecordedClass] {
        archive.classrooms(forCourseID: course.id).map { recorded in
            LinkedRecordedClass(
                id: recorded.id,
                name: recorded.displayName,
                sessionCount: archive.sessions(forClassroom: recorded.id).count
            )
        }
        .sorted { $0.sessionCount > $1.sessionCount }
    }

    private var emptyCoursesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(classroom.isLoadingCourses
                 ? "Loading your classes from Google Classroom…"
                 : "No active classes on this Google account.")
                .font(.system(size: 12, weight: .medium))

            if !classroom.isLoadingCourses {
                Text("Anchor lists classes where you are a teacher and the class is "
                     + "active. Archived classes, and classes you're enrolled in as a "
                     + "student, aren't shown.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Recorded classes

    private var recordedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(
                text: "Recorded by Anchor",
                trailingText: linkableCourses.isEmpty
                    ? "Open one for its history"
                    : "Connect one to a Google Classroom class"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)],
                spacing: 12
            ) {
                ForEach(unlinkedSummaries, id: \.classroom.id) { summary in
                    ClassroomCard(
                        summary: summary,
                        sensitivity: sensitivity,
                        courses: linkableCourses,
                        onLink: { link(classroomID: summary.classroom.id, to: $0) },
                        action: { path.append(.classroom(summary.classroom.id)) }
                    )
                    .contextMenu {
                        Button("Delete \(summary.classroom.displayName)…", role: .destructive) {
                            archive.delete(classroomID: summary.classroom.id)
                        }
                    }
                }
            }
        }
    }

    /// Most recently taught first — the class you just finished should be the
    /// one you land next to.
    private var classroomSummaries: [SessionArchive.ClassroomSummary] {
        archive.classrooms
            .map { archive.summary(for: $0, sensitivity: sensitivity) }
            .sorted { lhs, rhs in
                let left = lhs.lastSession?.startedAt ?? lhs.classroom.createdAt
                let right = rhs.lastSession?.startedAt ?? rhs.classroom.createdAt
                return left > right
            }
    }

    // MARK: - Linking

    /// What a recorded class can be tied to: classes the teacher actually
    /// teaches, since Google gives a student account nothing to sync.
    private var linkableCourses: [ClassroomCourse] {
        guard classroom.isConnected else { return [] }
        return classroom.courses.filter { !$0.enrolledAsStudent }
    }

    /// A linked class has moved into the Google Classroom section, so it isn't
    /// listed here twice.
    private var unlinkedSummaries: [SessionArchive.ClassroomSummary] {
        classroomSummaries.filter { !isShownUnderCourses($0.classroom) }
    }

    /// True when the Google Classroom section is showing this class.
    ///
    /// A link whose course has gone from the account — or which can't be shown
    /// because Classroom is disconnected — falls back to the recorded section
    /// rather than leaving the class unreachable. While the course list is still
    /// loading, the card stays put instead of flickering through this section on
    /// every launch.
    private func isShownUnderCourses(_ recorded: Classroom) -> Bool {
        guard classroom.isConnected, let courseID = recorded.googleCourseID else { return false }
        if classroom.courses.contains(where: { $0.id == courseID }) { return true }
        return classroom.isLoadingCourses
    }

    private func link(classroomID: UUID, to courseID: String?) {
        withAnimation(.easeOut(duration: 0.18)) {
            archive.link(classroomID: classroomID, toCourseID: courseID)
        }
    }

    // MARK: - Recent sessions

    private var recentSection: some View {
        HomeSection(title: "Recent sessions", trailingText: "Last \(recentSessions.count)") {
            VStack(spacing: 1) {
                ForEach(recentSessions) { session in
                    SessionRow(
                        session: session,
                        classroomName: name(forClassroom: session.classroomID),
                        sensitivity: sensitivity
                    ) {
                        path.append(.session(session.id))
                    }
                }
            }
        }
    }

    private var recentSessions: [ClassSession] {
        Array(archive.sessions.prefix(6))
    }

    private func name(forClassroom id: UUID) -> String? {
        archive.classroom(id: id)?.displayName
    }

    // MARK: - First session in progress

    /// Shown during the very first monitored class, when there is a live roster
    /// but nothing archived yet.
    private var firstSessionNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Recording this session")
                    .font(.system(size: 12.5, weight: .medium))
                Text("It'll appear here as a class you can review once the meeting ends.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Classroom connect banner

/// The sign-in prompt, on Home rather than buried in Settings.
///
/// It runs the OAuth flow directly. Sending the teacher to Settings for the one
/// action Home is asking them to take is how "connect to classroom" ends up
/// looking like it did nothing.
private struct ClassroomConnectBanner: View {
    @ObservedObject private var credentials = GoogleCredentialsStore.shared
    @ObservedObject private var classroom = ClassroomViewModel.shared

    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Google Classroom")
                    .font(.system(size: 14, weight: .semibold))

                Text(credentials.hasClientID
                     ? "Sign in to see your classes here, and to factor missing "
                       + "assignments and grade trends into each student's score."
                     : "Add a Google OAuth client ID in Settings first — Anchor ships "
                       + "no Google credentials of its own, so each deployment uses "
                       + "its own registered app.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = classroom.lastError {
                    Text([error.errorDescription, error.recoverySuggestion]
                        .compactMap { $0 }
                        .joined(separator: " "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.riskHigh)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if credentials.hasClientID {
                Button(isConnecting ? "Opening browser…" : "Connect") { onConnect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isConnecting)
            } else {
                SettingsLink { Text("Open Settings") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.20), lineWidth: 1)
        )
    }
}

/// A working connection missing one or more permissions. Amber, not red, and
/// never in place of the class list — the classes below it are real.
private struct ScopeWarningRow: View {
    let text: String
    let onReconnect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.riskElevated)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Reconnect") { onReconnect() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.riskElevated.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.riskElevated.opacity(0.25), lineWidth: 1)
        )
    }
}

/// A Classroom failure shown where the classes should have been, so a sync that
/// died is never mistaken for a teacher with no classes.
private struct ClassroomErrorRow: View {
    let error: ClassroomError
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .padding(.top, 1)

            Text([error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " "))
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if error.requiresUserAction {
                Button("Reconnect") { onRetry() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .foregroundStyle(error.requiresUserAction ? Theme.riskHigh : Theme.riskElevated)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

// MARK: - Live banner

/// Present only while a class is actually running, so Home never implies a live
/// session that isn't there.
private struct LiveNowBanner: View {
    @EnvironmentObject private var store: EngagementStore
    let onOpenLive: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: onOpenLive) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.riskLow.opacity(0.25))
                        .frame(width: 22, height: 22)
                        .scaleEffect(isPulsing ? 1.35 : 0.9)
                        .opacity(isPulsing ? 0 : 1)
                    Circle()
                        .fill(Theme.riskLow)
                        .frame(width: 9, height: 9)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.meeting?.displayName ?? "Class in progress")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if store.highRiskCount > 0 {
                    HStack(spacing: 5) {
                        RiskDot(level: .high, size: 6)
                        Text("\(store.highRiskCount) need attention")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.riskHigh)
                    }
                }

                Text("Open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.riskLow.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.riskLow.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }

    private var detail: String {
        "\(Theme.elapsedString(store.elapsed)) elapsed · \(store.students.count) students"
    }
}

// MARK: - Empty state

/// What Home looks like before Anchor has ever monitored a class and before
/// Google Classroom is connected.
///
/// Deliberately not a placeholder grid of fake classes: the first thing a
/// teacher sees should be true.
private struct HomeEmptyState: View {
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var credentials = ZoomCredentialsStore.shared
    @ObservedObject private var google = GoogleCredentialsStore.shared

    let onOpenLive: () -> Void
    let onConnectClassroom: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No classes yet")
                    .font(.system(size: 18, weight: .semibold))

                Text("Connect Google Classroom to see your classes here. Their "
                     + "engagement history fills in after Anchor's first monitored "
                     + "session.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            HStack(spacing: 8) {
                if google.hasClientID {
                    Button("Connect Google Classroom") { onConnectClassroom() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    SettingsLink { Text("Connect Google Classroom") }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                if ZoomViewModel.hasAnyZoomCredential {
                    Button("Go to Live Class") { onOpenLive() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else {
                    SettingsLink { Text("Connect Zoom") }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .padding(.top, 2)

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var hint: String {
        ZoomViewModel.hasAnyZoomCredential
            ? "Anchor records a session automatically once its bot is in a meeting. Nothing is stored until then."
            : "Connect your Zoom account in Settings before Anchor can read a class."
    }
}
