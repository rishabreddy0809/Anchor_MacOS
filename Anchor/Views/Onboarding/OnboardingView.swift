//
//  OnboardingView.swift
//  Anchor
//
//  First-launch walkthrough, shown as a sheet over the main window until a
//  teacher finishes or skips it. Seven steps: what Anchor does, an Anchor
//  account, who's using it, a dedicated sign-in screen for Zoom, a dedicated
//  one for Google Classroom, a couple of preferences worth setting up front,
//  and a confirmation screen.
//
//  Skipping or finishing both mark onboarding complete — see OnboardingStore.
//
//  **The account step is the one exception to "nothing here is required".**
//  Continue stays disabled on it until the teacher has an account — but only
//  in a build where accounts actually work. If FirebaseAuth isn't linked or
//  GoogleService-Info.plist is missing, the gate lifts and the step becomes
//  informational, because a walkthrough that cannot be completed is worse than
//  one that skips a screen. That branch is what keeps QA-PROTOCOL.md Pass A
//  runnable on a build made before the Firebase package lands.
//
//  Every connection and setting offered here is also reachable from Settings
//  afterwards.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: EngagementStore
    @ObservedObject private var onboarding = OnboardingStore.shared
    @ObservedObject private var accounts = AccountStore.shared

    enum Step: Int, CaseIterable {
        case welcome, account, name, zoom, classroom, preferences, done
    }

    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            ScrollView(.vertical) {
                Group {
                    switch step {
                    case .welcome: WelcomeStep()
                    case .account: AccountStep()
                    case .name: NameStep()
                    case .zoom: ZoomStep()
                    case .classroom: ClassroomStep()
                    case .preferences: PreferencesStep()
                    case .done: FinishStep()
                    }
                }
                .padding(28)
                .frame(maxWidth: 480, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider().overlay(Theme.hairline)
            footer
        }
        .frame(width: 600, height: 640)
        .background(.background)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Group {
                if step != .welcome && step != .done {
                    Button("Skip") { onboarding.finish() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    // `Color.clear` alone has no intrinsic height and expands
                    // to fill whatever the parent offers — which, with no
                    // other row in this HStack pinning a height, was blowing
                    // the whole header up to most of the sheet. An empty
                    // Text keeps the same footprint as the Skip button
                    // without that runaway sizing.
                    Text("")
                        .font(.system(size: 11.5))
                }
            }
            .frame(width: 44, alignment: .leading)

            Spacer(minLength: 0)

            StepDots(current: step.rawValue, total: Step.allCases.count - 1)

            Spacer(minLength: 0)

            Text("")
                .font(.system(size: 11.5))
                .frame(width: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { back() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer(minLength: 0)

            Button(primaryLabel) { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
        }
        .padding(18)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: "Get Started"
        case .account, .name, .zoom, .classroom, .preferences: "Continue"
        case .done: "Go to Anchor"
        }
    }

    /// The account step is the only one that can hold the flow.
    ///
    /// Reads `isConfigured` first and deliberately fails *open*: in a build
    /// without Firebase there is no way to satisfy the gate, so gating would
    /// strand the teacher on step 2 with a disabled button and no explanation.
    /// The step itself already says setup is unfinished in that case.
    private var canAdvance: Bool {
        guard step == .account, accounts.isConfigured else { return true }
        return accounts.isSignedIn
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onboarding.finish()
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { step = next }
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeOut(duration: 0.2)) { step = previous }
    }
}

// MARK: - Step progress

private struct StepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0...total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.accent : Theme.hairline)
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

// MARK: - Shared header

private struct OnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 68, height: 68)
                    AnchorGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                }

                VStack(spacing: 6) {
                    Text("Welcome to Anchor")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Anchor watches your live classes and flags students who "
                         + "are quietly struggling — before it shows up in their grades.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(
                    symbol: "waveform.path.ecg",
                    tint: Theme.accent,
                    title: "Live engagement scoring",
                    detail: "Camera, mic, chat and hand-raises turn into a per-student "
                        + "risk score while class is running."
                )
                featureRow(
                    symbol: "graduationcap.fill",
                    tint: Theme.riskLow,
                    title: "Classwork in context",
                    detail: "Connect Google Classroom to see missing work and grade "
                        + "trends alongside engagement."
                )
                featureRow(
                    symbol: "lock.fill",
                    tint: Theme.riskElevated,
                    title: "Kept on this Mac",
                    detail: "Class history is stored locally and never uploaded anywhere."
                )
            }
        }
    }

    private func featureRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 2: Name

