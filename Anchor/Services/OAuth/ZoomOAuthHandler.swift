//
//  ZoomOAuthHandler.swift
//  Anchor
//
//  Browser sign-in for a teacher's own Zoom account: authorization code + PKCE,
//  with the redirect coming back through `anchor://oauth/zoom`.
//
//  How this differs from ZoomAuthenticator, which is still here:
//
//    ZoomAuthenticator runs Server-to-Server OAuth. It swaps an Account ID and
//    a Client ID/Secret for a token with no human involved, which is right for
//    the in-meeting bot — it signs in as its own robot account — and wrong for
//    a teacher, who would have to be handed admin credentials to type in.
//
//    This file runs the user-managed flow. The teacher clicks Connect, signs in
//    to Zoom in their browser, and Anchor receives a code it exchanges for
//    tokens scoped to *that* teacher. Nothing is typed and no admin credential
//    leaves the school's Zoom account.
//
//  Both produce a bearer token, so both satisfy `ZoomTokenProviding` and
//  ZoomService neither knows nor cares which one it is holding.
//
//  Two Zoom details worth knowing before changing anything here:
//
//    1. Zoom's authorize endpoint takes no `scope` parameter. Scopes are fixed
//       on the Marketplace app, and whatever it is configured for is what the
//       consent screen offers. Anchor therefore *verifies* the granted scopes
//       from the token response rather than requesting them, and says which one
//       to add when a feature is missing.
//    2. Refresh tokens rotate. Every refresh returns a new refresh token and
//       invalidates the one used, so a refresh that isn't persisted immediately
//       locks the teacher out on the next launch. The rotated pair is written
//       to the Keychain before the new access token is handed to anyone — see
//       `ZoomUserTokenProvider.accessToken(forceRefresh:)`.
//

import AppKit
import Combine
import Foundation

// MARK: - Tokens

/// One teacher's Zoom grant.
///
/// Unlike the Google flow — which keeps its access token in memory only — the
/// access token is persisted here too. Zoom rotates refresh tokens on use, so
/// throwing away a perfectly good hour-long access token at every launch would
/// burn a rotation each time the app started, and each rotation is a chance to
/// lose the grant to a crash between "Zoom issued a new one" and "it reached
/// the Keychain".
nonisolated struct ZoomOAuthTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String?
    /// Display label for Settings ("Connected as …"), filled in after the first
    /// successful `/users/me`. Not an identity Anchor trusts for anything.
    var accountLabel: String?

    /// Refreshed early so a request never races the expiry.
    func isValid(at date: Date = Date(), skew: TimeInterval = ZoomConfig.tokenRefreshSkew) -> Bool {
        date.addingTimeInterval(skew) < expiresAt
    }

    var grantedScopes: Set<String> {
        Set((scope ?? "").split(separator: " ").map(String.init))
    }
}

// MARK: - Redirect transport

/// Where a provider sends the browser once the teacher has signed in.
nonisolated enum OAuthRedirectTransport: Sendable, Equatable {
    /// `anchor://oauth/zoom` — macOS hands the URL straight to the app.
    case customScheme(route: String)
    /// `http://127.0.0.1:<port>/oauth/zoom`, served by LoopbackRedirectListener.
    ///
    /// The port is fixed rather than kernel-assigned because Zoom matches its
    /// registered redirect URL exactly, port included. This is what Anchor
    /// ships with: Zoom's General (user-managed) OAuth apps reject custom URI
    /// schemes outright ("Use HTTPS or numeric loopback addresses instead of
    /// custom URI schemes"), so `anchor://` never was a usable option there —
    /// unlike the Meeting SDK / Server-to-Server side, which never touches a
    /// browser at all.
    case loopback(port: UInt16, path: String)

    /// An HTTPS page we host, which forwards `code` and `state` straight on to
    /// the loopback listener — the provider only ever sees the HTTPS URL.
    ///
    /// Zoom needs this. Its Marketplace form happily *stores* an `http://`
    /// numeric-loopback redirect, but its OAuth service never honours one: the
    /// app's effective redirect list stays empty, so every `redirect_uri` —
    /// including the registered one — comes back `Invalid redirect URL`. An
    /// HTTPS redirect on the same account authorises normally. The evidence is
    /// tabulated in ZOOM_INTEGRATION.md §2a; `.loopback` is kept because Google
    /// Classroom still uses it, and Google accepts it.
    ///
    /// The listener is unchanged — still `LoopbackRedirectListener` on
    /// `loopbackPort`. Only the string handed to the provider differs.
    case hostedBounce(url: String, loopbackPort: UInt16)

    /// The exact string to register with the provider.
    ///
    /// For `.loopback`, literal `127.0.0.1` and not `localhost` — Zoom's
    /// redirect-URL validator rejects the hostname explicitly ("Localhost is
    /// not allowed, please use 127.0.0.1 or [::1] instead"), which matches
    /// `LoopbackRedirectListener` binding to the literal loopback address
    /// rather than resolving a name.
    var uri: String {
        switch self {
        case .customScheme(let route):
            URLSchemeHandler.redirectURI(route: route)
        case .loopback(let port, let path):
            "http://127.0.0.1:\(port)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        case .hostedBounce(let url, _):
            url
        }
    }
}

