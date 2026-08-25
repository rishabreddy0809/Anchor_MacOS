//
//  AccountStore.swift
//  Anchor
//
//  The signed-in teacher, observable by any view.
//
//  Shaped like the stores it sits beside — `OnboardingStore`, `ZoomOAuthStore`,
//  `GoogleCredentialsStore`: a `@MainActor` singleton publishing state, with
//  the network work pushed into a service actor behind it.
//
//  ── What this store does NOT persist ────────────────────────────────────────
//
//  Nothing. Firebase keeps the session in the login Keychain under its own
//  service, refreshes the token on its own schedule, and restores it at launch
//  — so a second copy here could only ever disagree with it. That is a
//  deliberate departure from `ZoomCredentialsStore`, which persists because
//  Anchor runs that OAuth flow itself and nothing else would hold the token.
//
//  Worth knowing for QA Pass A: this adds a **fifth** Keychain item that
//  survives dragging Anchor to the Trash, alongside the four QA-PROTOCOL.md §0
//  already lists. A "fresh install" on a used Mac now also has to sign out, or
//  the account step will be skipped and the walkthrough will test a path no
//  pilot teacher walks.
//

import Combine
import SwiftUI

@MainActor
final class AccountStore: ObservableObject {

    static let shared = AccountStore()

    /// `.unknown` until Firebase reports. See `AccountState` for why this is
    /// not a `Bool`.
    @Published private(set) var state: AccountState = .unknown

    /// Set while a sign-in, sign-up or Google round trip is in flight, so the
    /// account step can disable its buttons rather than let a teacher press
    /// Continue twice.
    @Published private(set) var isBusy = false

    /// The last failure, cleared on the next attempt. Cancellations never land
    /// here — closing a browser tab is not an error worth a red banner, the
    /// same rule `ZoomStep` and `ClassroomStep` already follow.
    @Published var lastError: AccountError?

    private let service: FirebaseAuthService
    private var listenerHandle: Any?

    private init(service: FirebaseAuthService = .shared) {
        self.service = service
    }

    // MARK: - Lifecycle

    /// Called once at launch, after `FirebaseAuthService.configureIfNeeded()`.
    func start() {
        guard listenerHandle == nil else { return }

        guard service.isConfigured else {
            // No package, or no GoogleService-Info.plist. Resolve to signed-out
            // rather than sitting in `.unknown` forever — a spinner that never
            // stops is the worst of the three states to ship.
            state = .signedOut
            return
        }

        listenerHandle = service.observeAuthState { [weak self] account in
            guard let self else { return }
            self.state = account.map(AccountState.signedIn) ?? .signedOut
            self.mirrorNameIntoProfile(account)
        }
    }

    /// True when this build can offer accounts at all.
    var isConfigured: Bool { service.isConfigured }

    /// True when the Google button can complete a sign-in rather than merely
    /// start one. See `FirebaseAuthService.canSignInWithGoogle`.
    var canSignInWithGoogle: Bool { service.canSignInWithGoogle }

    var account: AnchorAccount? { state.account }
    var isSignedIn: Bool { state.isSignedIn }

    // MARK: - Actions

    func signUp(email: String, password: String, displayName: String?) async {
        await perform { try await self.service.signUp(email: email, password: password, displayName: displayName) }
    }

    func signIn(email: String, password: String) async {
        await perform { try await self.service.signIn(email: email, password: password) }
    }

    func signInWithGoogle() async {
        await perform { try await self.service.signInWithGoogle() }
    }

    func signOut() {
        do {
            try service.signOut()
            state = .signedOut
        } catch let error as AccountError {
            lastError = error
        } catch {
            lastError = .unknown(error.localizedDescription)
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        lastError = nil
        do {
            try await service.sendPasswordReset(email: email)
            return true
        } catch let error as AccountError {
            lastError = error
            return false
        } catch {
            lastError = .unknown(error.localizedDescription)
            return false
        }
    }

    // MARK: - Plumbing

    /// One place where busy state, error mapping and the cancellation rule live,
    /// so the four entry points above cannot drift apart on any of the three.
    private func perform(_ work: @escaping () async throws -> AnchorAccount) async {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            let account = try await work()
            state = .signedIn(account)
            mirrorNameIntoProfile(account)
        } catch let error as AccountError {
            guard !error.isCancellation else { return }
            lastError = error
        } catch {
            lastError = .unknown(error.localizedDescription)
        }
    }

    /// Copies a Google-supplied name into `TeacherProfileStore` when the teacher
    /// has not set one themselves.
    ///
    /// Only ever fills a blank. Overwriting would mean signing in with Google
    /// silently renames a teacher who typed "Ms. Rivera" on the name step to
    /// whatever their Google profile says — and the name step comes *after*
    /// this one in the flow, so the teacher's own answer must win.
    private func mirrorNameIntoProfile(_ account: AnchorAccount?) {
        guard let name = account?.displayName?.trimmed, !name.isEmpty else { return }
        let profile = TeacherProfileStore.shared
        guard profile.name.trimmed.isEmpty else { return }
        profile.name = name
    }
}
