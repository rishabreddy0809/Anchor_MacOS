//
//  GoogleIdentitySignIn.swift
//  Anchor
//
//  "Continue with Google" on the account screen — the identity half of Google
//  sign-in, deliberately separate from the Classroom grant in GoogleOAuth.swift.
//
//  ── Why this is not the GoogleSignIn SDK ────────────────────────────────────
//
//  The usual recipe for Firebase + Google on a Mac is to add Google's own
//  GoogleSignIn SDK and let it run the browser flow. Anchor already has that
//  flow: `PKCE`, `LoopbackRedirectListener` and a registered Desktop client
//  (`OAuthClientDefaults.googleClientID`) have been driving the Classroom
//  connection since August. All Firebase actually needs to sign a teacher in
//  with Google is an **ID token** from that same client — `GoogleAuthProvider`
//  takes one directly.
//
//  So this file asks the existing flow for an ID token instead, and Anchor
//  links one Firebase product rather than two SDKs. That is not tidiness: every
//  framework added here has to be re-signed and notarized alongside the ~35
//  Zoom binaries the build already handles, and the build phase that does it
//  was only just made to pass `codesign --verify --deep --strict`. The cheapest
//  dependency is the one not added.
//
//  ── Why the scopes are not GoogleOAuthConfig.scopes ─────────────────────────
//
//  That set carries four Classroom scopes. Reusing it would mean a teacher
//  creating an Anchor account is asked to hand over their roster before they
//  have an account — and would force every existing teacher through a fresh
//  consent screen, because adding a scope invalidates the current grant. The
//  identity request asks for `openid email profile` and nothing else. Two
//  grants, two consent screens, and neither breaks the other.
//
//  `openid` is the load-bearing one: without it Google's token endpoint returns
//  no `id_token` at all, and Firebase has nothing to verify.
//

import AppKit
import Foundation
import os

/// What Firebase needs to sign a teacher in as themselves.
nonisolated struct GoogleIdentityTokens: Sendable {
    /// The JWT Firebase verifies. This is the credential.
    var idToken: String
    /// Passed to Firebase alongside the ID token when Google issues one.
    var accessToken: String?
    /// Read out of the ID token rather than fetched, so there is no second
    /// round trip before the account screen can show who signed in.
    var email: String?
    var displayName: String?
}

nonisolated enum GoogleIdentityConfig {
    /// Identity only. See the file comment for why this is not
    /// `GoogleOAuthConfig.scopes`.
    static let scopes = ["openid", "email", "profile"]
}

/// Runs the browser sign-in and returns an ID token.
actor GoogleIdentityClient {

    private let session: URLSession
    private let logger = Logger(subsystem: "com.anchor.account", category: "GoogleIdentity")

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Opens the system browser, waits for the loopback redirect, and exchanges
    /// the code for an ID token.
    ///
    /// Mirrors `GoogleOAuthClient.authorize` step for step — same PKCE, same
    /// `localhost` redirect (Google matches the host string and ignores the
    /// port, and the listener still binds to 127.0.0.1) — differing only in the
    /// scopes requested and in what is kept from the response.
    func signIn(clientID: String, clientSecret: String?) async throws -> GoogleIdentityTokens {
        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.makeCodeChallenge(from: verifier)
        let state = PKCE.makeState()

        let listener: LoopbackRedirectListener
        do {
            listener = try LoopbackRedirectListener()
        } catch {
            throw AccountError.googleSignInFailed(
                "Anchor could not open a local port to receive the response."
            )
        }
        let redirectURI = "http://localhost:\(listener.port)"

        var components = URLComponents(
            url: GoogleOAuthConfig.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleIdentityConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // No `access_type=offline` and no `prompt=consent`: Anchor keeps no
            // Google refresh token for identity — Firebase mints and holds the
            // session — so asking for one would request a durable grant this
            // flow never uses. `select_account` still lets a teacher who has two
            // Google accounts pick the school one.
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        guard let authorizationURL = components.url else {
            throw AccountError.googleSignInFailed("Could not build the sign-in URL.")
        }

        // Listen before opening the browser, so a fast redirect can't arrive
        // before we're ready for it.
        async let callback = listener.waitForRedirect(expectedState: state)
        await MainActor.run { NSWorkspace.shared.open(authorizationURL) }

        let redirect: OAuthRedirect
        do {
            redirect = try await callback
        } catch let error as OAuthRedirectError {
            throw Self.accountError(from: error)
        }

        if redirect.isUserDenial { throw AccountError.cancelled }
        if let failure = redirect.failureMessage {
            throw AccountError.googleSignInFailed(failure)
        }
        guard let code = redirect.code else { throw AccountError.cancelled }

        return try await exchange(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI,
            clientID: clientID,
            clientSecret: clientSecret
        )
    }

    // MARK: - Token exchange

    private func exchange(
        code: String,
        verifier: String,
        redirectURI: String,
        clientID: String,
        clientSecret: String?
    ) async throws -> GoogleIdentityTokens {
        var form = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        if let clientSecret, !clientSecret.isEmpty {
            form["client_secret"] = clientSecret
        }

        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.encode(form: form).data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountError.networkUnavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder().decode(TokenErrorBody.self, from: data)
            let detail = body?.error_description ?? body?.error ?? "HTTP \(status)"
            logger.error("Google identity token exchange failed: \(detail, privacy: .public)")
            throw AccountError.googleSignInFailed(detail)
        }

        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let idToken = decoded.id_token else {
            // The one failure worth naming precisely: a token response with no
            // `id_token` means `openid` was dropped from the scope list, and
            // every downstream symptom would point at Firebase instead.
            throw AccountError.googleSignInFailed(
                "Google returned no ID token, so Anchor has nothing to sign you in with."
            )
        }

        let claims = Self.claims(fromIDToken: idToken)
        return GoogleIdentityTokens(
            idToken: idToken,
            accessToken: decoded.access_token,
            email: claims["email"] as? String,
            displayName: claims["name"] as? String
        )
    }

    private struct TokenResponse: Decodable {
        var access_token: String?
        var id_token: String?
        var expires_in: TimeInterval?
        var scope: String?
    }

    private struct TokenErrorBody: Decodable {
        var error: String?
        var error_description: String?
    }

    private static func encode(form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

    // MARK: - ID token claims

    /// Reads the payload of a JWT **without verifying it**.
    ///
    /// Safe here and only here: these claims are used to prefill a name and
    /// show which account signed in. Nothing is authorised on their basis —
    /// Firebase verifies the same token against Google's keys server-side and
    /// that verdict, not this, is what creates the session. Anchor must never
    /// grant anything from a claim read here.
    static func claims(fromIDToken token: String) -> [String: Any] {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else { return [:] }

        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Base64URL drops padding; Foundation's decoder requires it.
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func accountError(from error: OAuthRedirectError) -> AccountError {
        switch error {
        case .cancelled: .cancelled
        case .stateMismatch:
            .googleSignInFailed("The response didn't match the request Anchor sent.")
        case .missingCode: .cancelled
        case .provider(let message): .googleSignInFailed(message)
        case .listenerFailed(let message): .googleSignInFailed(message)
        }
    }
}
