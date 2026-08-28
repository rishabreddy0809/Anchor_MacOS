//
//  ConnectionStatusView.swift
//  Anchor
//
//  Small connection indicator shared by the popover footer and the window
//  toolbar, plus the Zoom setup panel used in Settings.
//

import SwiftUI

// MARK: - Status chip

struct ConnectionStatusChip: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.14)))
        .help(helpText)
    }

    private var label: String { zoom.state.label }

    private var symbolName: String { zoom.state.symbolName }

    private var tint: Color {
        switch zoom.state {
        case .connected: return Theme.riskLow
        case .connecting, .retrying, .waitingForMeeting: return Theme.riskElevated
        case .failed: return Theme.riskHigh
        case .idle: return .secondary
        }
    }

    private var helpText: String {
        store.connectionSummary ?? zoom.state.label
    }
}

// MARK: - Zoom settings panel

struct ZoomConnectionPanel: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var credentials = ZoomCredentialsStore.shared
    @ObservedObject private var oauth = ZoomOAuthStore.shared

    // Credential entry is Debug-only, and gated here at the declaration so a
    // Release build does not compile it at all. The call site in `body` is
    // gated too; this removes the dead views, their state and their strings
    // from the shipped binary, and lets TeacherFacingCopyTests scan this file
    // in full rather than exempting it.
    //
    // `testResult` and `testSucceeded` are deliberately NOT in here: `save()`
    // writes them, but so do `connect()` and `disconnect()`, which every
    // teacher uses.
#if DEBUG
    @State private var accountID = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
#endif
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false
#if DEBUG
    @State private var showSecretField = false
#endif
    @State private var meetingNumber = ""
    @State private var meetingPasscode = ""
#if DEBUG
    /// The Server-to-Server credentials and the OAuth app override both live
    /// behind this. A teacher never opens it; it exists for whoever sets a
    /// school up, and for the bot's own account.
    @State private var showAdvanced = false
    @State private var advancedClientID = ""
    @State private var advancedClientSecret = ""
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            accountRow

            // Directly under the buttons that produce it — a sign-in result
            // shown below the Advanced section reads as belonging to whatever
            // is nearest, and what's nearest there is the credential fields.
            if let testResult {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(testResult)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(testSucceeded ? Theme.riskLow : Theme.riskHigh)
            }

            // Credential entry is Debug-only. §4 of the ship checklist exists to
            // get this out of a teacher's Settings entirely: both client IDs
            // ship in OAuthClientDefaults, and neither integration needs a
            // secret to sign a teacher in — Zoom runs as a public client, and
            // Google documents client_secret as *optional* for installed apps,
            // with PKCE standing in for it. So a shipped build has nothing to
            // ask for, and a field asking anyway invites a teacher to believe
            // something is missing.
            //
            // Deliberately #if DEBUG rather than deleted. It is still the
            // fastest way to point a development build at a different
            // registration, and a managed deployment provisions through the
            // ANCHOR_* environment variables on first launch (see AppDelegate),
            // which is a path this never touched.
#if DEBUG
            advancedDisclosure
