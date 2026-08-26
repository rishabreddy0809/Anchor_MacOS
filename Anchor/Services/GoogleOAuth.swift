//
//  GoogleOAuth.swift
//  Anchor
//
//  OAuth 2.0 for an installed macOS app: authorization code + PKCE, with the
//  redirect landing on a loopback listener.
//
//  Why this flow rather than a client secret:
//
//    A desktop app cannot keep a secret — anything shipped in the bundle is
//    readable. Google's guidance for installed apps is therefore PKCE over a
//    loopback redirect, where the proof-of-possession is a per-request verifier
//    that never leaves this process. Google still issues a "client secret" for
//    desktop clients; it is not treated as confidential and is optional here.
//
//  What is stored: the refresh token, in the Keychain, and nothing else. Access
//  tokens live in memory for their ~1 hour and are never written to disk.
//
//  Which OAuth client is used: the one this build ships with (see
//  OAuthClientDefaults), unless a school overrode it in Settings → Google
//  Classroom → Advanced. A teacher connects by clicking Connect and signing in;
//  they never see or type a client ID. When neither is set the connect button
//  reports `.missingClientID` rather than opening a browser — that is a build
//  configuration problem, and OAuthClientDefaults says how to fix it.
//

import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import os

// MARK: - Tokens

/// The credential set for one connected Google account.
///
/// Codable so the refresh token can go to the Keychain. The access token is
/// deliberately excluded from that write — see `keychainPayload`.
nonisolated struct GoogleTokens: Codable, Equatable, Sendable {
    var accessToken: String?
    var refreshToken: String
    var expiresAt: Date?
    var scope: String?
    var accountEmail: String?

    /// Refreshed a minute early so a request never races the expiry.
    var isExpired: Bool {
        guard let expiresAt else { return true }
        return Date() >= expiresAt.addingTimeInterval(-60)
    }

    /// Scopes Google actually granted, which can be a strict subset of those
    /// requested — it reduces silently rather than failing.
    var grantedScopes: Set<String> {
        Set((scope ?? "").split(separator: " ").map(String.init))
    }

    /// Classroom scopes that were asked for but not granted.
    var missingClassroomScopes: [String] {
        let granted = grantedScopes
        return GoogleOAuthConfig.classroomScopes.filter { !granted.contains($0) }
    }

    /// Classroom scopes Google did grant. Counted separately from the identity
    /// scopes (`openid`, `userinfo.email`, and anything Google adds of its own
    /// accord) — mixing them produced the nonsense "granted 6 of 6 permissions,
    /// missing: …" that this pair of properties exists to make impossible.
    var grantedClassroomScopes: [String] {
        let granted = grantedScopes
        return GoogleOAuthConfig.classroomScopes.filter { granted.contains($0) }
    }

    /// True when the grant covers reading a course list and its roster — enough
    /// for Anchor to show a teacher their classes, with or without coursework.
    var canReadCourses: Bool {
        let granted = grantedScopes
        return granted.contains("https://www.googleapis.com/auth/classroom.courses.readonly")
    }

    /// What actually gets persisted: the long-lived refresh token and the
    /// account label, never the bearer token.
    var keychainPayload: GoogleTokens {
        GoogleTokens(
            accessToken: nil,
            refreshToken: refreshToken,
            expiresAt: nil,
            scope: scope,
            accountEmail: accountEmail
        )
    }
}

// MARK: - Configuration

nonisolated struct GoogleOAuthConfig: Sendable {
    var clientID: String
    /// Optional for desktop clients; sent only when Google issued one.
    var clientSecret: String?

    /// The Classroom permissions Anchor cannot work without.
    ///
    /// Anchor itself never writes to a teacher's Classroom — every call this app
    /// makes is a GET. `classroom.coursework.students` (rather than the
    /// `.readonly` variant) is used here anyway because the Cloud console
    /// project backing this OAuth client does not expose a read-only coursework
    /// scope in its Data Access configuration — only the broader read/write one
    /// is offered there. The extra write permission is simply unused.
    ///
    /// Google presents these as individual tick boxes on the consent screen and
    /// grants only what the teacher ticks, so these are checked after sign-in
    /// rather than assumed. See `GoogleTokens.missingClassroomScopes`.
    /// `classroom.profile.emails` was removed on 2026-08-17. It was the only
    /// *sensitive* scope Anchor requested and the only thing standing between
    /// this app and publishing to Production without Google verification —
    /// everything left is non-sensitive, and nothing here is restricted.
    ///
    /// What it cost: Google no longer returns roster email addresses, so
    /// `ClassroomStudent.matchKey` is nil for every entry and identity matching
    /// runs on normalised display names via `AcademicMatchTable.byName`. That
    /// path was already built and already refuses ambiguous names outright — two
    /// students who normalise alike both drop out rather than one being guessed
    /// at — and the UI already labels those links unverified. What changes is
    /// that it is now the ordinary path rather than the fallback, so a class with
    /// two Emmas will show both as unmatched until the teacher links them by
    /// hand in `ManualRosterLinks`.
    static let classroomScopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.rosters.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.students",
        "https://www.googleapis.com/auth/classroom.student-submissions.students.readonly"
    ]

    /// Everything requested, including identity.
    static let scopes = classroomScopes + [
        "https://www.googleapis.com/auth/userinfo.email"
    ]

    /// Short label for an error message — the full URLs are unreadable in UI.
    static func shortScopeName(_ scope: String) -> String {
        scope.replacingOccurrences(of: "https://www.googleapis.com/auth/", with: "")
    }

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
}

