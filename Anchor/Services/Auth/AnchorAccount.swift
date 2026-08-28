//
//  AnchorAccount.swift
//  Anchor
//
//  The teacher's Anchor account: who they signed in as, and how.
//
//  This is *identity*, and it is deliberately kept apart from the two
//  integration grants Anchor already holds. Zoom and Google Classroom are
//  connections to a teacher's own accounts elsewhere, minted in the browser and
//  kept in the Keychain (see `ZoomCredentialsStore`, `GoogleCredentialsStore`).
//  An Anchor account is the teacher's login to Anchor itself.
//
//  Keeping them separate matters at the consent screen. `GoogleOAuthConfig`
//  requests four Classroom scopes; signing in with Google to *create an Anchor
//  account* requests `openid email profile` and nothing else, so a teacher
//  meeting Anchor for the first time is not asked to hand over their roster
//  before they have an account. It also means signing out of Anchor does not
//  silently revoke Classroom, and disconnecting Classroom does not sign them
//  out — two grants that fail independently, because they are independent.
//
//  What is stored where: Firebase holds the account record (uid, email,
//  display name) on Google's servers. Nothing about a class, a student, a
//  score or a roster is part of it — those never leave the Mac, which is the
//  claim the privacy policy makes and this file must not quietly break.
//

import Foundation

/// How the teacher proved who they are.
nonisolated enum AccountProvider: String, Codable, Sendable {
    case password
    case google

    var label: String {
        switch self {
        case .password: "Email and password"
        case .google: "Google"
        }
    }
}

/// A signed-in teacher, reduced to the fields Anchor actually shows.
///
/// Intentionally not the Firebase `User` object: that type carries tokens and
/// a live handle to the SDK, and passing it into SwiftUI views would make
/// every screen that greets a teacher by name depend on Firebase being linked.
nonisolated struct AnchorAccount: Codable, Equatable, Sendable {
    /// Firebase's stable identifier for this account.
    var uid: String
    var email: String?
    var displayName: String?
    var provider: AccountProvider

    /// The Google address to hand Google as a `login_hint`, or nil.
    ///
    /// Gated on the provider rather than just returning `email`, because a
    /// password account's email is frequently not a Google address at all —
    /// and hinting at one that Google does not recognise makes its account
    /// picker worse, not better. Only a teacher who actually signed in with
    /// Google has proved which Google identity is theirs.
    var googleEmail: String? {
        guard provider == .google, let email, !email.trimmed.isEmpty else { return nil }
        return email
    }

    /// What to show in Settings and on the finish screen — a name if there is
    /// one, otherwise the email, otherwise something honest rather than blank.
    var label: String {
        if let displayName, !displayName.trimmed.isEmpty { return displayName }
        if let email, !email.trimmed.isEmpty { return email }
        return "Signed in"
    }

    /// The line under the teacher's name in the Settings profile card.
    ///
    /// Static, pure, and taking nothing but an account — and that signature is
    /// the actual guard, not the string it returns.
    ///
    /// Until 2026-08-27 the profile card built this line from
    /// `GoogleCredentialsStore.tokens?.accountEmail ?? ZoomOAuthStore.accountLabel`
    /// — the Classroom grant, falling back to the Zoom one. Both are
    /// *connections*; neither is who the teacher is signed in to Anchor as. The
    /// card was written before Anchor had accounts and nobody revisited it when
    /// they landed, so a teacher signed in as one Google account with Classroom
    /// connected as another saw the other one, directly under their own name,
    /// and reasonably concluded the sign-in had gone to the wrong account.
    ///
    /// No assertion about the returned `String` would have caught that. Being
    /// unable to reach a connection store from in here does.
    static func profileSubtitle(for account: AnchorAccount?) -> String {
        guard let account else { return "Not signed in" }
        let email = account.email?.trimmed ?? ""
        return email.isEmpty ? "Signed in via \(account.provider.label)" : email
    }

    /// The Classroom card's detail line: the connected address, and a plain
    /// word when it is not the one the teacher signed in with.
    ///
    /// Stated rather than flagged as an error. The two grants are deliberately
    /// independent — a teacher may sign in to Anchor personally and teach from
    /// a school Google account — but until now a mismatch was invisible, and an
    /// unexplained address is what caused the confusion above.
    ///
    /// `signedInGoogleEmail` is `googleEmail`, not `email`: a password
    /// account's address is frequently not a Google one, and comparing it
    /// against a Google grant would report a mismatch on every such account.
    static func connectionDetail(connected: String?, signedInGoogleEmail: String?) -> String? {
        guard let connected, !connected.trimmed.isEmpty else { return nil }
        guard let signedIn = signedInGoogleEmail,
              signedIn.trimmed.lowercased() != connected.trimmed.lowercased()
        else { return connected }
        return "\(connected) — not the account you signed in with"
    }

    /// First word of the display name, matching `TeacherProfileStore.firstName`
    /// so a greeting reads the same whichever of the two supplied the name.
    var firstName: String? {
        guard let displayName else { return nil }
        let trimmed = displayName.trimmed
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: .whitespaces).first
    }
}