#endif

            if store.dataSource == .zoom, !store.capabilities.unavailableSignals.isEmpty {
                capabilityNote
            }

            if zoom.emailVerification.isDegraded {
                emailVerificationNote
            }

            Divider().overlay(Theme.hairline)
            botSection
        }
    }

    // MARK: In-meeting bot

    private var botSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: zoom.botSession == nil ? "person.badge.plus" : "person.fill.checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(zoom.botSession == nil ? .secondary : Theme.riskLow)
                Text("In-meeting bot")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                if zoom.botSession != nil {
                    Button("Leave") { Task { await zoom.leaveBot() } }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 10))
                }
            }

            Text(zoom.botStatus
                 ?? "Anchor watches for Zoom calls and offers to send a bot in. The bot is the only way to read mute, camera, raised hands and speaking time.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if zoom.needsMeetingNumber {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        TextField("Paste the invite, link, or meeting number", text: $meetingNumber)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.system(size: 11))
                            .onChange(of: meetingNumber) { _, pasted in
                                adoptPastedInvitation(pasted)
                            }
                        TextField("Passcode (optional)", text: $meetingPasscode)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.system(size: 11))
                            .frame(width: 110)
                        Button("Join") {
                            Task {
                                await zoom.joinBot(
                                    meetingNumber: pastedLink?.meetingNumber ?? meetingNumber.trimmed,
                                    passcode: meetingPasscode.isEmpty ? nil : meetingPasscode
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(pastedLink == nil)
                    }

                    // Said here rather than after a failed join. A personal-room
                    // link carries no meeting id at all, so the join would fail
                    // deep in the SDK with a message about the meeting number
                    // being wrong — which is true and useless, because the
                    // teacher pasted exactly what Zoom gave them.
                    if !meetingNumber.trimmed.isEmpty, pastedLink == nil {
                        Text("No meeting number in that. A personal room link "
                             + "(zoom.us/my/…) doesn't contain one — paste the "
                             + "invitation instead, or the number from your Zoom window.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        }
    }

    /// Whatever is currently in the field, understood.
    private var pastedLink: ZoomMeetingLink? {
        ZoomMeetingLink.parse(meetingNumber)
    }

    /// Collapses a pasted invitation into the two fields the moment it lands.
    ///
    /// The teacher sees the paragraph they pasted turn into a bare meeting
    /// number with the passcode filled in beside it, which is both the
    /// confirmation that Anchor understood it and the chance to correct it
    /// before joining. Doing this on paste rather than on Join matters: a join
    /// that silently used something other than what is on screen would be
    /// impossible to argue with when it failed.
    private func adoptPastedInvitation(_ raw: String) {
        // Only act on something that isn't already just the number. Without
        // this, every keystroke of a hand-typed id would be re-parsed and
        // written back, which fights the cursor. It also terminates the
        // re-entrant `onChange` this assignment triggers: the value written
        // back is bare digits, so the next pass stops here.
        guard raw.contains(where: { !$0.isNumber && !$0.isWhitespace && $0 != "-" }),
              let link = ZoomMeetingLink.parse(raw)
        else { return }

        meetingNumber = link.meetingNumber

        // Never overwrite a passcode already typed by hand — if the two
        // disagree, the human is the one who knows which meeting this is.
        if let passcode = link.passcode, meetingPasscode.trimmed.isEmpty {
            meetingPasscode = passcode
        }
    }

    // MARK: Rows

    private var statusRow: some View {
        HStack(spacing: 6) {
            ConnectionStatusChip()
            Text(store.connectionSummary ?? "Not connected to a meeting.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// The whole teacher-facing story: connected as whom, or one button.
    private var accountRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if oauth.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.riskLow)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Zoom connected")
                            .font(.system(size: 11, weight: .medium))
                        Text(oauth.accountLabel ?? "Signed in with your Zoom account")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                Text("Sign in with your own Zoom account. Anchor opens Zoom in your "
                     + "browser — there is nothing to copy or paste, and Anchor never "
                     + "sees your password.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow

            if !oauth.hasClientCredentials {
                noticeRow(
                    symbol: "exclamationmark.triangle.fill",
                    tint: Theme.riskHigh,
                    // "Sign-in can't open" was already the kinder half-truth — the
                    // browser opens fine, and that is exactly the problem. Say what
                    // actually happens instead.
                    text: "Anchor's Zoom setup isn't finished on this Mac. Zoom would ask "
                        + "you to approve Anchor and then refuse the connection, so the "
                        + "button is off until whoever installed Anchor finishes setup."
                )
            }

            if let storeError = oauth.lastError {
                noticeRow(
                    symbol: "exclamationmark.triangle.fill",
                    tint: Theme.riskElevated,
                    text: storeError
                )
            }
        }
    }

#if DEBUG
    /// Server-to-Server credentials and the OAuth app override — everything a
    /// teacher should never have to look at.
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 10) {
                oauthClientFields
                Divider().overlay(Theme.hairline)
                serverToServerFields
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .onAppear {
            advancedClientID = oauth.clientIDOverride ?? ""
            advancedClientSecret = ""
        }
    }

    private var oauthClientFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zoom OAuth app")
                .font(.system(size: 10.5, weight: .medium))

            Text("Anchor signs teachers in with the Zoom app this build ships with. "
                 + "Override it here to use your school's own. Redirect URL: "
                 + ZoomOAuthConfig.redirectURIForDisplay)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            labelledField("Client ID", text: $advancedClientID, prompt: oauth.clientID ?? "Jn_7…")

            VStack(alignment: .leading, spacing: 2) {
                Text("Client Secret")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                SecureField(
                    oauth.clientSecret == nil ? "Required by Zoom's token endpoint" : "••••••••",
                    text: $advancedClientSecret
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: 11))
            }

            HStack(spacing: 7) {
                Button("Save OAuth App") {
                    oauth.saveClientOverride(id: advancedClientID, secret: advancedClientSecret)
                    advancedClientSecret = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if oauth.clientIDOverride != nil {
                    Button("Use Built-in") {
                        oauth.saveClientOverride(id: "", secret: nil)
                        advancedClientID = ""
                        advancedClientSecret = ""
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 10))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var serverToServerFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server-to-Server OAuth")
                .font(.system(size: 10.5, weight: .medium))

            Text("Optional. Lets Anchor read meetings for the whole account without a "
                 + "teacher signed in, and is what the in-meeting bot authenticates with.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if credentials.hasCredentials && !showSecretField {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.riskLow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Credentials saved to Keychain")
                            .font(.system(size: 11, weight: .medium))
                        Text("Client ID \(credentials.credentials?.clientID ?? "—") · Secret \(credentials.credentials?.redactedSecret ?? "—")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Replace") {
                        accountID = credentials.credentials?.accountID ?? ""
                        clientID = credentials.credentials?.clientID ?? ""
                        clientSecret = ""
                        showSecretField = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 10))
                }
            } else {
                labelledField("Account ID", text: $accountID, prompt: "Cqx9_…")
                labelledField("Client ID", text: $clientID, prompt: "Jn_7…")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Client Secret")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    SecureField("Never stored in code", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .font(.system(size: 11))
                }

                Button("Save") { save() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canSave)
            }

            Text("Stored in the macOS Keychain, never in a file or in source.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }
#endif

    private func noticeRow(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }

#if DEBUG
    private func labelledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: 11))
        }
    }