// MARK: - Credential store

/// Keychain-backed storage for the Google refresh token.
final class GoogleCredentialsStore: ObservableObject {

    static let shared = GoogleCredentialsStore()

    private static let service = "com.anchor.google.classroom"
    private static let tokenAccount = "oauth-tokens"
    private static let clientAccount = "oauth-client"
    private static let secretAccount = "oauth-client-secret"

    private let keychain = KeychainStore(service: GoogleCredentialsStore.service)

    @Published private(set) var tokens: GoogleTokens?
    /// A deployment's own OAuth client, entered in Settings → Advanced. `nil`
    /// falls back to the one this build ships with.
    @Published private(set) var clientIDOverride: String?
    /// Google issues one even for Desktop clients and *requires* it on the token
    /// endpoint. It is not a confidential secret — anything shipped in a desktop
    /// binary is readable — which is why PKCE, not this value, is what actually
    /// protects the exchange. Kept in the Keychain regardless.
    @Published private(set) var clientSecretOverride: String?
    @Published private(set) var lastError: String?

    var isConnected: Bool { tokens != nil }

    /// The registration in force: the school's own if they set one, otherwise
    /// whatever the build shipped with. A teacher never sees either.
    var clientID: String? {
        clientIDOverride ?? OAuthClientDefaults.value(OAuthClientDefaults.googleClientID)
    }

    var clientSecret: String? {
        clientSecretOverride ?? OAuthClientDefaults.value(OAuthClientDefaults.googleClientSecret)
    }

    var hasClientID: Bool { clientID != nil }

    /// True when a sign-in can actually be *completed*, not merely started.
    ///
    /// `hasClientID` is enough to build an authorization URL and open a
    /// browser. It is not enough to redeem the code that comes back: Google
    /// requires `client_secret` for a Desktop client, proven by probe on
    /// 2026-08-24 (see `OAuthClientDefaults.googleClientSecret`). Gating the
    /// Connect button on the weaker of the two conditions is what produced the
    /// worst failure shape this app had — consent granted in the browser, then
    /// an error, with the teacher having already handed over access.
    ///
    /// So every gate that decides whether to *offer* Connect reads this, and
    /// `hasClientID` is left to the places that only describe configuration.
    var canCompleteSignIn: Bool { clientID != nil && clientSecret != nil }
    var hasClientSecret: Bool { clientSecret != nil }
    /// True when Connect works with nothing typed in.
    var isUsingBundledClient: Bool { clientIDOverride == nil && hasClientID }

    init() {
        load()
    }

    private func load() {
        // `read` returns Data?? through `try?` — flatten before unwrapping.
        if let data = (try? keychain.read(account: Self.tokenAccount)) ?? nil {
            tokens = try? JSONDecoder().decode(GoogleTokens.self, from: data)
        }
        if let data = (try? keychain.read(account: Self.clientAccount)) ?? nil {
            clientIDOverride = OAuthClientDefaults.value(String(decoding: data, as: UTF8.self))
        }
        if let data = (try? keychain.read(account: Self.secretAccount)) ?? nil {
            clientSecretOverride = OAuthClientDefaults.value(String(decoding: data, as: UTF8.self))
        }
    }