private struct NameStep: View {
    @ObservedObject private var profile = TeacherProfileStore.shared
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Image(systemName: "person.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

                VStack(spacing: 6) {
                    Text("What should we call you?")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Anchor uses this to personalize your dashboard and alerts.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextField("e.g. Ms. Rivera", text: $profile.name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isFocused ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1)
                )
                .focused($isFocused)
                .onAppear { isFocused = true }

            Text("Optional — you can change this later in Settings.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}

// MARK: - Steps 3 & 4: Integrations, one per screen

/// The hero layout shared by the Zoom and Classroom steps: icon, tagline,
/// what connecting gets them, and the connect/disconnect action itself. Each
/// integration gets its own full step rather than sharing a list — this is
/// the one chance to walk a teacher through *why* before asking for a
/// sign-in, and a shared row list left no room for that.
private struct IntegrationHeroStep: View {
    let symbolName: String
    let tint: Color
    let title: String
    let tagline: String
    let benefits: [String]
    let isConnected: Bool
    let isBusy: Bool
    let canConnect: Bool
    let unavailableReason: String?
    let connectedDetail: String
    let privacyNote: String
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 76, height: 76)
                    Image(systemName: symbolName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 21, weight: .semibold))
                    Text(tagline)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(benefits, id: \.self) { benefit in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(tint)
                        Text(benefit)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: 340, alignment: .leading)

            VStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small)
                    Text("Opening browser…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.riskLow)
                        Text(connectedDetail)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Disconnect") { onDisconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                } else {
                    Button("Connect \(title)") { onConnect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canConnect)
                }

                if let unavailableReason, !canConnect {
                    Text(unavailableReason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.riskElevated)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 360)
                }
            }

            Text(privacyNote)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private struct ZoomStep: View {
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var oauth = ZoomOAuthStore.shared

    @State private var isBusy = false

    /// The error itself rather than its description: `ErrorNotice` needs to
    /// know whether the teacher can act on it, which only the value knows.
    @State private var error: ZoomError?

    var body: some View {
        VStack(spacing: 14) {
            IntegrationHeroStep(
                symbolName: "video.fill",
                tint: Color(red: 0.15, green: 0.47, blue: 0.94),
                title: "Zoom",
                tagline: "Sign in with your Zoom account so Anchor can watch your classes as they happen.",
                benefits: [
                    "Live roster while class is running",
                    "Mute, camera and hand-raise signals",
                    "Optional in-meeting bot for speaking time"
                ],
                isConnected: oauth.isConnected,
                isBusy: isBusy,
                canConnect: oauth.hasClientCredentials,
                unavailableReason: oauth.hasClientCredentials
                    ? nil
                    // Was "Add one in Settings → Zoom connection → Advanced",
                    // which is a `#if DEBUG` panel — so in the build a teacher
                    // actually runs, that sentence pointed at a screen that is
                    // not there. Same class of defect as the three strings the
                    // Advanced disclosure left wrong in HANDOFF.md.
                    : "Anchor's Zoom setup isn't finished on this Mac, so sign-in "
                        + "would fail after you signed in. Whoever installed Anchor "
                        + "can finish it in one step — you can skip this and connect later.",
                connectedDetail: oauth.accountLabel.map { "Connected as \($0)" } ?? "Connected",
                privacyNote: "Anchor opens Zoom in your browser to sign in — nothing is "
                    + "typed here, and Anchor never sees your password.",
                onConnect: connect,
                onDisconnect: disconnect
            )

            if let error {
                ErrorNotice(
                    message: [error.errorDescription, error.recoverySuggestion]
                        .compactMap { $0 }
                        .joined(separator: " "),
                    isSetupProblem: error.isSetupProblem,
                    technicalDetail: error.technicalDetail
                )
            }
        }
    }

    private func connect() {
        error = nil
        Task {
            isBusy = true
            defer { isBusy = false }
            switch await zoom.connectAccount() {
            case .success:
                break
            case .failure(let failure):
                // Cancelling isn't worth a red banner — the teacher closed the tab.
                guard failure != .authorizationCancelled else { return }
                error = failure
            }
        }
    }

    private func disconnect() {
        Task { await zoom.disconnectAccount() }
    }
}

private struct ClassroomStep: View {
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var credentials = GoogleCredentialsStore.shared

    @State private var isBusy = false
    @State private var error: ClassroomError?

