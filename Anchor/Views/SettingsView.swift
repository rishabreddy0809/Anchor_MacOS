//
//  SettingsView.swift
//  Anchor
//
//  Settings, organized the way macOS System Settings is: a sidebar of
//  categories on the left, one category's content on the right. Each
//  category groups panels that used to sit in one long scrolling list —
//  the panels themselves (ZoomConnectionPanel, ClassroomConnectionPanel,
//  LessonTopicPanel) are unchanged, only where they live changed.
//
//  The sidebar is a real NavigationSplitView + List(.sidebar), the same
//  construction LiveSessionView's roster uses — that's what gets the native
//  translucent "liquid glass" sidebar material and the collapse toggle next
//  to the traffic lights for free, rather than a hand-drawn imitation of it.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel
    @EnvironmentObject private var coach: LiveCoachViewModel
    @ObservedObject private var archive = SessionArchive.shared
    @ObservedObject private var profile = TeacherProfileStore.shared
    @ObservedObject private var oauth = ZoomOAuthStore.shared
    @ObservedObject private var googleCredentials = GoogleCredentialsStore.shared
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var accounts = AccountStore.shared

    /// Optional because a macOS sidebar `List` selection binding is —
    /// mirrors LiveSessionView's own `SidebarSelection?`. Nil is treated as
    /// General everywhere it's read.
#if DEBUG
    /// Screenshot mode opens on Integrations — the pane that shows the
    /// product's actual connections, rather than General, which is mostly the
    /// teacher's own profile.
    @State private var category: Category? = DemoData.isEnabled ? .integrations : .general
#else
    @State private var category: Category? = .general