    /// Overrides the shipped OAuth client with a school's own. An empty ID
    /// clears the override and hands control back to OAuthClientDefaults.
    func saveClient(id: String, secret: String?) {
        do {
            if let id = OAuthClientDefaults.value(id) {
                try keychain.save(Data(id.utf8), account: Self.clientAccount)
                clientIDOverride = id
            } else {
                try keychain.delete(account: Self.clientAccount)
                clientIDOverride = nil
            }

            if let secret = OAuthClientDefaults.value(secret ?? "") {
                try keychain.save(Data(secret.utf8), account: Self.secretAccount)
                clientSecretOverride = secret
            } else {
                try keychain.delete(account: Self.secretAccount)
                clientSecretOverride = nil
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Persists the refresh token only; the in-memory copy keeps the access token.
    ///
    /// The in-memory value is set either way so the current session still works,
    /// but a failed write is surfaced rather than swallowed: previously the app
    /// reported "Connected" off the in-memory copy while nothing reached the
    /// Keychain, and the connection silently evaporated on the next launch.
    func save(_ newTokens: GoogleTokens) {
        tokens = newTokens
        do {
            let data = try JSONEncoder().encode(newTokens.keychainPayload)
            try keychain.save(data, account: Self.tokenAccount)

            // Read it straight back. A write that reports success but stores
            // nothing is the failure mode this whole path exists to catch.
            guard let stored = (try? keychain.read(account: Self.tokenAccount)) ?? nil,
                  !stored.isEmpty else {
                lastError = "Signed in, but the Google credential could not be saved to the "
                    + "Keychain — you'll have to reconnect next time Anchor launches."
                return
            }
            lastError = nil
        } catch {
            lastError = "Signed in, but the Google credential could not be saved to the "
                + "Keychain (\(error.localizedDescription)). You'll have to reconnect "
                + "next time Anchor launches."
        }
    }

    /// Updates the in-memory access token without touching the Keychain — a
    /// refresh every hour should not rewrite the stored credential.
    func updateAccessToken(_ accessToken: String, expiresAt: Date) {
        guard var current = tokens else { return }
        current.accessToken = accessToken
        current.expiresAt = expiresAt
        tokens = current
    }

    func disconnect() {
        tokens = nil
        try? keychain.delete(account: Self.tokenAccount)
    }

    func config() -> GoogleOAuthConfig? {
        guard let clientID, !clientID.trimmed.isEmpty else { return nil }
        // The secret is passed through when present — Google's token endpoint
        // rejects a Desktop-client exchange without it (`invalid_client`).
        return GoogleOAuthConfig(
            clientID: clientID,
            clientSecret: clientSecret?.trimmed.isEmpty == false ? clientSecret : nil
        )
    }
}

// MARK: - OAuth client

/// Runs the browser sign-in and exchanges/refreshes tokens.
actor GoogleOAuthClient {

    private let session: URLSession
    private let logger = Logger(subsystem: "com.anchor.google", category: "OAuth")

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Authorization

    /// Opens the system browser, waits for the loopback redirect, and exchanges
    /// the code for tokens.
    /// - Parameter loginHint: the Google address to pre-select, when one is
    ///   already known. Passed when the teacher created their Anchor account
    ///   with Google: they have just proved which Google identity is theirs, so
    ///   asking them to pick it out of a list again is a question Anchor has
    ///   already been told the answer to. It only pre-selects — Google still
    ///   shows the consent screen and the teacher can still switch accounts,
    ///   which is why this does not make the Classroom grant implicit in the
    ///   sign-in. The privacy policy says those two are separate grants and
    ///   neither implies the other, and that stays true.
    func authorize(config: GoogleOAuthConfig, loginHint: String? = nil) async throws -> GoogleTokens {
        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.makeCodeChallenge(from: verifier)
        let state = PKCE.makeState()

        let listener: LoopbackRedirectListener
        do {
            listener = try LoopbackRedirectListener()
        } catch {
            throw Self.classroomError(from: error)
        }
        // `localhost`, not `127.0.0.1`: Google console registers Desktop clients
        // with `http://localhost` and matches the loopback *host string*, while
        // ignoring the port. The listener still binds to 127.0.0.1 — which is
        // what localhost resolves to — so nothing off-machine can reach it.
        let redirectURI = "http://localhost:\(listener.port)"

        var components = URLComponents(
            url: GoogleOAuthConfig.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Required to get a refresh token at all, and to get a fresh one if
            // the teacher has authorised Anchor before.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        // Appended rather than included above so the hint is plainly optional:
        // an empty or whitespace value must not be sent, because Google treats
        // `login_hint=` as a hint to an account named "" and shows an error
        // instead of the picker.
        if let hint = loginHint?.trimmed, !hint.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "login_hint", value: hint))
        }

        guard let authorizationURL = components.url else {
            throw ClassroomError.authorizationFailed("Could not build the sign-in URL.")
        }

        // Start listening before opening the browser, so a fast redirect can't
        // arrive before we're ready for it.
        async let callback = listener.waitForRedirect(expectedState: state)
        await MainActor.run { NSWorkspace.shared.open(authorizationURL) }

        let result: OAuthRedirect
        do {
            result = try await callback
        } catch {
            throw Self.classroomError(from: error)
        }

        guard result.state == state else {
            // A mismatched state means the response didn't come from the request
            // we made. Refuse it rather than exchanging an attacker's code.
            throw ClassroomError.authorizationFailed("Sign-in response did not match the request.")
        }
        if let error = result.error {
            throw result.isUserDenial
                ? ClassroomError.authorizationCancelled
                : ClassroomError.authorizationFailed(result.failureMessage ?? error)
        }
        guard let code = result.code else {
            throw ClassroomError.authorizationFailed("Google did not return an authorization code.")
        }

        var tokens = try await exchange(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI,
            config: config
        )

        // Google reduces the grant silently — it returns whatever the teacher
        // ticked, and some Classroom scopes are simply never offered unless the
        // Cloud console project lists them under Data access.
        //
        // A partial grant is *not* fatal. Refusing the whole sign-in over one
        // missing scope threw away a token that could still list courses and
        // rosters, and left the teacher on a connect button with no way forward.
        // What's missing is recorded on the tokens; the view model degrades the
        // features that need it and says which ones those are.
        guard tokens.canReadCourses else {
            let names = tokens.missingClassroomScopes
                .map(GoogleOAuthConfig.shortScopeName)
                .joined(separator: ", ")
            throw ClassroomError.insufficientScope(names.isEmpty ? nil : names)
        }

        tokens.accountEmail = try? await fetchAccountEmail(accessToken: tokens.accessToken)
        return tokens
    }

    // MARK: Token endpoints

    private func exchange(
        code: String,
        verifier: String,
        redirectURI: String,
        config: GoogleOAuthConfig
    ) async throws -> GoogleTokens {
        var form = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            form["client_secret"] = secret
        }

        let response: TokenResponse = try await post(form: form)

        guard let refreshToken = response.refresh_token else {
            // Without offline access there is nothing to persist, and the
            // teacher would be sent back to the browser every hour.
            throw ClassroomError.authorizationFailed(
                "Google did not return a refresh token. Remove Anchor from your "
                + "Google account's third-party access list and try again."
            )
        }

        return GoogleTokens(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            expiresAt: response.expires_in.map { Date().addingTimeInterval($0) },
            scope: response.scope,
            accountEmail: nil
        )
    }