// MARK: - Configuration

nonisolated struct ZoomOAuthConfig: Sendable {
    var clientID: String

    /// Zoom requires this **with `clientID`**, and it is optional only because
    /// `publicClientID` below exists.
    ///
    /// ── The correction of 2026-08-20, in the order it actually happened ─────
    ///
    /// This file carried a PKCE-only branch — `client_id` in the body, no Basic
    /// header — that had never run, because a developer's Keychain always holds
    /// a secret. Probing `zoom.us` with the shipped `zoomClientID` and no
    /// secret returned `400 invalid_client`, byte-identical to sending no
    /// client identification at all and to sending a garbage id. The conclusion
    /// drawn was that Zoom refuses PKCE-only outright. **That was wrong, and
    /// the reason it was wrong is worth keeping.**
    ///
    /// Opening the Marketplace console showed **Use Public Client OAuth** is
    /// enabled on this app, and that enabling it mints a **second, different
    /// identifier** — a *Public Client ID*. Re-probed with that one:
    ///
    ///     public id, PKCE, no secret  → 400 invalid_grant "Invalid authorization code"
    ///     confidential id, same call  → 400 invalid_client
    ///     public id, refresh_token    → 400 invalid_grant "Invalid refresh token"
    ///
    /// `invalid_grant` means Zoom **authenticated the client** and went on to
    /// reject the deliberately bogus code — which is as far as a probe can get
    /// without a real one. So Zoom supports PKCE-only fine; Anchor was
    /// presenting the confidential client's id on the public client's flow.
    /// The branch was right and the identifier was wrong.
    ///
    /// The lesson is narrower than "check the console": **an error message
    /// naming a credential can mean the credential is wrong rather than
    /// missing.** `invalid_client` was read as "this endpoint demands a
    /// secret". It actually meant "this id is not a client that authenticates
    /// this way". Nothing in the response distinguished those, and only the
    /// console did.
    var clientSecret: String?

    /// The same Marketplace app's public-client identifier, redeemable with
    /// PKCE and no secret.
    var publicClientID: String?

    /// The id to present on **both** the authorization request and the token
    /// exchange.
    ///
    /// One accessor rather than two call sites choosing independently, because
    /// the invariant is not obvious and breaking it is silent: an authorization
    /// code is issued *to a client*, so a code obtained under one id and
    /// redeemed under the other fails at the exchange — after the teacher has
    /// already approved Anchor, which is the expensive place to fail.
    ///
    /// Confidential wins when a secret exists so an admin-provisioned install
    /// keeps behaving exactly as it did; the public client is the fallback that
    /// makes an un-provisioned install work at all.
    var effectiveClientID: String? {
        if let clientSecret, !clientSecret.trimmed.isEmpty,
           !clientID.trimmed.isEmpty {
            return clientID
        }
        if let publicClientID, !publicClientID.trimmed.isEmpty {
            return publicClientID
        }
        return nil
    }

    /// The public client id this install is actually allowed to present.
    ///
    /// **The three identifiers are not independent settings.** The confidential
    /// id, its secret and the public id are all issued to *one* Marketplace
    /// registration. Anchor may present the shipped registration or a
    /// deployment-provisioned one, and must never present halves of both.
    ///
    /// The case this exists for is a per-school install where ADMIN-SETUP.md
    /// step 3 landed the client ID and not the secret — a mistyped variable
    /// name, a quoting mistake, one of the two Keychain writes failing. Without
    /// this rule `effectiveClientID` finds no secret, falls through to the
    /// *shipped* public client, and signs the teacher into **Anchor's own**
    /// Marketplace app rather than the school's. A teacher on the school's
    /// account is then an external user of an unpublished app, so Zoom answers
    /// **"You cannot authorize"** — which ADMIN-SETUP.md already records as the
    /// most misleading page in this flow, because a skipped step 3 and a typo'd
    /// redirect URL produce the identical screen and the natural reaction is to
    /// go back and re-check step 1, which is not where the problem is.
    ///
    /// Suppressing the fallback turns that into a Connect button that is off
    /// with a reason — before consent, and on the admin's own machine while
    /// they are still on the setup call.
    ///
    /// **The asymmetry is deliberate: this keys on the provisioned *id*, never
    /// on the secret.** A provisioned secret with no provisioned id is not
    /// incoherent — it completes the *shipped* registration, which is how the
    /// developer's own Mac is configured and how a school could choose to use
    /// Anchor's app rather than register its own. A rule of "either half
    /// overridden" would have broken both.
    ///
    /// Blank counts as absent for the same reason it does everywhere else here:
    /// a value that survived a paste with a trailing newline is not a value,
    /// and treating one as a provisioned id would switch off sign-in on an
    /// install that has provisioned nothing.
    static func offeredPublicClientID(shipped: String?, provisionedClientID: String?) -> String? {
        if let provisionedClientID, !provisionedClientID.trimmed.isEmpty { return nil }
        return shipped
    }

    /// Whether this registration can complete Zoom's token exchange at all.
    ///
    /// Pure and static so the rule can be tested without a Keychain, a
    /// MainActor or a network — the same reason `CredentialSeed` is a value.
    /// Everything is trimmed-empty-checked because a value provisioned with a
    /// stray newline is not a value, and `OAuthClientDefaults.value` already
    /// folds `""` to `nil` on the shipped constants while a Keychain override
    /// does not go through it.
    static func canCompleteTokenExchange(
        clientID: String?,
        clientSecret: String?,
        publicClientID: String?
    ) -> Bool {
        if let publicClientID, !publicClientID.trimmed.isEmpty { return true }
        guard let clientID, !clientID.trimmed.isEmpty else { return false }
        guard let clientSecret, !clientSecret.trimmed.isEmpty else { return false }
        return true
    }

    /// HTTPS rather than loopback, because Zoom will not honour an `http://`
    /// loopback redirect — see `OAuthRedirectTransport.hostedBounce`.
    ///
    /// This requires two things that live outside the app, and sign-in fails
    /// until both are done: `bounceURL` must actually serve the forwarding page
    /// (see `Web/oauth-zoom-bounce.html`), and the same string must be
    /// registered on the Marketplace app as both the OAuth Redirect URL and an
    /// OAuth allow list entry.
    var redirect: OAuthRedirectTransport = .hostedBounce(
        url: ZoomOAuthConfig.bounceURL,
        loopbackPort: ZoomOAuthConfig.loopbackPort
    )

    /// Where the bounce page is hosted. Change this and the Marketplace
    /// registration together — they must match character for character.
    static let bounceURL = "https://anchor-oauth-bounce.vercel.app/oauth/zoom"

    /// Path half of the redirect route, shared by both transports.
    static let redirectRoute = "oauth/zoom"

    /// Fixed rather than kernel-assigned — see `OAuthRedirectTransport.loopback`.
    /// Arbitrary high port picked to avoid common collisions; whatever value
    /// this is, it must match the Marketplace app's registered redirect URL
    /// exactly.
    static let loopbackPort: UInt16 = 51789

    /// The redirect URL to paste into the Marketplace app, shown verbatim in
    /// error messages because an exact-match failure is the single most likely
    /// way this flow breaks in a new deployment.
    static var redirectURIForDisplay: String {
        OAuthRedirectTransport.hostedBounce(url: bounceURL, loopbackPort: loopbackPort).uri
    }

    static let authorizationEndpoint = URL(string: "https://zoom.us/oauth/authorize")!
    static let tokenEndpoint = ZoomConfig.tokenURL
    static let revokeEndpoint = URL(string: "https://zoom.us/oauth/revoke")!

    /// What Anchor reads, and what stops working without it.
    ///
    /// Checked against the grant rather than requested — see the file header.
    /// Each entry lists the classic scope name first and the granular name Zoom
    /// issues to newer apps; either satisfies it, in user-level or admin form.
    static let requiredScopes: [ZoomOAuthScope] = [
        ZoomOAuthScope(
            names: ["user:read", "user:read:user"],
            purpose: "Identify the signed-in teacher",
            isOptional: false
        ),
        ZoomOAuthScope(
            names: ["meeting:read", "meeting:read:list_meetings"],
            purpose: "Find the class that is running now",
            isOptional: false
        ),
        // Optional, and the bot degrades **silently** without it: `MeetingBot`
        // mints the ZAK with `try?` and falls back to an anonymous guest join,
        // because a guest join is a valid outcome for an open meeting and
        // failing there would turn a working join into an error. That is the
        // right call at the join site and the wrong thing to leave unsaid — the
        // assistant then appears in the class as a guest rather than as the
        // teacher, and nothing anywhere says why.
        //
        // `ADMIN-SETUP.md` step 1.4 tells the school admin to add this scope.
        // Until 2026-08-28 nothing verified they had, so missing it produced a
        // connection Anchor called healthy and a bot that quietly joined wrong.
        // Classic name first, granular second — `displayName` shows the last,
        // and the granular one is what the Marketplace picker lists and what
        // `ADMIN-SETUP.md` step 1.4 tells the admin to look for. Both are
        // accepted: the table this replaced recorded the ZAK scope as
        // `user:read:token` while step 1.4 says `user:read:zak`, the two were
        // never reconciled, and a grant carrying either must satisfy this.
        ZoomOAuthScope(
            names: ["user:read:token", "user:read:zak"],
            purpose: "Let the assistant join as you rather than as a guest",
            isOptional: true
        ),
        ZoomOAuthScope(
            names: ["dashboard_meetings:read:admin", "dashboard:read:list_meeting_participants:admin"],
            purpose: "Read live participants without the bot joining "
                + "(needs an account admin on a Business or Education plan)",
            isOptional: true
        ),
        // Also in `ADMIN-SETUP.md` step 1.4, also previously unverified. Feeds
        // the session record after a class ends.
        ZoomOAuthScope(
            names: ["report:read:admin", "report:read:list_meeting_participants:admin"],
            purpose: "Read the participant report after a class ends "
                + "(needs an account admin on a Business or Education plan)",
            isOptional: true
        )
    ]

    /// Required scopes the grant is missing. Optional ones are reported
    /// separately by `degradedScopes` — a teacher who isn't a Zoom admin can
    /// never grant those, and refusing the sign-in over them would leave the
    /// bot path, which needs none of them, unreachable.
    static func missingScopes(in granted: Set<String>) -> [ZoomOAuthScope] {
        requiredScopes.filter { !$0.isOptional && !$0.isSatisfied(by: granted) }
    }

    static func degradedScopes(in granted: Set<String>) -> [ZoomOAuthScope] {
        requiredScopes.filter { $0.isOptional && !$0.isSatisfied(by: granted) }
    }
}