#endif

    private var actionRow: some View {
        HStack(spacing: 7) {
            if oauth.isConnected {
                Button("Disconnect") { Task { await disconnect() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button(zoom.isConnectingAccount ? "Waiting for browser…" : "Connect Zoom") {
                    Task { await connect() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(zoom.isConnectingAccount || !oauth.hasClientCredentials)
            }

            if zoom.isConnectingAccount {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }

            Button(isTesting ? "Testing…" : "Test Connection") {
                Task { await test() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!ZoomViewModel.hasTeacherZoomConnection || isTesting)

            // Monitoring is separate from being signed in: a teacher can pause
            // polling between classes without giving up the connection.
            if store.dataSource == .zoom {
                Button("Stop Monitoring") { zoom.stop() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Start Monitoring") {
                    zoom.useLiveService()
                    zoom.start()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!ZoomViewModel.hasTeacherZoomConnection)
            }

            Spacer(minLength: 0)
        }
    }

    private var capabilityNote: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.riskElevated)
            Text(
                "Zoom's REST API does not expose "
                + store.capabilities.unavailableSignals.joined(separator: ", ")
                + " during a live meeting. Scores use presence data only until the Meeting SDK is added."
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Why students are being matched to Classroom by name instead of by a
    /// verified address. Distinct from `capabilityNote`, which is about missing
    /// *signals* — this one is about missing *identity*, and it changes whether
    /// academic data can be trusted at all.
    private var emailVerificationNote: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 10))
                .foregroundStyle(Theme.riskElevated)

            VStack(alignment: .leading, spacing: 2) {
                Text(zoom.emailVerification.headline)
                    .font(.system(size: 10.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = zoom.emailVerification.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

#if DEBUG
    private var canSave: Bool {
        !accountID.trimmed.isEmpty && !clientID.trimmed.isEmpty && !clientSecret.trimmed.isEmpty
    }

    private func save() {
        let saved = credentials.save(
            ZoomCredentials(accountID: accountID, clientID: clientID, clientSecret: clientSecret)
        )
        if saved {
            clientSecret = ""
            showSecretField = false
            testResult = "Saved to Keychain — connecting to Zoom."
            testSucceeded = true
            zoom.useLiveService()
            zoom.start()          // go live immediately rather than making the teacher click twice
        } else {
            testResult = credentials.lastError ?? "Could not save to the Keychain."
            testSucceeded = false
        }
    }
#endif

    private func connect() async {
        testResult = nil
        switch await zoom.connectAccount() {
        case .success(let info):
            testSucceeded = true
            testResult = "Connected as \(info.email ?? info.displayName)."
        case .failure(let error):
            testSucceeded = false
            // Cancelling isn't a failure worth a red banner — the teacher closed
            // the tab, and the button they need is right there.
            testResult = error == .authorizationCancelled
                ? "Sign-in didn't finish. Click Connect Zoom to try again."
                : [error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: " ")
        }
    }

    private func disconnect() async {
        await zoom.disconnectAccount()
        testResult = nil
        testSucceeded = false
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }

        switch await zoom.testConnection() {
        case .success(let info):
            testSucceeded = true
            testResult = "Connected as \(info.displayName)."
        case .failure(let error):
            testSucceeded = false
            testResult = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }
}