    var body: some View {
        VStack(spacing: 14) {
            IntegrationHeroStep(
                symbolName: "graduationcap.fill",
                tint: Color(red: 0.20, green: 0.60, blue: 0.36),
                title: "Google Classroom",
                tagline: "Optional. Connect Classroom to see missing work and grade "
                    + "trends alongside engagement.",
                benefits: [
                    "Missing assignments per student",
                    "Grade trend context on every score",
                    "Read-only — Anchor never posts or grades"
                ],
                isConnected: classroom.isConnected,
                isBusy: isBusy,
                // Gated on `canCompleteSignIn`, not `hasClientID`.
                //
                // CORRECTED 2026-08-24. The comment that stood here said this
                // branch was "not expected to be reachable — googleClientID
                // ships non-empty and Google genuinely accepts PKCE without a
                // secret". The second half was false, and it was the load-
                // bearing half. Probing Google's token endpoint with a valid
                // client id, a PKCE verifier and no secret returns
                // `client_secret is missing`, so with no secret provisioned
                // this branch was reachable by EVERY teacher — and worse, it
                // was not reached here at all: `hasClientID` was true, the
                // button was offered, the browser opened, consent was granted,
                // and the failure landed after it. The note ended "unreachable
                // is what the Zoom branch was assumed to be too", which turned
                // out to be the most accurate sentence in it.
                canConnect: credentials.canCompleteSignIn,
                unavailableReason: credentials.canCompleteSignIn
                    ? nil
                    : "Anchor's Google setup isn't finished on this Mac, so signing in "
                        + "would fail after you'd already approved it in your browser. "
                        + "Classroom is optional — carry on without it, and whoever "
                        + "installed Anchor can finish setup later.",
                connectedDetail: credentials.tokens?.accountEmail ?? "Connected",
                privacyNote: "Anchor opens Google in your browser to sign in, and only "
                    + "ever reads Classroom — it never posts, grades or changes anything.",
                onConnect: connect,
                onDisconnect: disconnect
            )

            if let error {
                ErrorNotice(
                    message: [error.errorDescription, error.recoverySuggestion]
                        .compactMap { $0 }
                        .joined(separator: " "),
                    isSetupProblem: error.isSetupProblem,
                    technicalDetail: error.technicalDetail
                )
            }
        }
    }

    private func connect() {
        error = nil
        Task {
            isBusy = true
            defer { isBusy = false }
            await classroom.connect()
            // Cancelling isn't worth a red banner here either — matches Zoom.
            if let failure = classroom.lastError, failure != .authorizationCancelled {
                error = failure
            }
        }
    }

    private func disconnect() {
        classroom.disconnect()
    }
}

// MARK: - Step 5: Preferences

private struct PreferencesStep: View {
    @EnvironmentObject private var store: EngagementStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                title: "Tune it to your classroom",
                subtitle: "You can change any of this later in Settings."
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.settings.sensitivityLabel)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("High risk at \(thresholdPercent)%+")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $store.settings.sensitivity, in: 0...1)
                    .controlSize(.small)

                HStack {
                    Text("Conservative")
                    Spacer()
                    Text("Very alert")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $store.settings.notifyOnHighRisk) {
                    Text("Notify me when a student crosses high risk")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle(isOn: $store.settings.showsBadge) {
                    Text("Show a menu bar badge for high-risk students")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private var thresholdPercent: Int {
        Int((RiskLevel.highThreshold(sensitivity: store.settings.sensitivity) * 100).rounded())
    }
}

// MARK: - Step 6: Finish

private struct FinishStep: View {
    @ObservedObject private var oauth = ZoomOAuthStore.shared
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var profile = TeacherProfileStore.shared
    @ObservedObject private var accounts = AccountStore.shared

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.riskLow.opacity(0.14))
                    .frame(width: 68, height: 68)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.riskLow)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Only shown when this build has accounts at all — otherwise
                // the row would report "not signed in" as though the teacher
                // had skipped something they were never offered.
                if accounts.isConfigured {
                    summaryRow(
                        connected: accounts.isSignedIn,
                        label: accounts.account.map { "Signed in as \($0.label)" }
                            ?? "Not signed in"
                    )
                }
                summaryRow(
                    connected: oauth.isConnected,
                    label: oauth.isConnected ? "Zoom connected" : "Zoom not connected yet"
                )
                summaryRow(
                    connected: classroom.isConnected,
                    label: classroom.isConnected ? "Google Classroom connected" : "Google Classroom not connected yet"
                )
            }
            .padding(14)
            .frame(maxWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func summaryRow(connected: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 12))
                .foregroundStyle(connected ? Theme.riskLow : .secondary)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(connected ? .primary : .secondary)
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        // `AccountStore` already mirrors a Google-supplied name into the
        // profile when the profile is blank, so this fallback only matters for
        // the ordering case where the mirror hasn't landed yet.
        guard let first = profile.firstName ?? accounts.account?.firstName else {
            return "You're all set"
        }
        return "You're all set, \(first)"
    }

    private var subtitle: String {
        oauth.isConnected
            ? "Start a Zoom class and Anchor picks it up automatically — no need to open the app."
            : "Connect Zoom any time from Settings, and Anchor will start scoring your next class automatically."
    }
}