nonisolated struct ZoomOAuthScope: Sendable, Equatable {
    /// Accepted spellings, any one of which satisfies this requirement.
    var names: [String]
    var purpose: String
    var isOptional: Bool

    /// The name to show a teacher — the granular one, which is what the
    /// Marketplace scope picker lists today.
    var displayName: String { names.last ?? "" }

    func isSatisfied(by granted: Set<String>) -> Bool {
        names.contains { name in
            granted.contains(name) || granted.contains("\(name):admin")
        }
    }
}

// MARK: - Credential store

/// Keychain-backed storage for the teacher's Zoom grant and, when a deployment
/// overrides them, the OAuth client credentials.
@MainActor
final class ZoomOAuthStore: ObservableObject {

    static let shared = ZoomOAuthStore()

    private static let service = "com.anchor.zoom.oauth"
    private static let tokenAccount = "user-tokens"
    private static let clientIDAccount = "oauth-client-id"
    private static let clientSecretAccount = "oauth-client-secret"

    private let keychain = KeychainStore(service: ZoomOAuthStore.service)
    private var scopeObserver: Any?

    /// The teacher's own Zoom grant, kept under the signed-in account.
    ///
    /// The client id and secret below are *not* scoped: they are a school's
    /// Marketplace registration, provisioned once per Mac. See `AccountScope`.
    private var scopedTokenAccount: String {
        AccountScope.shared.keychainAccount(Self.tokenAccount)
    }

