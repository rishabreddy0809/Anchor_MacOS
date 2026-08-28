//
//  OnboardingStore.swift
//  Anchor
//
//  Whether the first-launch onboarding flow has been completed.
//
//  Two flags rather than one: `hasCompletedOnboarding` is the durable record,
//  written to UserDefaults; `isPresented` is transient and drives the sheet
//  directly, so replaying onboarding from Settings doesn't need to touch the
//  completion record until the teacher actually finishes it again.
//
//  The durable record is **per account**. It used to live in
//  `UserDefaults.standard`, which meant the first teacher to finish onboarding
//  finished it for everyone who ever signed in on that Mac — a second Google
//  account landed straight on somebody else's Home tab. See `AccountScope`.
//

import Combine
import SwiftUI

@MainActor
final class OnboardingStore: ObservableObject {

    static let shared = OnboardingStore()

    private static let completedKey = "anchor.onboarding.completed"

    @Published private(set) var hasCompletedOnboarding: Bool
    @Published var isPresented = false

    /// Pinned by a test; `nil` follows whichever account is signed in.
    private let pinnedDefaults: UserDefaults?
    private var defaults: UserDefaults { pinnedDefaults ?? AccountScope.shared.defaults }
    private var scopeObserver: Any?

    init(defaults: UserDefaults? = nil) {
        self.pinnedDefaults = defaults
        self.hasCompletedOnboarding = (defaults ?? AccountScope.shared.defaults)
            .bool(forKey: Self.completedKey)
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// A different teacher is now signed in.
    ///
    /// Their completion record is their own, so the walkthrough comes back for
    /// an account that has never seen it and stays away from one that has.
    ///
    /// **`isPresented` is deliberately left alone.** This used to close the
    /// sheet, on the reasoning that a replay left open by the previous teacher
    /// has nothing to do with this one — which is true and was still wrong,
    /// because the commonest way to reach this method is a teacher signing in
    /// *from inside the walkthrough*, on the account step. Dismissing there
    /// tore down the flow at the exact moment it was supposed to carry on to
    /// the next screen. `OnboardingView` decides what to do with the sheet, and
    /// it is the only thing that can: it is the one that knows the teacher is
    /// standing in it.
    private func accountDidChange() {
        guard pinnedDefaults == nil else { return }
        hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
    }

    /// Called once, from the main window's `onAppear`.
    func presentIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        isPresented = true
    }

    /// Whether the walkthrough should close itself the instant an account
    /// signs in, instead of walking a returning teacher round a flow they
    /// finished last term.
    ///
    /// Lifted out pure for the same reason as
    /// `AccountStore.requiresSignIn(isConfigured:isSignedIn:)`: it is the whole
    /// decision behind the signed-out gate opening this walkthrough for
    /// everybody, and it lives in a SwiftUI `onChange` where nothing can reach
    /// it. Both halves matter. Without the uid check it would fire on sign-*out*
    /// and close the flow that had just been opened to sign back in; without
    /// the completion check every returning teacher gets the full tour.
    nonisolated static func shouldFinishOnSignIn(uid: String?, hasCompletedOnboarding: Bool) -> Bool {
        uid != nil && hasCompletedOnboarding
    }

    /// Reached by finishing the flow or by Skip — both mean the teacher has
    /// seen it and it shouldn't come back on its own.
    func finish() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.completedKey)
        isPresented = false
    }

    /// Opens the walkthrough whether or not it has been completed.
    ///
    /// The signed-out gate needs this: there is no account yet, so there is no
    /// completion record to consult — `hasCompletedOnboarding` at that moment
    /// describes nobody. The walkthrough itself sorts out which kind of teacher
    /// arrived, by closing immediately when the account that signs in turns out
    /// to have finished it already. See `OnboardingView`.
    func present() {
        isPresented = true
    }

    /// "Show onboarding again" in Settings. Doesn't clear the completion
    /// record until the teacher reaches the end again, so dismissing this
    /// replay early doesn't resurrect it on next launch.
    func replay() {
        present()
    }
}
