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
    /// Zoom requires this on the token endpoint even for a native app, so it is
    /// optional only in the sense that a PKCE-only Zoom app would omit it.
    var clientSecret: String?
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
        ZoomOAuthScope(
            names: ["dashboard_meetings:read:admin", "dashboard:read:list_meeting_participants:admin"],
            purpose: "Read live participants without the bot joining "
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

    @Published private(set) var tokens: ZoomOAuthTokens?
    /// Overrides for the shipped registration; `nil` falls back to
    /// OAuthClientDefaults.
    @Published private(set) var clientIDOverride: String?
    @Published private(set) var clientSecretOverride: String?
    @Published private(set) var lastError: String?

    var isConnected: Bool { tokens != nil }
    var accountLabel: String? { tokens?.accountLabel }

    var clientID: String? {
        clientIDOverride ?? OAuthClientDefaults.value(OAuthClientDefaults.zoomClientID)
    }

    var clientSecret: String? {
        clientSecretOverride ?? OAuthClientDefaults.value(OAuthClientDefaults.zoomClientSecret)
    }

    /// Whether Connect can open a browser at all.
    var hasClientCredentials: Bool { clientID != nil }

    init() {
        load()
    }

    private func load() {
        // `read` returns Data?? through `try?` — flatten before unwrapping.
        if let data = (try? keychain.read(account: Self.tokenAccount)) ?? nil {
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
        guard let clientID else { return nil }
        return ZoomOAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }

    // MARK: Tokens

    /// Persists the whole grant. A failed write is surfaced rather than
    /// swallowed: reporting "Connected" from memory while nothing reached the
    /// Keychain is how a connection silently evaporates at the next launch.
    @discardableResult
    func save(_ newTokens: ZoomOAuthTokens) -> Bool {
        tokens = newTokens
        do {
            try keychain.save(try JSONEncoder().encode(newTokens), account: Self.tokenAccount)
            guard let stored = (try? keychain.read(account: Self.tokenAccount)) ?? nil,
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
        try? keychain.delete(account: Self.tokenAccount)
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
            URLQueryItem(name: "client_id", value: config.clientID),
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
            throw ZoomError.authorizationFailed(
                "Zoom did not return a refresh token, so the connection would expire "
                + "within the hour. Check that the Marketplace app is a General "
                + "(user-managed) app rather than Server-to-Server OAuth."
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
            query.append(URLQueryItem(name: "client_id", value: config.clientID))
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
            body["client_id"] = config.clientID
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
