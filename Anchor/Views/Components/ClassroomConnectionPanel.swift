//
//  ClassroomConnectionPanel.swift
//  Anchor
//
//  Settings → Google Classroom: sign-in, course selection and sync status.
//
//  A teacher clicks Connect and signs in to Google in their browser; nothing is
//  typed here. The OAuth client behind that is the one the build ships with
//  (OAuthClientDefaults), and a school that would rather register its own —
//  which keeps their Classroom data reachable only by their own app — can
//  replace it under Advanced.
//

import SwiftUI

struct ClassroomConnectionPanel: View {
    @ObservedObject private var classroom = ClassroomViewModel.shared
    @ObservedObject private var credentials = GoogleCredentialsStore.shared

    // Debug-only, gated at the declaration as well as the call site, so a
    // Release build compiles none of it. See ConnectionStatusView for the
    // reasoning; this file is the simpler half — nothing here is shared with
    // the panel a teacher sees.
#if DEBUG
    @State private var clientIDDraft = ""
    @State private var clientSecretDraft = ""
    @State private var showAdvanced = false
#endif
    @State private var isConnecting = false
    /// True only for a sync the teacher started from this panel, so the
    /// scheduled one never surfaces a spinner here.
    @State private var isManuallySyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            if !classroom.isConnected {
                Text("Sign in with the Google account that owns your classes. Anchor "
                     + "opens Google in your browser and only ever reads — it never "
                     + "posts, grades or changes anything in Classroom.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow

            if !credentials.hasClientID {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .padding(.top, 1)
                    Text("This copy of Anchor is missing part of its Google setup, so "
                         + "sign-in can't open. It isn't something you can fix from here.")
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.riskHigh)
            }

            // Credential entry is Debug-only. §4 of the ship checklist exists to
            // get this out of a teacher's Settings entirely: both client IDs
            // ship in OAuthClientDefaults, so a shipped build has nothing to ask
            // a teacher for, and a field asking anyway invites them to believe
            // something is missing.
            //
            // CORRECTED 2026-08-24. This comment used to claim "neither
            // integration needs a secret — Zoom runs as a public client, and
            // Google documents client_secret as *optional* for installed apps,
            // with PKCE standing in for it". Half right, and the wrong half was
            // load-bearing. Both halves were probed directly:
            //
            //   Zoom, public client, no secret  -> invalid_grant  (client OK)
            //   Google, Desktop client, no secret
            //       -> {"error":"invalid_request",
            //           "error_description":"client_secret is missing."}
            //
            // Google requires it. PKCE does not stand in for it. The secret now
            // arrives at build time from Config/Secrets.xcconfig, and the
            // Connect gates read `canCompleteSignIn` so an unprovisioned build
            // refuses before opening a browser rather than after consent.
            //
            // Note also that the ANCHOR_* environment variables mentioned below
            // are all Zoom — there has never been one for Google, which is why
            // a Release build had no route to receive this secret at all.
            //
            // Deliberately #if DEBUG rather than deleted. It is still the
            // fastest way to point a development build at a different
            // registration.
#if DEBUG
            advancedDisclosure
#endif

            if classroom.isConnected {
                Divider().overlay(Theme.hairline)
                coursePicker
            }

            if let error = classroom.lastError {
                errorRow(error)
            }

            // A partial grant connects successfully and then quietly does less.
            // Said here as well as on Home, since this is where a teacher comes
            // to fix it.
            if let warning = classroom.scopeWarning {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .padding(.top, 1)
                    Text(warning)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.riskElevated)
            }

            // Keychain problems are reported by the credential store, not the
            // view model, and were previously invisible.
            if let storeError = credentials.lastError {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .padding(.top, 1)
                    Text(storeError)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.riskElevated)
            }

            if classroom.unmatchableStudentCount > 0 {
                unmatchedNote
            }

            if classroom.ambiguouslyNamedStudentCount > 0 {
                sharedNameNote
            }
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: classroom.state.symbolName)
                    .font(.system(size: 8, weight: .bold))
                Text(classroom.state.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(statusTint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(statusTint.opacity(0.14)))

            Text(classroom.summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var statusTint: Color {
        switch classroom.state {
        case .connected: Theme.riskLow
        case .connecting: Theme.riskElevated
        case .failed: Theme.riskHigh
        case .notConnected: .secondary
        }
    }

    // MARK: - Client ID

#if DEBUG
    /// The OAuth client registration — a deployment concern, not a teacher's.
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 4) {
                Text(credentials.isUsingBundledClient
                     ? "Anchor is using the Google client this build ships with. "
                        + "Override it to use your school's own."
                     : "Using your own Google OAuth client.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Google OAuth client ID")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField("123…apps.googleusercontent.com", text: $clientIDDraft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 11))

                Text("Client secret")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                SecureField(credentials.hasClientSecret ? "••••••••" : "GOCSPX-…",
                            text: $clientSecretDraft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 11))

                HStack(spacing: 7) {
                    Button("Save Client") {
                        credentials.saveClient(id: clientIDDraft, secret: clientSecretDraft)
                        clientSecretDraft = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !credentials.isUsingBundledClient && credentials.clientIDOverride != nil {
                        Button("Use Built-in") {
                            credentials.saveClient(id: "", secret: nil)
                            clientIDDraft = ""
                            clientSecretDraft = ""
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 10))
                    }

                    Spacer(minLength: 0)
                }

                Text("Google Cloud console → APIs & Services → Credentials → "
                     + "Create OAuth client ID → Desktop app. Enable the Google "
                     + "Classroom API on the same project. The secret is REQUIRED: "
                     + "probed 2026-08-24, Google's token endpoint answers "
                     + "\"client_secret is missing.\" for a Desktop client even with "
                     + "a valid PKCE verifier, so an empty secret is a gap rather "
                     + "than a supported configuration — sign-in fails after the "
                     + "teacher has already consented. Shipped builds get it from "
                     + "Config/Secrets.xcconfig at build time. "
                     + "Google refuses custom URL schemes for this client type — "
                     + "the redirect is a loopback port Anchor opens for the sign-in.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .onAppear { clientIDDraft = credentials.clientIDOverride ?? "" }
    }
