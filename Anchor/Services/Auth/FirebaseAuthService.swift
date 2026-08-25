//
//  FirebaseAuthService.swift
//  Anchor
//
//  The only file in Anchor that imports Firebase.
//
//  Everything above it — `AccountStore`, `AccountStep`, the onboarding flow —
//  speaks in `AnchorAccount` and `AccountError`. That containment is the point:
//  Firebase is the first third-party dependency this project has ever taken
//  through the package manager (the Zoom SDK is vendored), and confining it to
//  one file keeps the decision reversible.
//
//  ── The canImport guard ─────────────────────────────────────────────────────
//
//  The Swift sources land in the target automatically (the project uses Xcode
//  16 filesystem-synchronized groups), but the *package* has to be added in
//  Xcode once. Between those two moments `import FirebaseAuth` would fail and
//  the whole app would stop compiling — and HANDOFF.md's own hard-won lesson is
//  that a build which does not compile is indistinguishable from a feature that
//  does not fire. So the guard below keeps the project building, and the
//  fallback fails **loudly and visibly** with `.notConfigured`, which the UI
//  renders as a setup problem. It is not a silent no-op.
//
//  Once the package is linked the guard is inert and can be deleted.
//
//  ── Setup, once ─────────────────────────────────────────────────────────────
//
//  1. Xcode → File → Add Package Dependencies →
//     https://github.com/firebase/firebase-ios-sdk
//     Add **FirebaseAuth only**. Not Firestore, Analytics or Crashlytics —
//     each drags in binaries that the Zoom re-signing build phase would then
//     have to handle, and Anchor stores nothing in the cloud to justify them.
//  2. Firebase console → Project settings → your macOS app → download
//     `GoogleService-Info.plist` into `Anchor/` (synchronized groups pick it
//     up; confirm it appears under Copy Bundle Resources).
//  3. Firebase console → Authentication → Sign-in method → enable
//     **Email/Password** and **Google**.
//  4. Under the Google provider, add Anchor's existing Desktop OAuth client
//     (`OAuthClientDefaults.googleClientID`) to the allowed client IDs, so the
//     ID token minted by GoogleIdentitySignIn is accepted.
//

import Foundation
import os

#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif

/// Wraps Firebase Authentication. Stateless — `AccountStore` holds the state.
@MainActor
final class FirebaseAuthService {

    static let shared = FirebaseAuthService()

    private let logger = Logger(subsystem: "com.anchor.account", category: "Firebase")
    private let identityClient = GoogleIdentityClient()

    private init() {}

    // MARK: - Availability

    /// False when the package is missing or `GoogleService-Info.plist` was
    /// never added. Checked before any screen offers to sign a teacher in, so
    /// the failure appears on the account step rather than after they have
    /// typed a password.
    var isConfigured: Bool {
#if canImport(FirebaseAuth)
        FirebaseApp.app() != nil
#else
        false
#endif
    }

    /// Whether "Continue with Google" can complete, as opposed to start.
    ///
    /// Separate from `isConfigured` because the two fail independently: Firebase
    /// can be wired up perfectly while the Google client secret is missing, and
    /// the button would then open a browser, take a teacher through consent, and
    /// fail on the exchange.
    var canSignInWithGoogle: Bool {
        isConfigured
            && OAuthClientDefaults.value(OAuthClientDefaults.googleClientID) != nil
            && OAuthClientDefaults.value(OAuthClientDefaults.googleClientSecret) != nil
    }

    /// Called once at launch, before any view reads `AccountStore`.
    ///
    /// Deliberately does not `fatalError` on a missing plist. A teacher whose
    /// build shipped without one should meet a sentence explaining that account
    /// setup is unfinished, not a crash on launch that looks like a corrupt
    /// download — the same reasoning `OAuthClientDefaults` applies to an empty
    /// client ID.
    func configureIfNeeded() {
#if canImport(FirebaseAuth)
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            logger.error("GoogleService-Info.plist is missing — Anchor accounts are disabled in this build.")
            return
        }
        FirebaseApp.configure()
        logger.info("Firebase configured.")
#else
        logger.error("FirebaseAuth is not linked — Anchor accounts are disabled in this build.")
#endif
    }

    // MARK: - Session

    /// The account Firebase has restored, if any.
    func currentAccount() -> AnchorAccount? {
#if canImport(FirebaseAuth)
        Auth.auth().currentUser.map { Self.account(from: $0) }
#else
        nil
#endif
    }

    /// Fires whenever Firebase restores, creates or drops a session.
    /// Returns an opaque handle the caller keeps alive.
    func observeAuthState(_ onChange: @escaping @MainActor (AnchorAccount?) -> Void) -> Any? {
#if canImport(FirebaseAuth)
        return Auth.auth().addStateDidChangeListener { _, user in
            let account = user.map { Self.account(from: $0) }
            Task { @MainActor in onChange(account) }
        }
#else
        Task { @MainActor in onChange(nil) }
        return nil
#endif
    }

    // MARK: - Email and password

    func signUp(email: String, password: String, displayName: String?) async throws -> AnchorAccount {
#if canImport(FirebaseAuth)
        guard isConfigured else { throw AccountError.notConfigured }
        do {
            let result = try await Auth.auth().createUser(withEmail: email.trimmed, password: password)
            // Set the name in the same call chain rather than leaving it for a
            // later screen: `AnchorAccount.label` falls back to the raw email
            // otherwise, and "Signed in as ms.rivera@..." on the finish screen
            // is the kind of small wrongness a pilot teacher notices first.
            if let displayName, !displayName.trimmed.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = displayName.trimmed
                try? await change.commitChanges()
            }
            return Self.account(from: result.user, fallbackName: displayName)
        } catch {
            throw Self.accountError(from: error)
        }