/// Where the account flow can be.
///
/// `.unknown` is a real state and not a placeholder: Firebase restores a
/// persisted session asynchronously at launch, so for a moment after start-up
/// neither "signed in" nor "signed out" is true. Onboarding must not flash a
/// sign-up screen at a teacher who is already signed in, which is exactly what
/// collapsing this into a `Bool` would cause.
nonisolated enum AccountState: Equatable, Sendable {
    case unknown
    case signedOut
    case signedIn(AnchorAccount)

    var account: AnchorAccount? {
        if case .signedIn(let account) = self { return account }
        return nil
    }

    var isSignedIn: Bool { account != nil }

    /// True only once Firebase has reported, so a view can hold a spinner
    /// rather than guess.
    var isResolved: Bool { self != .unknown }
}

// MARK: - Errors

/// Account failures, phrased for a teacher rather than a console.
///
/// Firebase returns its own `AuthErrorCode` values; `FirebaseAuthService` maps
/// them here so no Firebase type reaches a view, and so the wording stays under
/// this project's control. Same shape as `ClassroomError` and `ZoomError`:
/// a description, a recovery suggestion, and a flag for whoever installed
/// Anchor rather than the teacher using it.
nonisolated enum AccountError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case emailAlreadyInUse
    case invalidEmail
    case weakPassword
    case wrongPassword
    case noSuchAccount
    case networkUnavailable
    case tooManyAttempts
    case cancelled
    case googleSignInFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Anchor's account setup isn't finished on this Mac."
        case .emailAlreadyInUse:
            "There's already an Anchor account with that email."
        case .invalidEmail:
            "That doesn't look like an email address."
        case .weakPassword:
            "That password is too easy to guess."
        case .wrongPassword:
            "That password doesn't match this account."
        case .noSuchAccount:
            "No Anchor account uses that email."
        case .networkUnavailable:
            "Anchor couldn't reach the internet."
        case .tooManyAttempts:
            "Too many attempts. Anchor has paused sign-in for a few minutes."
        case .cancelled:
            "Sign-in didn't finish."
        case .googleSignInFailed(let detail):
            "Google sign-in didn't finish. \(detail)"
        case .unknown(let detail):
            detail
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            "Whoever installed Anchor can finish it in one step — see ADMIN-SETUP.md."
        case .emailAlreadyInUse:
            "Sign in instead, or use a different email."
        case .invalidEmail:
            "Check for a typo and try again."
        case .weakPassword:
            "Use at least 8 characters."
        case .wrongPassword:
            "Try again, or reset your password."
        case .noSuchAccount:
            "Create an account instead, or check the email for a typo."
        case .networkUnavailable:
            "Check your connection and try again."
        case .tooManyAttempts:
            "Wait a few minutes, then try again."
        case .cancelled, .googleSignInFailed, .unknown:
            nil
        }
    }

    /// True when the fix belongs to whoever packaged the build, not the teacher
    /// — the same distinction `ZoomError.isSetupProblem` draws, so `ErrorNotice`
    /// can present it the same way.
    var isSetupProblem: Bool {
        if case .notConfigured = self { return true }
        return false
    }

    /// Cancelling is not worth a red banner — the teacher closed the tab.
    var isCancellation: Bool { self == .cancelled }
}