    @Published private(set) var tokens: ZoomOAuthTokens?
    /// Overrides for the shipped registration; `nil` falls back to
    /// OAuthClientDefaults.
    @Published private(set) var clientIDOverride: String?
    @Published private(set) var clientSecretOverride: String?
    @Published private(set) var lastError: String?

    var isConnected: Bool { tokens != nil }
    var accountLabel: String? { tokens?.accountLabel }

    /// Optional Zoom permissions the grant did not come back with.
    ///
    /// `ZoomOAuthConfig.degradedScopes` existed from the beginning and **had no
    /// callers**, so a school that granted only the two required scopes
    /// connected successfully and was never told the participant path was shut
    /// — the exact guessing `ZoomCapabilities` was written to prevent. Wired up
    /// 2026-08-28.
    var degradedScopes: [ZoomOAuthScope] {
        guard let tokens else { return [] }
        return ZoomOAuthConfig.degradedScopes(in: tokens.grantedScopes)
    }

    /// What a partial grant costs, in Anchor's own terms — one clause per
    /// missing permission, ready for a view to put a sentence around.
    ///
    /// Deliberately **not** the finished sentence.
    /// `TeacherFacingSourceScanTests` refuses prose outside a view that tells a
    /// teacher to do something only a developer or an admin can, and it was
    /// right to catch the first draft of this: "your Zoom admin can add these in
    /// the Marketplace — some need a Business or Education plan" is an
    /// instruction for the person on the setup call, not for the teacher whose
    /// class is about to start. The data belongs here; the wording belongs where
    /// it is read.
    var degradedCapabilities: [String] {
        degradedScopes.map(\.purpose)
    }

    /// Names the missing scopes on stderr, for the admin who is still standing
    /// at the Terminal they ran `ADMIN-SETUP.md` step 3 from.
    ///
    /// This is the other half of the sentence Settings shows. The teacher is
    /// told what stopped working and that it is not their doing; the person who
    /// can actually fix it is told which scope to add, and gets it in the same
    /// window that already prints the provisioning result. Only fixed scope
    /// names cross — never a token, never anything about a class.
    func reportDegradedScopesToOperator() {
        let missing = degradedScopes
        guard !missing.isEmpty else { return }
        AnchorDiag.operatorMessage(
            "Zoom granted a partial scope set. Missing: "
                + missing.map(\.displayName).joined(separator: ", ")
                + ". Add them to the Zoom Marketplace app and reconnect; the "
                + "dashboard and report scopes need a Business or Education plan."
        )
    }

    var clientID: String? {
        clientIDOverride ?? OAuthClientDefaults.value(OAuthClientDefaults.zoomClientID)
    }

    var clientSecret: String? {
        clientSecretOverride ?? OAuthClientDefaults.value(OAuthClientDefaults.zoomClientSecret)
    }