#endif
    @State private var isConfirmingClear = false
    /// Presents the onboarding account screen on its own, so signing in does
    /// not require replaying the whole seven-step walkthrough.
    @State private var isPresentingSignIn = false
    @State private var isConnectingZoom = false
    @State private var isConnectingClassroom = false
    @State private var zoomConnectError: String?
    @State private var classroomConnectError: String?

    enum Category: String, CaseIterable, Identifiable {
        case account = "Account"
        case general = "General"
        case integrations = "Integrations"
        case notifications = "Notifications"
        case dataPrivacy = "Data & Privacy"
        case about = "About"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .account: "person.crop.circle"
            case .general: "gearshape"
            case .integrations: "puzzlepiece.extension"
            case .notifications: "bell"
            case .dataPrivacy: "lock.shield"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            content
        }
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            SidebarBrandingHeader()

            List(selection: $category) {
                ForEach(Category.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbolName)
                        .font(.system(size: 12.5, weight: .medium))
                        .tag(item)
                }
            }
            .listStyle(.sidebar)

            Divider()
            profileCard
        }
    }

    /// Doubles as a shortcut into General, where the name field lives.
    private var profileCard: some View {
        Button { category = .general } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.16))
                    Text(profileInitials)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.firstName != nil ? profile.name : "Add your name")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(profile.firstName != nil ? .primary : .secondary)
                        .lineLimit(1)
                    Text(profileSubtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var profileInitials: String {
        guard let first = profile.firstName, let letter = first.first else { return "?" }
        return String(letter).uppercased()
    }

    private var profileSubtitle: String {
#if DEBUG
        // These captures are published on the website. Whatever account happens
        // to be signed in on the machine taking them must not travel with them.
        if DemoData.isEnabled { return DemoData.teacherEmail }
#endif
        return googleCredentials.tokens?.accountEmail ?? oauth.accountLabel ?? "No account connected"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                switch category ?? .general {
                case .account: accountContent
                case .general: generalContent
                case .integrations: integrationsContent
                case .notifications: notificationsContent
                case .dataPrivacy: dataPrivacyContent
                case .about: aboutContent
                }
            }
            .padding(22)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pageHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Account

    /// Sign-in, reachable without replaying onboarding.
    ///
    /// The account screen used to exist *only* inside the onboarding sheet,
    /// which meant a teacher who finished or skipped onboarding had no way to
    /// sign in at all — `hasCompletedOnboarding` is durable, so the sheet never
    /// comes back on its own. Every other connection Anchor makes is reachable
    /// from Settings afterwards; this one now is too.
    private var accountContent: some View {
        Group {
            pageHeader("Account", "Your Anchor account, and what it does not hold.")

            settingsCard(
                title: "Anchor account",
                subtitle: "Keeps your settings and connected tools together."
            ) {
                if !accounts.isConfigured {
                    // Same sentence the onboarding step shows. Named as a setup
                    // problem rather than a teacher problem, because it is one.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accounts aren't set up in this build of Anchor.")
                            .font(.system(size: 12, weight: .medium))
                        Text("Everything else works normally. Whoever installed Anchor "
                             + "can finish account setup in one step.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let account = accounts.account {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.riskLow)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("Signed in via \(account.provider.label)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }

                        Button("Sign out") { accounts.signOut() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("You're not signed in.")
                            .font(.system(size: 12, weight: .medium))
                        Button("Sign in or create an account") {
                            isPresentingSignIn = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            settingsCard(title: "What the account holds") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your name and email address — nothing else.")
                        .font(.system(size: 11.5))
                    Text("No rosters, scores, session history or transcripts. Those stay "
                         + "on this Mac and are never uploaded. Signing in changes nothing "
                         + "about where your class data lives.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - General

    private var generalContent: some View {
        Group {
            pageHeader("General", "Your profile, and how Anchor scores a class.")

            settingsCard(title: "Your name", subtitle: "Used to personalize your dashboard and alerts.") {
                TextField("e.g. Ms. Rivera", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 12))
                    .frame(maxWidth: 260)
            }

            meetingSection
            LessonTopicPanel()
            sensitivitySection
            refreshSection
        }
    }

    private var meetingSection: some View {
        settingsCard(title: "Monitored meeting") {
            VStack(alignment: .leading, spacing: 8) {
                if let meeting = store.meeting {
                    HStack(spacing: 5) {
                        Image(systemName: meeting.platform.symbolName)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                        Text(meeting.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 9))
                        Text("Host: \(meeting.hostName)")
                        Divider().frame(height: 9)
                        Text("Started \(Theme.clockString(meeting.startedAt))")
                        Divider().frame(height: 9)
                        // Students, not everyone in the call — the teacher and
                        // Anchor's bot are filtered out before this is counted.
                        Text("\(meeting.participantCount) students")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                } else {
                    Text("No meeting connected. Anchor monitors whichever live meeting Zoom reports, or the one its bot joins.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sensitivitySection: some View {
        settingsCard(
            title: "Detection sensitivity",
            subtitle: "Higher sensitivity flags students sooner, with more false positives."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.settings.sensitivityLabel)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("High risk at \(thresholdPercent)%+")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $store.settings.sensitivity, in: 0...1)
                    .controlSize(.small)

                HStack {
                    Text("Conservative")
                    Spacer()
                    Text("Very alert")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

                Divider().overlay(Theme.hairline)

                HStack(spacing: 10) {
                    countLabel(store.highRiskCount, level: .high)
                    countLabel(store.elevatedCount, level: .elevated)
                    countLabel(store.engagedCount, level: .low)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func countLabel(_ count: Int, level: RiskLevel) -> some View {
        HStack(spacing: 4) {
            RiskDot(level: level, size: 6)
            Text("\(count) \(level.shortLabel.lowercased())")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var thresholdPercent: Int {
        Int((RiskLevel.highThreshold(sensitivity: store.settings.sensitivity) * 100).rounded())
    }

    private var refreshSection: some View {
        settingsCard(title: "Auto-refresh") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $store.settings.refreshInterval) {
                    ForEach(AppSettings.RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .controlSize(.small)

                if let notice = zoom.pollFloorNotice {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .padding(.top, 1)
                        Text(notice)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text("Last updated \(store.lastUpdatedDescription.lowercased())")
                    Spacer(minLength: 0)
                    Button("Refresh now") { Task { await zoom.refreshNow() } }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 10))
                        .disabled(!store.dataSource.isLive)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Integrations

    private var integrationsContent: some View {
        Group {
            pageHeader("Integrations", "Connect your favorite tools to enhance your workflow.")

            IntegrationCard(
                symbolName: "video.fill",
                tint: Color(red: 0.15, green: 0.47, blue: 0.94),
                title: "Zoom",
                description: "Live roster, mute and camera state, and the in-meeting bot "
                    + "Anchor uses to read engagement signals.",
                learnMoreDetail: "Anchor opens Zoom in your browser to sign in — nothing is "
                    + "typed here, and Anchor never sees your password. The in-meeting bot "
                    + "is what reads raised hands and speaking time; everything else works "
                    + "from Zoom's API alone.",
                isConnected: oauth.isConnected,
                isBusy: isConnectingZoom,
                canConnect: oauth.hasClientCredentials,
                unavailableReason: oauth.hasClientCredentials
                    ? nil
                    // Deliberately says sign-in would fail *after* Zoom, because
                    // that is the failure this button now prevents rather than a
                    // generic "misconfigured" — see `hasClientCredentials`.
                    : "Anchor's Zoom setup isn't finished on this Mac. Signing in would "
                        + "get as far as Zoom's permission screen and then fail, so the "
                        + "button is off until whoever installed Anchor finishes setup.",
                connectedDetail: oauth.accountLabel,
                onConnect: connectZoom,
                onDisconnect: disconnectZoom
            ) {
                ZoomConnectionPanel()
            }

            if let zoomConnectError {
                errorLine(zoomConnectError)
            }

            IntegrationCard(
                symbolName: "graduationcap.fill",
                tint: Color(red: 0.20, green: 0.60, blue: 0.36),
                title: "Google Classroom",
                description: "Optional. Adds missing assignments and grade trends to each "
                    + "student's score.",
                learnMoreDetail: "Anchor only reads Classroom — it never posts, grades or "
                    + "changes anything. Once connected, choose which classes to sync in this panel.",
                isConnected: classroom.isConnected,
                isBusy: isConnectingClassroom,
                // `canCompleteSignIn`, not `hasClientID` — see the corrected note
                // on the onboarding twin. A client id alone is enough to open a
                // browser and not enough to redeem the code that comes back.
                canConnect: googleCredentials.canCompleteSignIn,
                unavailableReason: googleCredentials.canCompleteSignIn
                    ? nil
                    : "This copy of Anchor is missing part of its Google setup, so signing "
                        + "in would fail after you'd already approved it. It isn't something "
                        + "you can fix from here.",
                connectedDetail: googleCredentials.tokens?.accountEmail,
                onConnect: connectClassroom,
                onDisconnect: disconnectClassroom
            ) {
                ClassroomConnectionPanel()
            }

            if let classroomConnectError {
                errorLine(classroomConnectError)
            }
        }
    }

    private func errorLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.riskHigh)
    }

    private func connectZoom() {
        zoomConnectError = nil
        Task {
            isConnectingZoom = true
            defer { isConnectingZoom = false }
            switch await zoom.connectAccount() {
            case .success:
                break
            case .failure(let error):
                guard error != .authorizationCancelled else { return }
                zoomConnectError = [error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
        }
    }

    private func disconnectZoom() {
        Task { await zoom.disconnectAccount() }
    }

    private func connectClassroom() {
        classroomConnectError = nil
        Task {
            isConnectingClassroom = true
            defer { isConnectingClassroom = false }
            await classroom.connect()
            if let error = classroom.lastError {
                classroomConnectError = [error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
        }
    }

    private func disconnectClassroom() {
        classroom.disconnect()
    }

    // MARK: - Notifications

    private var notificationsContent: some View {
        Group {
            pageHeader("Notifications", "What Anchor tells you, and when.")

            settingsCard(title: "Alerts & signals") {
                VStack(alignment: .leading, spacing: 7) {
                    settingsToggle("Show menu bar badge for high risk", isOn: $store.settings.showsBadge)
                    settingsToggle("Notify when a student crosses high risk", isOn: $store.settings.notifyOnHighRisk)
                    settingsToggle("Include camera-off in scoring", isOn: $store.settings.includesCameraSignal)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
            }
        }
    }

    /// Label fills the row so the switches line up on the trailing edge.
    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Data & Privacy

    private var dataPrivacyContent: some View {
        Group {
            pageHeader("Data & Privacy", "What Anchor keeps, and where.")

            settingsCard(
                title: "Class history",
                subtitle: "Kept on this Mac only. Anchor never uploads a session."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                        Text(historySummary)
                            .font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                    }

                    Text(SessionArchive.fileURL.path(percentEncoded: false))
                        .font(.system(size: 9.5).monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Divider().padding(.vertical, 2)

                    // The window is stated, not just configurable. A teacher
                    // asked by their school what Anchor keeps and for how long
                    // should be able to read the answer off this pane and repeat
                    // it, which is also why the sentence below is the same one
                    // the privacy policy uses.
                    HStack(spacing: 7) {
                        Text("Keep history for")
                            .font(.system(size: 11, weight: .medium))

                        Picker("", selection: $archive.retention) {
                            ForEach(SessionArchive.RetentionWindow.allCases) { window in
                                Text(window.label).tag(window)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 210)

                        Spacer(minLength: 0)
                    }

                    Text(archive.retention.policySentence)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().padding(.vertical, 2)

                    HStack(spacing: 7) {
                        Button("Export Training Data…") {
                            TrainingDataExporter.export(
                                students: store.students,
                                meetingTitle: store.meetingTitle
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.students.isEmpty)
                        .help("Save this class's feature vectors as CSV for model retraining.")

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 7) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([SessionArchive.fileURL])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!archive.hasHistory)

                        Button("Clear Session Data") { isConfirmingClear = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!archive.hasHistory)

                        Spacer(minLength: 0)
                    }
                }
            }
            .confirmationDialog(
                "Delete all class history?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { archive.clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every recorded session and class from this Mac. "
                     + "This cannot be undone, and a live class in progress will start a fresh record.")
            }
        }
    }

    private var historySummary: String {
        guard archive.hasHistory else { return "No sessions recorded yet" }
        let sessions = archive.sessions.count
        let classes = archive.classrooms.count
        return "\(sessions) \(sessions == 1 ? "session" : "sessions") across "
            + "\(classes) \(classes == 1 ? "class" : "classes")"
    }

    // MARK: - About

    private var aboutContent: some View {
        Group {
            pageHeader("About", "")

            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 56, height: 56)
                    Image(systemName: "scope")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

                VStack(spacing: 2) {
                    Text("Anchor").font(.system(size: 14, weight: .semibold))
                    Text(appVersion).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            HStack(spacing: 7) {
                Button("Show Onboarding Again") {
                    OnboardingStore.shared.replay()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Nothing has gone wrong at this point — the teacher is
                // browsing — so this opens the support page rather than a
                // pre-filled bug report. The report path is attached to the
                // errors themselves, where the detail is known.
                Button("Get Help") {
                    NSWorkspace.shared.open(SupportContact.supportPageURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Quit Anchor") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }

    // MARK: - Card shell

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Theme.surface)
                )
        }
    }
}