    /// Trades the refresh token for a new access token.
    func refresh(tokens: GoogleTokens, config: GoogleOAuthConfig) async throws -> (String, Date) {
        var form = [
            "client_id": config.clientID,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            form["client_secret"] = secret
        }

        do {
            let response: TokenResponse = try await post(form: form)
            guard let accessToken = response.access_token else {
                throw ClassroomError.tokenExpired
            }
            return (accessToken, Date().addingTimeInterval(response.expires_in ?? 3600))
        } catch let error as ClassroomError {
            // A revoked or expired refresh token is terminal: the teacher has to
            // sign in again, and retrying would just burn quota.
            if case .server(let status, _) = error, status == 400 || status == 401 {
                throw ClassroomError.tokenExpired
            }
            throw error
        }
    }

    private func fetchAccountEmail(accessToken: String?) async throws -> String? {
        guard let accessToken else { return nil }
        var request = URLRequest(url: GoogleOAuthConfig.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        struct UserInfo: Decodable { var email: String? }
        return try? JSONDecoder().decode(UserInfo.self, from: data).email
    }

    private struct TokenResponse: Decodable {
        var access_token: String?
        var refresh_token: String?
        var expires_in: TimeInterval?
        var scope: String?
    }

    /// Google's OAuth error envelope. Declared at type scope — a type nested in
    /// a generic function can't be used as a generic argument.
    private struct OAuthErrorBody: Decodable {
        var error: String?
        var error_description: String?
    }

    private func post<T: Decodable>(form: [String: String]) async throws -> T {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.encode(form: form).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClassroomError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClassroomError.decoding("Token response was not HTTP.")
        }

        guard (200...299).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            throw ClassroomError.server(
                status: http.statusCode,
                message: body?.error_description ?? body?.error
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClassroomError.decoding(error.localizedDescription)
        }
    }

    private static func encode(form: [String: String]) -> String {
        form.map { key, value in
            let encoded = value.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ) ?? value
            return "\(key)=\(encoded)"
        }
        .joined(separator: "&")
    }

    // MARK: Error mapping

    /// Turns a redirect-transport failure into the error type this flow reports.
    static func classroomError(from error: Error) -> ClassroomError {
        switch error {
        case let error as ClassroomError:
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
