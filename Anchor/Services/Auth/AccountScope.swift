//
//  AccountScope.swift
//  Anchor
//
//  Which teacher's data every store is looking at.
//
//  Firebase was wired up correctly and was never the bug. Two Google accounts
//  produce two distinct uids and two distinct sessions — but *nothing below the
//  sign-in screen knew that*. `anchor.onboarding.completed` lived in
//  `UserDefaults.standard`, the archive lived at one fixed path, and the
//  Classroom refresh token lived under one fixed Keychain account. So signing
//  in as somebody else swapped the name in the corner and left the previous
//  teacher's classes, rosters, session history and Google grant exactly where
//  they were — and skipped onboarding, because the flag said it was done.
//
//  This type is the missing half. It answers three questions for one account:
//
//    * `defaults`          — which UserDefaults suite
//    * `directoryURL`      — which Application Support directory
//    * `keychainAccount(_)` — which Keychain account name
//
//  and posts `didChange` when the answers change, which every per-teacher store
//  listens for and reloads on. Nothing is deleted on a switch: sign back in as
//  the first account and that account's Anchor is exactly where it was left.
//
//  ── What is deliberately NOT scoped ─────────────────────────────────────────
//
//  Deployment configuration, because it belongs to the *Mac*, not the teacher:
//  the Zoom Server-to-Server and bot credentials, the Meeting SDK key/secret,
//  and the Google/Zoom OAuth *client* overrides a school enters once in
//  Settings → Advanced (see ADMIN-SETUP.md). Scoping those would mean the
//  second teacher to sign in on a school Mac finds the app unprovisioned.
//
//  Only the per-teacher grants move: the Google Classroom refresh token and the
//  Zoom user token. Those name a person.
//

import Combine
import Foundation
import os

// MARK: - Identity

/// An immutable description of where one account's data lives.
///
/// Split out from the store below so it can be constructed for an arbitrary uid
/// — which is what the adoption migration needs, and what makes any of this
/// testable without a Firebase session.
nonisolated struct AccountScopeIdentity: Sendable, Equatable {

    /// The Firebase uid, or `nil` for the unscoped domain Anchor used before
    /// accounts existed and still uses in a build where they cannot work.
    let uid: String?

    /// The unscoped domain. Also what a signed-out app reads, which is harmless
    /// because a signed-out app shows `SignedOutGate` and nothing else.
    static let unscoped = AccountScopeIdentity(uid: nil)

    /// `nil` means `UserDefaults.standard`.
    var suiteName: String? {
        uid.map { "com.anchor.account.\($0)" }
    }

    var defaults: UserDefaults {
        guard let suiteName, let suite = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return suite
    }

    /// `~/Library/Application Support/Anchor`, or `…/Anchor/Accounts/<uid>`.
    var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let anchor = base.appendingPathComponent("Anchor", isDirectory: true)
        guard let uid else { return anchor }
        return anchor
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(uid, isDirectory: true)
    }

    /// The Keychain account name a per-teacher credential is stored under.
    ///
    /// `#` rather than `.` on purpose: every existing account name in this
    /// project is dotted (`oauth-tokens`, `user-tokens`), and a separator that
    /// cannot appear in either half means a scoped name can never collide with
    /// some future unscoped one.
    func keychainAccount(_ base: String) -> String {
        guard let uid else { return base }
        return "\(base)#\(uid)"
    }
}

// MARK: - Store

@MainActor
final class AccountScope: ObservableObject {

    static let shared = AccountScope()

    /// Posted *after* `identity` has changed, synchronously on the main actor.
    ///
    /// Synchronous matters: `AccountStore` activates the new scope before it
    /// publishes the new `state`, so by the time a view re-renders for a
    /// sign-in every store behind it is already showing the right teacher. A
    /// hop would put one frame of the previous teacher's classes on screen.
    static let didChange = Notification.Name("anchor.accountScope.didChange")

    @Published private(set) var identity: AccountScopeIdentity = .unscoped

    /// Which uid, if any, inherited the data that predates account scoping.
    /// Written to the *unscoped* domain, because that is the thing it describes.
    private static let adoptedByKey = "anchor.account.scope.adoptedBy"

    private let logger = Logger(subsystem: "com.anchor.account", category: "Scope")

    private init() {}

    var uid: String? { identity.uid }
    var defaults: UserDefaults { identity.defaults }
    var directoryURL: URL { identity.directoryURL }
    func keychainAccount(_ base: String) -> String { identity.keychainAccount(base) }

    // MARK: - Switching