#else
        throw AccountError.notConfigured
#endif
    }

    func signIn(email: String, password: String) async throws -> AnchorAccount {
#if canImport(FirebaseAuth)
        guard isConfigured else { throw AccountError.notConfigured }
        do {
            let result = try await Auth.auth().signIn(withEmail: email.trimmed, password: password)
            return Self.account(from: result.user)
        } catch {
            throw Self.accountError(from: error)
        }
#else
        throw AccountError.notConfigured
#endif
    }

    func sendPasswordReset(email: String) async throws {
#if canImport(FirebaseAuth)
        guard isConfigured else { throw AccountError.notConfigured }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email.trimmed)
        } catch {
            throw Self.accountError(from: error)
        }
#else
        throw AccountError.notConfigured
#endif
    }

    // MARK: - Google

    /// Runs Anchor's own browser flow for an ID token, then trades it for a
    /// Firebase session. See GoogleIdentitySignIn.swift for why this does not
    /// use Google's SDK.
    func signInWithGoogle() async throws -> AnchorAccount {
#if canImport(FirebaseAuth)
        guard isConfigured else { throw AccountError.notConfigured }

        // Both, before the browser opens. The secret is not optional for a
        // Desktop client — Google's token endpoint answers `client_secret is
        // missing` without it (probed 2026-08-24) — and checking it only at the
        // exchange would put the failure *after* the teacher had approved
        // access, which is the exact defect the Classroom connect gate was just
        // corrected for. Same client, same trap.
        guard let clientID = OAuthClientDefaults.value(OAuthClientDefaults.googleClientID),
              let clientSecret = OAuthClientDefaults.value(OAuthClientDefaults.googleClientSecret) else {
            throw AccountError.notConfigured
        }

        let tokens = try await identityClient.signIn(clientID: clientID, clientSecret: clientSecret)

        let credential = GoogleAuthProvider.credential(
            withIDToken: tokens.idToken,
            accessToken: tokens.accessToken ?? ""
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            // Google supplies a name; carry it over when Firebase's own record
            // has none, so the finish screen can greet them by name.
            if result.user.displayName?.trimmed.isEmpty != false,
               let name = tokens.displayName, !name.trimmed.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try? await change.commitChanges()
            }
            return Self.account(from: result.user, fallbackName: tokens.displayName, provider: .google)
        } catch {
            throw Self.accountError(from: error)
        }
#else
        throw AccountError.notConfigured
#endif
    }

    // MARK: - Sign out

    func signOut() throws {
#if canImport(FirebaseAuth)
        guard isConfigured else { return }
        do {
            try Auth.auth().signOut()
        } catch {
            throw Self.accountError(from: error)
        }
#endif
    }

    // MARK: - Mapping

#if canImport(FirebaseAuth)
    private static func account(
        from user: User,
        fallbackName: String? = nil,
        provider: AccountProvider? = nil
    ) -> AnchorAccount {
        let resolved = provider ?? (
            user.providerData.contains { $0.providerID == "google.com" } ? .google : .password
        )
        let name = user.displayName?.trimmed.isEmpty == false ? user.displayName : fallbackName
        return AnchorAccount(
            uid: user.uid,
            email: user.email,
            displayName: name,
            provider: resolved
        )
    }
#endif

    /// Maps Firebase's NSError codes onto Anchor's own error type.
    ///
    /// Compared as raw integers on purpose. `AuthErrorCode` has changed shape
    /// between Firebase major versions — struct in some, enum in others — so
    /// pattern-matching it ties this file to one version of a dependency the
    /// project has not pinned yet. The numeric codes are public API and have
    /// been stable since Firebase 4.
    private static func accountError(from error: Error) -> AccountError {
        if let accountError = error as? AccountError { return accountError }

        let nsError = error as NSError
        switch nsError.code {
        case 17007: return .emailAlreadyInUse
        case 17008: return .invalidEmail
        case 17026: return .weakPassword
        case 17009, 17004: return .wrongPassword
        case 17011: return .noSuchAccount
        case 17020: return .networkUnavailable
        case 17010: return .tooManyAttempts
        default:
            return .unknown(nsError.localizedDescription)
        }
    }
}
