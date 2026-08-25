//
//  AccountStep.swift
//  Anchor
//
//  Step 2 of onboarding: create an Anchor account or sign in to one.
//
//  This is the first screen in Anchor's history that asks a teacher for a
//  credential, and the copy is written around that. QA-PROTOCOL.md Pass A was
//  scripted against a flow that "never asks for a credential"; the sentence at
//  the foot of this screen is what has to earn the new one — it says plainly
//  what the account is for and, just as importantly, what it is not for.
//
//  Class data is not part of it. Rosters, scores, transcripts and session
//  history stay on the Mac exactly as before; the account carries an email, a
//  name and a Firebase uid. If that ever stops being true, this screen is
//  lying and the privacy policy is too.
//

import SwiftUI

struct AccountStep: View {

    /// Sign up and sign in share every field but the name, so they are one
    /// screen with a mode rather than two screens a teacher can get lost
    /// between.
    enum Mode: String, CaseIterable, Identifiable {
        case signUp, signIn
        var id: String { rawValue }

        var title: String {
            switch self {
            case .signUp: "Create account"
            case .signIn: "Sign in"
            }
        }
    }

    @ObservedObject private var accounts = AccountStore.shared
    @ObservedObject private var profile = TeacherProfileStore.shared

    @State private var mode: Mode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var resetNotice: String?

    @FocusState private var focusedField: Field?
    private enum Field { case name, email, password }

    var body: some View {
        VStack(spacing: 18) {
            if let account = accounts.account {
                signedIn(account)
            } else if !accounts.isConfigured {
                notConfigured
            } else {
                signInForm
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signed in

    private func signedIn(_ account: AnchorAccount) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.riskLow.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.riskLow)
            }

            VStack(spacing: 6) {
                Text("You're signed in")
                    .font(.system(size: 20, weight: .semibold))
                Text(account.label)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("via \(account.provider.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button("Sign out") { accounts.signOut() }
                .buttonStyle(.bordered)
                .controlSize(.regular)

            privacyNote
        }
        .padding(.top, 12)
    }

    // MARK: - Not configured

    /// Shown instead of the form when this build has no Firebase package or no
    /// `GoogleService-Info.plist`.
    ///
    /// The form is not merely disabled here — it is not shown at all. Rendering
    /// email and password fields above a dead "Create account" button, with no
    /// sentence saying why, is the same defect as an error message pointing a
    /// teacher at a DEBUG-only Advanced panel: it asks them to work out that
    /// the problem is not theirs. It is also the state a teacher meets if the
    /// plist was left out of the build, so it has to read as an explanation
    /// rather than a failure.
    private var notConfigured: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.riskElevated.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Theme.riskElevated)
            }

            VStack(spacing: 6) {
                Text("Accounts aren't set up yet")
                    .font(.system(size: 20, weight: .semibold))
                Text("Anchor's account setup isn't finished on this Mac, so there's nothing "
                     + "to sign in to yet. Everything else works — carry on, and whoever "
                     + "installed Anchor can finish this in one step.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }

            privacyNote
        }
        .padding(.top, 12)
    }

    // MARK: - Form

    private var signInForm: some View {
        VStack(spacing: 16) {
            header

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .disabled(accounts.isBusy)

            googleButton

            if !accounts.canSignInWithGoogle {
                Text("Google sign-in isn't set up in this build — use an email address "
                     + "and password instead.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }

            HStack(spacing: 10) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text("or")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            .frame(maxWidth: 300)

            fields

            Button(mode.title) { submit() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit)

            if mode == .signIn {
                Button("Forgot password?") { Task { await resetPassword() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.accent)
                    .disabled(email.trimmed.isEmpty || accounts.isBusy)
            }

            if let resetNotice {
                Text(resetNotice)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.riskLow)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = accounts.lastError {
                ErrorNotice(
                    message: [error.errorDescription, error.recoverySuggestion]
                        .compactMap { $0 }
                        .joined(separator: " "),
                    isSetupProblem: error.isSetupProblem
                )
            }

            privacyNote
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 64, height: 64)
                AnchorGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
            }

            VStack(spacing: 5) {
                Text(mode == .signUp ? "Create your Anchor account" : "Welcome back")
                    .font(.system(size: 20, weight: .semibold))
                Text(mode == .signUp
                     ? "Your account keeps your settings and connected tools together."
                     : "Sign in to pick up where you left off.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }
        }
    }

    private var googleButton: some View {
        Button {
            Task { await accounts.signInWithGoogle() }
        } label: {
            HStack(spacing: 8) {
                // Google's brand guidelines don't allow redrawing the mark, and
                // SF Symbols has no Google glyph, so this is a neutral badge
                // rather than an approximation of one.
                Text("G")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.accent.opacity(0.14)))
                Text("Continue with Google")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .frame(maxWidth: 280)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        // Not merely `isConfigured`: without the Google client secret this
        // button would open a browser, collect consent, and fail on the
        // exchange. Better to not offer it.
        .disabled(accounts.isBusy || !accounts.canSignInWithGoogle)
    }

    private var fields: some View {
        VStack(spacing: 10) {
            if mode == .signUp {
                // Prefilled from, and written back to, the same store the name
                // step uses — so a teacher who signs up with a name is not
                // asked for it again two screens later.
                field("Your name", text: $profile.name, isSecure: false, focus: .name)
            }
            field("Email", text: $email, isSecure: false, focus: .email)
            field("Password", text: $password, isSecure: true, focus: .password)

            if mode == .signUp {
                Text("At least 8 characters.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .frame(maxWidth: 300)
    }

    @ViewBuilder
    private func field(
        _ placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        focus: Field
    ) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focusedField == focus ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1)
        )
        .focused($focusedField, equals: focus)
        .disabled(accounts.isBusy)
        .onSubmit { submit() }
    }

    private var privacyNote: some View {
        Text("Your account holds your name and email — nothing about your classes. "
             + "Rosters, scores and session history stay on this Mac.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 340)
    }

    // MARK: - Actions

    /// Eight characters is Firebase's own floor for `createUser`; enforcing it
    /// here means a teacher is told before the round trip rather than after it.
    private var canSubmit: Bool {
        guard !accounts.isBusy, accounts.isConfigured else { return false }
        guard email.trimmed.contains("@") else { return false }
        return mode == .signUp ? password.count >= 8 : !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        resetNotice = nil
        Task {
            switch mode {
            case .signUp:
                await accounts.signUp(
                    email: email,
                    password: password,
                    displayName: profile.name.trimmed.isEmpty ? nil : profile.name
                )
            case .signIn:
                await accounts.signIn(email: email, password: password)
            }
            // Never leave a password sitting in view state after the attempt,
            // whichever way it went.
            password = ""
        }
    }

    private func resetPassword() async {
        resetNotice = nil
        if await accounts.sendPasswordReset(email: email) {
            resetNotice = "Sent. Check \(email.trimmed) for a reset link."
        }
    }
}