    /// No Keychain override: the public client id is not a per-deployment
    /// value. A school that provisions its own Marketplace app provisions the
    /// confidential pair, so an override here would only ever be a way to get
    /// the two halves out of step.
    ///
    /// It is *withheld* rather than overridden when a deployment has named its
    /// own confidential id, because the shipped public client belongs to
    /// Anchor's registration and not to theirs. The comment this replaces said
    /// `effectiveClientID` "prefers that pair whenever the secret is present",
    /// which is true and was not enough: when the secret is *absent* the
    /// preference does not fire, and the fallback silently substituted Anchor's
    /// app for the school's. See `ZoomOAuthConfig.offeredPublicClientID`.
    var publicClientID: String? {
        ZoomOAuthConfig.offeredPublicClientID(
            shipped: OAuthClientDefaults.value(OAuthClientDefaults.zoomPublicClientID),
            provisionedClientID: clientIDOverride
        )
    }

    /// Whether Connect can open a browser at all.
    ///
    /// **Revised twice on 2026-08-20 and the second revision undoes most of the
    /// first.** It was `clientID != nil`; it became "client ID *and* secret"
    /// after a probe suggested Zoom refused PKCE-only; and it is now "a public
    /// client id, or a confidential id with its secret" — because the probe had
    /// used the wrong identifier and Zoom refuses no such thing.
    ///
    /// The middle version would have disabled Connect Zoom on every
    /// un-provisioned install: honest about a failure that was not real, and
    /// costing exactly the reach the public client exists to provide. It is
    /// recorded rather than quietly reverted because the failure mode it was
    /// built for is real — a button that works until *after* consent — and the
    /// next person to see `invalid_client` should reach for the console before
    /// reaching for this gate.
    var hasClientCredentials: Bool {
        ZoomOAuthConfig.canCompleteTokenExchange(
            clientID: clientID,
            clientSecret: clientSecret,
            publicClientID: publicClientID
        )
    }

    init() {
        load()
        scopeObserver = AccountScope.observe { [weak self] in self?.accountDidChange() }
    }

    /// The Zoom half of the same migration. See
    /// `GoogleCredentialsStore.adoptUnscopedGrant` and `AccountScope`.
    func adoptUnscopedGrant(into scope: AccountScopeIdentity) {
        try? keychain.adopt(
            account: Self.tokenAccount,
            into: scope.keychainAccount(Self.tokenAccount)
        )
    }

    /// Swaps in the incoming teacher's Zoom grant, or none. The outgoing
    /// teacher's stays under their own uid.
    private func accountDidChange() {
        tokens = nil
        lastError = nil
        if let data = (try? keychain.read(account: scopedTokenAccount)) ?? nil {
            tokens = try? JSONDecoder().decode(ZoomOAuthTokens.self, from: data)
        }
    }

    private func load() {
        // `read` returns Data?? through `try?` — flatten before unwrapping.
        if let data = (try? keychain.read(account: scopedTokenAccount)) ?? nil {
            tokens = try? JSONDecoder().decode(ZoomOAuthTokens.self, from: data)
        }
        if let data = (try? keychain.read(account: Self.clientIDAccount)) ?? nil {
            clientIDOverride = OAuthClientDefaults.value(String(decoding: data, as: UTF8.self))
        }
        if let data = (try? keychain.read(account: Self.clientSecretAccount)) ?? nil {
            clientSecretOverride = OAuthClientDefaults.value(String(decoding: data, as: UTF8.self))
        }
    }

    func config() -> ZoomOAuthConfig? {
        // `clientID` may legitimately be absent on a public-client-only
        // deployment, so the guard is on there being *some* usable id rather
        // than on the confidential one specifically.
        let config = ZoomOAuthConfig(
            clientID: clientID ?? "",
            clientSecret: clientSecret,
            publicClientID: publicClientID
        )
        guard config.effectiveClientID != nil else { return nil }
        return config
    }

    // MARK: Tokens

    /// Persists the whole grant. A failed write is surfaced rather than
    /// swallowed: reporting "Connected" from memory while nothing reached the
    /// Keychain is how a connection silently evaporates at the next launch.
    @discardableResult
    func save(_ newTokens: ZoomOAuthTokens) -> Bool {
        tokens = newTokens
        do {
            try keychain.save(try JSONEncoder().encode(newTokens), account: scopedTokenAccount)
            guard let stored = (try? keychain.read(account: scopedTokenAccount)) ?? nil,
                  !stored.isEmpty else {
                lastError = "Signed in to Zoom, but the credential could not be saved to the "
                    + "Keychain — you'll have to reconnect next time Anchor launches."
                return false
            }
            lastError = nil
            return true
        } catch {
            lastError = "Signed in to Zoom, but the credential could not be saved to the "
                + "Keychain (\(error.localizedDescription)). You'll have to reconnect "
                + "next time Anchor launches."
            return false
        }
    }

    /// Records the account name Zoom reported, so Settings can name the
    /// connection without another round trip.
    func setAccountLabel(_ label: String?) {
        guard var current = tokens, current.accountLabel != label else { return }
        current.accountLabel = label
        save(current)
    }

    func disconnect() {
        tokens = nil
        lastError = nil
        try? keychain.delete(account: scopedTokenAccount)
    }

    // MARK: Client overrides

