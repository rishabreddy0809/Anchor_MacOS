//
//  CredentialSeed.swift
//  Anchor
//
//  What one launch's environment asks Anchor to provision.
//
//  ── Why this type exists ────────────────────────────────────────────────────
//
//  Provisioning has no GUI in a shipped build — Settings → Advanced is
//  `#if DEBUG` (ship-checklist §4), so a school's admin sets four environment
//  variables on one Terminal launch and Anchor writes them to the Keychain.
//  See ADMIN-SETUP.md step 3.
//
//  The code that did this read the environment and wrote storage in the same
//  breath, and that conflation caused two defects, both of which only bite on a
//  *partial* run — a secret rotation rather than a first setup, which is to say
//  months after anyone remembers how this works:
//
//    1. **A supplied secret deleted the key beside it.** The Meeting SDK branch
//       fired when *either* variable was present and then wrote both halves,
//       passing `nil` for the one the admin had not mentioned — and `nil` means
//       "delete" to `MeetingSDKCredentialStore.save`. So rotating only
//       `ANCHOR_ZOOM_SDK_SECRET` removed a school's provisioned *key*.
//       `resolved()` then fell back to Anchor's shipped `meetingSDKKey`, pairing
//       the school's secret with Anchor's key. `sdkAuth` rejects that locally,
//       before any network request, and the error's own technical detail reads
//       "No Meeting SDK Key/Secret" — which is false. Both existed. They did not
//       match. That sentence would have sent the reader looking for a missing
//       value that was present the whole time.
//
//    2. **A supplied secret alone did nothing, silently.** The browser sign-in
//       branch was gated on the *client ID* being present, so setting only
//       `ANCHOR_ZOOM_OAUTH_CLIENT_SECRET` wrote nothing and said nothing.
//
//  Both are the same mistake: the old code could not tell **"not mentioned"**
//  from **"set to empty"**. `CredentialIntent` is that distinction, made
//  explicit and given a name, so the rule can be stated once and tested without
//  a Keychain.
//
//  ── Why it is pure ──────────────────────────────────────────────────────────
//
//  The bug was never in the Keychain. It was in the decision about what to write
//  before anything was written, and a decision is testable where a Keychain
//  write is not — the test target touches no real Keychain, and a test that did
//  would either need the developer's login keychain or a signed test host.
//  Keeping the rule in a pure value means `CredentialSeedTests` can enumerate
//  every combination of the four variables, including the two that used to be
//  destructive, and prove the rule rather than the plumbing.
//

import Foundation

/// What the environment says about one stored credential.
///
/// Three states rather than `String?`, because `String?` is exactly the type
/// that lost the distinction: `nil` meant both "the admin didn't mention this"
/// and "the admin wants this gone", and the old code picked the destructive
/// reading.
nonisolated enum CredentialIntent: Equatable {

    /// The variable was absent. **Leave whatever is stored alone.** This is the
    /// case both defects got wrong, and it is the common case on a rotation.
    case leave

    /// The variable was present and empty. Remove the stored value and fall
    /// back to `OAuthClientDefaults`. Kept as a real state so un-provisioning
    /// stays possible — the fix for the defects above must not remove the
    /// ability to deliberately clear a value, or a school that mis-pasted a
    /// secret could never take it back out.
    case clear

    /// The variable carried a value. Store it.
    case set(String)

    /// Reads one variable. Whitespace-only counts as empty, because a value
    /// that survived a copy-paste with a stray newline is not a credential and
    /// storing it would fail later, further from the cause.
    static func read(_ name: String, from environment: [String: String]) -> CredentialIntent {
        guard let raw = environment[name] else { return .leave }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .clear : .set(trimmed)
    }

    /// The value to store, or `nil` to delete — for call sites that already
    /// treat `nil` as "remove". Only meaningful once `.leave` has been handled;
    /// collapsing `.leave` here would reintroduce the defect, so it traps
    /// instead of guessing.
    var storedValue: String? {
        switch self {
        case .leave:
            preconditionFailure("`.leave` must be handled by not writing at all — see CredentialSeed.swift")
        case .clear:
            return nil
        case .set(let value):
            return value
        }
    }

    /// Whether this intent writes anything. The whole fix is that `.leave`
    /// writes nothing.
    var writes: Bool { self != .leave }
}

/// The Server-to-Server triple, which is all-or-nothing rather than three
/// independent values.
///
/// Unlike the pairs above these three authenticate *together*: an account ID
/// with a rotated client secret and a stale client ID is not a partial
/// configuration, it is a broken one. So a run that names some but not all
/// three is refused rather than half-applied — and `isPartial` exists so the
/// refusal can be *reported* instead of being the silent no-op it used to be.
nonisolated struct ServerToServerSeed: Equatable {
    var accountID: String
    var clientID: String
    var clientSecret: String
}

/// One launch's provisioning request.
nonisolated struct CredentialSeed: Equatable {

    var sdkKey: CredentialIntent
    var sdkSecret: CredentialIntent
    var oauthClientID: CredentialIntent
    var oauthClientSecret: CredentialIntent

    /// Present only when all three Server-to-Server variables were supplied.
    var serverToServer: ServerToServerSeed?

    /// True when *some* Server-to-Server variables were named but not all
    /// three. Nothing is written in that case, and the caller is expected to
    /// say so — a rotation that quietly does nothing is how an admin ends a
    /// setup call believing a value landed.
    var serverToServerIsPartial: Bool

    /// Whether this launch asks for anything at all, so an ordinary
    /// double-click does no work and touches no storage.
    var isEmpty: Bool {
        !sdkKey.writes && !sdkSecret.writes
            && !oauthClientID.writes && !oauthClientSecret.writes
            && serverToServer == nil && !serverToServerIsPartial
    }

    static func read(from environment: [String: String]) -> CredentialSeed {
        let names = ["ANCHOR_ZOOM_ACCOUNT_ID", "ANCHOR_ZOOM_CLIENT_ID", "ANCHOR_ZOOM_CLIENT_SECRET"]
        let s2s = names.map { CredentialIntent.read($0, from: environment) }

        // `.set` only: a present-but-empty Server-to-Server variable is a
        // request to clear, which the triple has no coherent partial meaning
        // for, so it counts as "named" and lands in the partial branch.
        let values: [String] = s2s.compactMap {
            if case .set(let value) = $0 { return value }
            return nil
        }
        let named = s2s.filter(\.writes).count

        return CredentialSeed(
            sdkKey: .read("ANCHOR_ZOOM_SDK_KEY", from: environment),
            sdkSecret: .read("ANCHOR_ZOOM_SDK_SECRET", from: environment),
            oauthClientID: .read("ANCHOR_ZOOM_OAUTH_CLIENT_ID", from: environment),
            oauthClientSecret: .read("ANCHOR_ZOOM_OAUTH_CLIENT_SECRET", from: environment),
            serverToServer: values.count == 3
                ? ServerToServerSeed(accountID: values[0], clientID: values[1], clientSecret: values[2])
                : nil,
            serverToServerIsPartial: named > 0 && values.count != 3
        )
    }
}