    /// Points every store at `uid`'s data. `nil` on sign-out.
    ///
    /// Idempotent: the Firebase state listener fires on token refreshes as well
    /// as real sign-ins, and reloading every store an hour into a class because
    /// a token rotated would be its own bug.
    func activate(uid: String?) {
        let next = AccountScopeIdentity(uid: uid)
        guard next != identity else { return }

        if let uid { adoptUnscopedDataIfNeeded(into: uid) }

        identity = next
        logger.info("Account scope switched to \(uid ?? "none", privacy: .public).")
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Registers `onChange` for every subsequent account switch.
    ///
    /// The returned token has to be held — `NotificationCenter` stops calling a
    /// block observer once its token is released, and every caller here is a
    /// singleton that lives as long as the app, so a stored property is enough.
    static func observe(_ onChange: @escaping @MainActor () -> Void) -> Any {
        // `queue: nil` delivers synchronously on the posting thread, which is
        // always the main actor — see the note on `didChange`.
        NotificationCenter.default.addObserver(forName: didChange, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    // MARK: - Adoption

    /// Hands the data that predates account scoping to the first account that
    /// signs in on this Mac.
    ///
    /// Without this, shipping account scoping would look to every existing
    /// teacher exactly like the bug it fixes: they sign in with the account
    /// they have always used and find an empty app asking them to onboard. So
    /// the first uid to arrive inherits the unscoped domain, once, and every
    /// account after it starts clean — which is the behaviour that was wanted
    /// in the first place.
    ///
    /// Everything here is copy-verify-remove rather than move: a half-finished
    /// migration that leaves the original in place is recoverable, and one that
    /// deletes first is not.
    private func adoptUnscopedDataIfNeeded(into uid: String) {
        let standard = UserDefaults.standard
        guard standard.string(forKey: Self.adoptedByKey) == nil else { return }

        // Claimed before the work, not after. A crash mid-adoption must not
        // hand a second teacher's account the first teacher's data on the next
        // launch; losing a partial migration is the cheaper of the two.
        standard.set(uid, forKey: Self.adoptedByKey)

        let scope = AccountScopeIdentity(uid: uid)
        Self.adoptPreferences(from: standard, to: scope.defaults, logger: logger)
        adoptArchiveFiles(into: scope)
        adoptGrants(into: scope)

        logger.info("Adopted pre-account data into \(uid, privacy: .public).")
    }

    /// Every `anchor.`-prefixed preference, by prefix rather than by a list.
    ///
    /// A hand-maintained list of the eight keys this app persists is a list
    /// that goes stale the first time someone adds a ninth, and the failure is
    /// silent — one setting quietly resets for the existing teacher. The prefix
    /// is the same convention every key in the project already follows.
    /// Takes `source` and `destination` rather than a uid so a test can hand it
    /// two throwaway suites. Every other shape of this method needs a real
    /// signed-in account and writes to `UserDefaults.standard` to prove
    /// anything, which is not a thing a test suite should do to the Mac it is
    /// running on.
    static func adoptPreferences(
        from source: UserDefaults,
        to destination: UserDefaults,
        logger: Logger? = nil
    ) {
        guard source != destination else { return }

        for (key, value) in source.dictionaryRepresentation() {
            guard key.hasPrefix("anchor."), key != adoptedByKey else { continue }
            // Never overwrite: a scope that already holds a value has been used.
            guard destination.object(forKey: key) == nil else { continue }

            destination.set(value, forKey: key)
            // Read back before dropping the original, for the same reason
            // `GoogleCredentialsStore.save` does — a write that reports success
            // and stores nothing is the failure this ordering exists to catch.
            guard destination.object(forKey: key) != nil else {
                logger?.error("Could not adopt preference \(key, privacy: .public); leaving it in place.")
                continue
            }
            source.removeObject(forKey: key)
        }
    }

    /// The session archive and any sidecars beside it.
    private func adoptArchiveFiles(into scope: AccountScopeIdentity) {
        let manager = FileManager.default
        let source = AccountScopeIdentity.unscoped.directoryURL
        let destination = scope.directoryURL

        guard let entries = try? manager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) else { return }

        let adoptable = entries.filter { Self.isAdoptableArchiveFile($0.lastPathComponent) }
        guard !adoptable.isEmpty else { return }

        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create account directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        for url in adoptable {
            let target = destination.appendingPathComponent(url.lastPathComponent)
            guard !manager.fileExists(atPath: target.path) else { continue }
            do {
                try manager.moveItem(at: url, to: target)
            } catch {
                logger.error("Could not adopt \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Whether a file in the old shared directory is one this migration should
    /// move into an account.
    ///
    /// Narrow on purpose, and for the same reason as
    /// `SessionArchive.isPrunableSidecar`: the caller calls
    /// `FileManager.moveItem`, and Application Support holds other people's
    /// data. `Accounts` — the directory this migration writes *into* — is the
    /// one name in here that must never match, or a second run would try to
    /// move the destination inside itself.
    nonisolated static func isAdoptableArchiveFile(_ name: String) -> Bool {
        name.hasPrefix("session-archive")
    }

    /// The two credentials that name a teacher rather than a deployment.
    ///
    /// Each store moves its own, rather than this file reaching into the
    /// Keychain with a table of service names. Two reasons, and the second is
    /// enforced: a store already knows which of its accounts is a grant and
    /// which is configuration, and `PrivacyDisclosureTests` counts
    /// `KeychainStore` construction sites one-to-one against declared service
    /// identifiers so that an undisclosed credential store cannot slip in — a
    /// table here would have to build its own stores and break that count.
    private func adoptGrants(into scope: AccountScopeIdentity) {
        GoogleCredentialsStore.shared.adoptUnscopedGrant(into: scope)
        ZoomOAuthStore.shared.adoptUnscopedGrant(into: scope)
    }
}