    /// Stores a deployment's own Zoom OAuth app in place of the shipped one.
    /// An empty value clears the override and falls back to OAuthClientDefaults.
    func saveClientOverride(id: String, secret: String?) {
        do {
            if let id = OAuthClientDefaults.value(id) {
                try keychain.save(Data(id.utf8), account: Self.clientIDAccount)
                clientIDOverride = id
            } else {
                try keychain.delete(account: Self.clientIDAccount)
                clientIDOverride = nil
            }

            if let secret = OAuthClientDefaults.value(secret ?? "") {
                try keychain.save(Data(secret.utf8), account: Self.clientSecretAccount)
                clientSecretOverride = secret
            } else {
                try keychain.delete(account: Self.clientSecretAccount)
                clientSecretOverride = nil
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Applies only the halves the caller actually asked about.
    ///
    /// The environment-seeding counterpart to `saveClientOverride` above, and
    /// the reason it exists: that method takes a non-optional `id`, so the old
    /// seeding code had to gate the whole block on the client ID being present.
    /// Setting only `ANCHOR_ZOOM_OAUTH_CLIENT_SECRET` therefore wrote nothing
    /// and said nothing — a rotation that looked like it worked. And supplying
    /// only the ID passed `secret: nil`, which cleared a provisioned secret.
    /// `.leave` fixes both by writing neither. See CredentialSeed.swift.
    func applyClientOverride(id: CredentialIntent, secret: CredentialIntent) {
        do {
            if id.writes {
                if let value = id.storedValue.flatMap(OAuthClientDefaults.value) {
                    try keychain.save(Data(value.utf8), account: Self.clientIDAccount)
                    clientIDOverride = value
                } else {
                    try keychain.delete(account: Self.clientIDAccount)
                    clientIDOverride = nil
                }
            }
            if secret.writes {
                if let value = secret.storedValue.flatMap(OAuthClientDefaults.value) {
                    try keychain.save(Data(value.utf8), account: Self.clientSecretAccount)
                    clientSecretOverride = value
                } else {
                    try keychain.delete(account: Self.clientSecretAccount)
                    clientSecretOverride = nil
                }
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Snapshot for the token provider, which runs off the main actor.
    func snapshot() -> ZoomOAuthTokens? { tokens }
}

// MARK: - OAuth client

/// Runs the browser sign-in and the token endpoints. Holds no state: the tokens
/// it returns belong to `ZoomOAuthStore`.
actor ZoomOAuthClient {

    private let session: URLSession

    init(session: URLSession = .zoomDefault) {
        self.session = session
    }

    // MARK: Authorization

    /// Opens Zoom's sign-in page and waits for the redirect to come back.
    func authorize(config: ZoomOAuthConfig) async throws -> ZoomOAuthTokens {
        let verifier = PKCE.makeCodeVerifier()
        let state = PKCE.makeState()
        let redirectURI = config.redirect.uri

        // Registered *before* the browser opens: a fast sign-in can redirect
        // before this line would otherwise have run, and a redirect with
        // nothing waiting for it is dropped.
        let listener = try makeListener(for: config.redirect)

        var components = URLComponents(
            url: ZoomOAuthConfig.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.effectiveClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.makeCodeChallenge(from: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authorizationURL = components.url else {
            throw ZoomError.authorizationFailed("Could not build the Zoom sign-in URL.")
        }

        async let redirect = listener.wait(state)
        await MainActor.run { NSWorkspace.shared.open(authorizationURL) }

        let result: OAuthRedirect
        do {
            result = try await redirect
        } catch {
            throw Self.zoomError(from: error)
        }

        if result.error != nil {
            throw result.isUserDenial
                ? ZoomError.authorizationCancelled
                : ZoomError.authorizationFailed(result.failureMessage ?? "Zoom refused the sign-in.")
        }
        guard let code = result.code else {
            throw ZoomError.authorizationFailed("Zoom did not return an authorization code.")
        }

        let tokens = try await exchange(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI,
            config: config
        )

        let missing = ZoomOAuthConfig.missingScopes(in: tokens.grantedScopes)
        guard missing.isEmpty else {
            // Nothing Anchor can do with this grant, and the fix is in the
            // Marketplace app rather than anything the teacher can retry.
            throw ZoomError.insufficientScope(missing.map(\.displayName).joined(separator: ", "))
        }

        return tokens
    }

    /// The two redirect transports behind one `wait`.
    private func makeListener(for transport: OAuthRedirectTransport) throws -> RedirectWaiter {
        switch transport {
        case .customScheme(let route):
            return RedirectWaiter { state in
                try await URLSchemeHandler.shared.waitForRedirect(route: route, state: state)
            }
        case .loopback(let port, _):
            let listener = try LoopbackRedirectListener(preferredPort: port)
            return RedirectWaiter { state in
                try await listener.waitForRedirect(expectedState: state)
            }
        case .hostedBounce(_, let port):
            // Identical to `.loopback`: the bounce page hands the query string
            // back to this very listener. Only the registered URL differs.
            let listener = try LoopbackRedirectListener(preferredPort: port)
            return RedirectWaiter { state in
                try await listener.waitForRedirect(expectedState: state)
            }
        }
    }

    /// Erases which transport is in play, and keeps the listener alive for the
    /// duration of the wait.
    private struct RedirectWaiter: Sendable {
        let wait: @Sendable (String) async throws -> OAuthRedirect
    }

    // MARK: Token endpoints

    private func exchange(
        code: String,
        verifier: String,
        redirectURI: String,
        config: ZoomOAuthConfig
    ) async throws -> ZoomOAuthTokens {
        let response: TokenResponse = try await post(
            form: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "code_verifier": verifier
            ],
            config: config
        )

        guard let refreshToken = response.refresh_token else {
            // `authorizationFailed` renders its payload straight into
            // `errorDescription` ("Zoom sign-in failed: …"), so this string is
            // read by the teacher. The registration hint it used to carry —
            // check the app is General (user-managed) rather than
            // Server-to-Server — is correct and is addressed to whoever created
            // the Marketplace app, which is never the teacher.
            //
            // It goes to stderr instead, where the admin doing the setup call is
            // still looking. Same split as the Meeting SDK auth failure, and the
            // same reason: one sentence was serving two readers.
            AnchorDiag.operatorMessage(
                "Zoom returned no refresh token. This normally means the Marketplace app "
                    + "is a Server-to-Server OAuth app rather than a General (user-managed) "
                    + "one — only the latter can issue a refresh token to a signed-in user."
            )
            throw ZoomError.authorizationFailed(
                "Zoom didn't give Anchor a lasting connection, so it would have "
                + "stopped working within the hour. Whoever set Anchor up for your "
                + "school can put this right."
            )
        }

        return ZoomOAuthTokens(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600),
            scope: response.scope,
            accountLabel: nil
        )
    }

    /// Trades the refresh token for a fresh pair.
    ///
    /// Zoom rotates: the returned refresh token replaces the one passed in, and
    /// the old one stops working immediately. The caller must persist the result
    /// before using the access token for anything.
    func refresh(tokens: ZoomOAuthTokens, config: ZoomOAuthConfig) async throws -> ZoomOAuthTokens {
        do {
            let response: TokenResponse = try await post(
                form: [
                    "grant_type": "refresh_token",
                    "refresh_token": tokens.refreshToken
                ],
                config: config
            )
            guard let refreshToken = response.refresh_token else {
                throw ZoomError.authorizationExpired
            }
            return ZoomOAuthTokens(
                accessToken: response.access_token,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600),
                // Zoom omits `scope` on a refresh; the grant hasn't changed, so
                // carry the one from sign-in rather than blanking it and
                // reporting every optional feature as missing.
                scope: response.scope ?? tokens.scope,
                accountLabel: tokens.accountLabel
            )
        } catch let error as ZoomError {
            // A revoked, rotated-past or expired refresh token is terminal —
            // the teacher has to sign in again, and retrying burns quota.
            if case .invalidCredentials = error { throw ZoomError.authorizationExpired }
            if case .server(let status, _, _) = error, status == 400 || status == 401 {
                throw ZoomError.authorizationExpired
            }
            throw error
        }
    }

    /// Best-effort revocation, so disconnecting in Anchor also drops Anchor from
    /// the teacher's Zoom account rather than only forgetting the token locally.
    func revoke(tokens: ZoomOAuthTokens, config: ZoomOAuthConfig) async {
        var components = URLComponents(url: ZoomOAuthConfig.revokeEndpoint, resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "token", value: tokens.accessToken)]
        if config.clientSecret == nil {
            query.append(URLQueryItem(name: "client_id", value: config.effectiveClientID))
        }
        components.queryItems = query
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ZoomConfig.requestTimeout
        if let basic = Self.basicAuthorization(config: config) {
            request.setValue(basic, forHTTPHeaderField: "Authorization")
        }
        _ = try? await session.data(for: request)
    }

    // MARK: Plumbing

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: TimeInterval?
        var scope: String?
    }

    /// zoom.us/oauth/* reports failures as {"reason": …, "error": …} rather than
    /// the {code, message} shape the v2 API uses.
    private struct OAuthErrorBody: Decodable {
        var reason: String?
        var error: String?
        var error_description: String?

        var message: String? { error_description ?? reason ?? error }
    }

    private func post<T: Decodable>(form: [String: String], config: ZoomOAuthConfig) async throws -> T {
        var request = URLRequest(url: ZoomOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = ZoomConfig.requestTimeout

        // HTTP Basic when a secret exists, which is what Zoom's token endpoint
        // expects; `client_id` in the body otherwise, for a PKCE-only
        // registration. PKCE is what actually proves this request is Anchor's
        // either way — see PKCE.swift.
        var body = form
        if let basic = Self.basicAuthorization(config: config) {
            request.setValue(basic, forHTTPHeaderField: "Authorization")
        } else {
            body["client_id"] = config.effectiveClientID
        }
        request.httpBody = Self.encode(form: body).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw ZoomError.cancelled }
            throw ZoomError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ZoomError.decoding("Token response was not HTTP")
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ZoomError.decoding("Could not read Zoom's token response")
            }
        case 400, 401:
            let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            throw ZoomError.invalidCredentials(reason: body?.message)
        case 429:
            throw ZoomError.rateLimited(retryAfter: http.retryAfterSeconds)
        default:
            let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            throw ZoomError.server(status: http.statusCode, code: nil, message: body?.message)
        }
    }

    /// The `Authorization` header value, or nil for a registration with no
    /// secret to authenticate with.
    private static func basicAuthorization(config: ZoomOAuthConfig) -> String? {
        guard let secret = config.clientSecret, !secret.isEmpty else { return nil }
        return "Basic " + Data("\(config.clientID):\(secret)".utf8).base64EncodedString()
    }

    private static func encode(form: [String: String]) -> String {
        form.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            return "\(key)=\(encoded)"
        }
        .joined(separator: "&")
    }