#endif

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 7) {
            if classroom.isConnected {
                Button("Disconnect") { classroom.disconnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Sync Now") {
                    Task {
                        isManuallySyncing = true
                        defer { isManuallySyncing = false }
                        await classroom.syncNow()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!classroom.isMonitoringAnyCourse || isManuallySyncing)
            } else {
                Button(isConnecting ? "Opening browser…" : "Connect Google Classroom") {
                    Task {
                        isConnecting = true
                        defer { isConnecting = false }
                        await classroom.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!credentials.canCompleteSignIn || isConnecting)
            }

            // Only for a sync the teacher pressed the button for. The scheduled
            // one is background work and stays silent — a spinner appearing on
            // its own every ten minutes is exactly the noise this panel doesn't
            // need. A button press with no feedback, on the other hand, reads as
            // broken.
            if isManuallySyncing {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Course

    /// Which classes Anchor syncs coursework for. A list of toggles rather than
    /// a picker: a teacher takes several classes, and each is synced on its own.
    private var coursePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Classes to monitor")
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 0)

                if classroom.isMonitoringAnyCourse {
                    Button("None") { classroom.stopMonitoringAll() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 10))
                }

                Button("Reload") { Task { await classroom.loadCourses() } }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 10))
            }

            if classroom.courses.isEmpty {
                Text("No active courses found for this Google account.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(classroom.courses) { course in
                        courseToggle(course)
                    }
                }
            }

            Text("Only the ticked courses are read. Anchor never writes to Classroom, "
                 + "and grades are held in memory only — they are never written to the "
                 + "session archive or any log. A meeting is scored against the class "
                 + "you linked it to on Home; monitoring more classes doesn't mix their "
                 + "rosters together.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func courseToggle(_ course: ClassroomCourse) -> some View {
        Toggle(isOn: monitorBinding(for: course)) {
            HStack(spacing: 5) {
                Text(course.displayName)
                    .font(.system(size: 11))
                    .lineLimit(1)

                if course.enrolledAsStudent {
                    Text("enrolled as a student")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                } else if let error = classroom.lastSyncError(courseID: course.id) {
                    // No spinner for a sync in progress — it runs on its own
                    // clock and the teacher isn't waiting on it. A failure is
                    // worth a line, because the "synced 3 min ago" below would
                    // otherwise be the only thing they see and it would be wrong.
                    Text(error.localizedDescription)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.riskElevated)
                        .lineLimit(2)
                } else if let synced = classroom.lastSynced(courseID: course.id) {
                    Text("synced \(Theme.relativeString(from: synced, to: Date()).lowercased())")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        // Google shows a student nobody's coursework but their own, so there is
        // nothing here to sync.
        .disabled(course.enrolledAsStudent)
    }

    private func monitorBinding(for course: ClassroomCourse) -> Binding<Bool> {
        Binding(
            get: { classroom.isMonitored(courseID: course.id) },
            set: { classroom.setMonitored($0, courseID: course.id) }
        )
    }

    // MARK: - Notices

    private func errorRow(_ error: ClassroomError) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .padding(.top, 1)
            Text([error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " "))
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(error.requiresUserAction ? Theme.riskHigh : Theme.riskElevated)
    }

    /// Students Anchor has nothing at all to match on — say so once here rather
    /// than leaving the teacher to notice gaps per student.
    ///
    /// **This note used to fire for the whole class**, because its count was
    /// `matchKey == nil` and Google stopped returning roster addresses on
    /// 2026-08-17. It also said their coursework would not affect any score,
    /// which was false for exactly the same reason: matching moved to the name
    /// and kept working. Now it counts entries with no address *and* no usable
    /// name, which is the case it was always describing.
    private var unmatchedNote: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
                .padding(.top, 1)
            Text("\(classroom.unmatchableStudentCount) student(s) on this roster have "
                 + "neither an email address nor a usable name, so Anchor has nothing to "
                 + "match them on. Link them by hand from a student's card during a class.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    /// The common case, and the one worth naming separately: two students whose
    /// names normalise alike.
    ///
    /// Anchor refuses to guess between them on purpose — showing one student's
    /// grades under another's name is worse than showing none — so this is a
    /// recovery the teacher can complete in two clicks, not a dead end. Said
    /// here, once, because noticing it per-student means noticing it mid-class.
    private var sharedNameNote: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "person.2")
                .font(.system(size: 9))
                .padding(.top, 1)
            Text("\(classroom.ambiguouslyNamedStudentCount) student(s) share a name with "
                 + "someone else on this roster. Anchor won't guess which is which, so "
                 + "they stay unlinked until you pick — use Link to student… on their "
                 + "card during a class.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}