    /// Turns a redirect-transport failure into the error type Zoom's UI reports.
    static func zoomError(from error: Error) -> ZoomError {
        switch error {
        case let error as ZoomError:
            return error
        case OAuthRedirectError.cancelled:
            return .authorizationCancelled
        case let error as OAuthRedirectError:
            return .authorizationFailed(error.localizedDescription)
        default:
            return .authorizationFailed(error.localizedDescription)
        }
    }
}

// MARK: - Token provider

/// Supplies bearer tokens from the teacher's browser sign-in, refreshing when
/// they expire. Interchangeable with `ZoomAuthenticator` from ZoomService's
/// point of view.
actor ZoomUserTokenProvider: ZoomTokenProviding {

    static let shared = ZoomUserTokenProvider()

    private let client: ZoomOAuthClient
    private var refreshTask: Task<ZoomOAuthTokens, Error>?

    init(client: ZoomOAuthClient = ZoomOAuthClient()) {
        self.client = client
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = await MainActor.run(body: { ZoomOAuthStore.shared.snapshot() }) else {
            throw ZoomError.notSignedIn  // never connected
        }
        if !forceRefresh, current.isValid() {
            return current.accessToken
        }

        // Collapse simultaneous callers onto one refresh. Doubly important here:
        // Zoom rotates refresh tokens, so two refreshes in flight would race,
        // and the loser would persist a token Zoom has already invalidated.
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }

        let task = Task<ZoomOAuthTokens, Error> { [client] in
            guard let config = await MainActor.run(body: { ZoomOAuthStore.shared.config() }) else {
                throw ZoomError.missingOAuthClient
            }
            let refreshed = try await client.refresh(tokens: current, config: config)
            // Persisted *before* anyone gets to use it: the token that just
            // rotated is already dead at Zoom.
            let saved = await MainActor.run { ZoomOAuthStore.shared.save(refreshed) }
            guard saved else { throw ZoomError.keychainUnavailable }
            return refreshed
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            return try await task.value.accessToken
        } catch let error as ZoomError {
            // An expired grant is not something the next request can recover
            // from — drop it so the UI stops claiming a connection.
            if case .authorizationExpired = error {
                await MainActor.run { ZoomOAuthStore.shared.disconnect() }
            }
            throw error
        }
    }

    /// After a 401. There is nothing cached here to clear — the store holds the
    /// tokens — so this expires the stored one in place. The refresh token is
    /// untouched, so the next request re-mints rather than resending what Zoom
    /// just refused.
    ///
    /// Awaited rather than fired into a Task: ZoomService calls this and then
    /// immediately retries the request once, and a retry that raced the write
    /// would resend the dead token and burn the one retry it has.
    func invalidate() async {
        refreshTask?.cancel()
        refreshTask = nil
        await MainActor.run {
            guard var tokens = ZoomOAuthStore.shared.snapshot() else { return }
            tokens.expiresAt = .distantPast
            ZoomOAuthStore.shared.save(tokens)
        }
    }

    func grantedScopes() async -> Set<String> {
        await MainActor.run { ZoomOAuthStore.shared.snapshot()?.grantedScopes ?? [] }
    }

    // MARK: Sign-in / sign-out

    /// Runs the browser flow and stores the result.
    func connect() async throws -> ZoomOAuthTokens {
        guard let config = await MainActor.run(body: { ZoomOAuthStore.shared.config() }) else {
            throw ZoomError.missingOAuthClient
        }
        let tokens = try await client.authorize(config: config)
        let saved = await MainActor.run { ZoomOAuthStore.shared.save(tokens) }
        guard saved else { throw ZoomError.keychainUnavailable }
        return tokens
    }

    /// Revokes at Zoom where possible, then forgets the grant locally either
    /// way — a teacher who clicks Disconnect must not be left connected because
    /// the network was down.
    /// Drops in-flight work without touching the grant.
    ///
    /// The account-switch counterpart to `disconnect()`, and the distinction is
    /// the whole point: `disconnect()` revokes the token with Zoom and deletes
    /// it, which is right when a teacher says "disconnect" and catastrophic
    /// when they merely sign out. The outgoing teacher's grant is theirs and
    /// stays in the Keychain under their own uid, so signing back in finds Zoom
    /// still connected.
    ///
    /// Only the refresh task needs clearing — tokens themselves are read
    /// through `ZoomOAuthStore`, which is already per-account.
    func forgetCachedTokens() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func disconnect() async {
        refreshTask?.cancel()
        refreshTask = nil

        let snapshot = await MainActor.run { ZoomOAuthStore.shared.snapshot() }
        let config = await MainActor.run { ZoomOAuthStore.shared.config() }
        if let snapshot, let config {
            await client.revoke(tokens: snapshot, config: config)
        }
        await MainActor.run { ZoomOAuthStore.shared.disconnect() }
    }
}
