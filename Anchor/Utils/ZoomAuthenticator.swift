//
//  ZoomAuthenticator.swift
//  Anchor
//
//  Server-to-Server OAuth token management.
//
//  Note: Zoom retired JWT apps in June 2023. S2S OAuth does not sign a JWT
//  locally — it exchanges the Client ID/Secret (HTTP Basic) plus the Account ID
//  for a bearer token that lives about an hour. This actor caches that token,
//  refreshes it before expiry, and collapses concurrent refreshes into one
//  request.
//

import Foundation

// MARK: - Token source

/// Anything that can hand ZoomService a bearer token.
///
/// Two implementations exist and they authenticate different parties:
///
///   - `ZoomAuthenticator` — Server-to-Server OAuth, below. No human involved.
///     Used by the in-meeting bot, which signs in as its own Zoom account.
///   - `ZoomUserTokenProvider` — the teacher's browser sign-in. Used for the
///     teacher's own connection, so nobody has to be handed admin credentials.
///
/// ZoomService holds one of these and never asks which.
nonisolated protocol ZoomTokenProviding: Sendable {
    /// A valid bearer token, fetching or refreshing as needed.
    func accessToken(forceRefresh: Bool) async throws -> String
    /// Called after a 401 so the next request re-authenticates.
    func invalidate() async
    /// Scopes the current token actually carries, for capability checks.
    func grantedScopes() async -> Set<String>
}

extension ZoomTokenProviding {
    func accessToken() async throws -> String {
        try await accessToken(forceRefresh: false)
    }
}

actor ZoomAuthenticator: ZoomTokenProviding {

    struct AccessToken: Sendable {
        let value: String
        let expiresAt: Date
        let scopes: Set<String>

        func isValid(at date: Date, skew: TimeInterval) -> Bool {
            date.addingTimeInterval(skew) < expiresAt
        }
    }

    private let credentialsProvider: @Sendable () async -> ZoomCredentials?
    private let session: URLSession

    private var cached: AccessToken?
    private var refreshTask: Task<AccessToken, Error>?

    init(
        session: URLSession = .zoomDefault,
        credentialsProvider: @escaping @Sendable () async -> ZoomCredentials?
    ) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    // MARK: - API

    /// Returns a valid bearer token, fetching or refreshing as needed.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let cached,
           cached.isValid(at: Date(), skew: ZoomConfig.tokenRefreshSkew) {
            return cached.value
        }

        // Collapse simultaneous callers onto a single network request.
        if let refreshTask, !forceRefresh {
            return try await refreshTask.value.value
        }

        let task = Task<AccessToken, Error> { try await fetchToken() }
        refreshTask = task

        defer { refreshTask = nil }

        do {
            let token = try await task.value
            cached = token
            return token.value
        } catch {
            cached = nil
            throw error
        }
    }

    /// Called after a 401 so the next request re-authenticates.
    func invalidate() {
        cached = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func grantedScopes() -> Set<String> {
        cached?.scopes ?? []
    }

    // MARK: - Token exchange

    private func fetchToken() async throws -> AccessToken {
        guard let credentials = await credentialsProvider(), credentials.isComplete else {
            throw ZoomError.missingCredentials
        }
        guard let basic = credentials.basicAuthValue else {
            throw ZoomError.invalidCredentials(reason: nil)
        }

        var components = URLComponents(url: ZoomConfig.tokenURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "account_credentials"),
            URLQueryItem(name: "account_id", value: credentials.accountID)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = ZoomConfig.requestTimeout

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
        case 200:
            break
        case 400, 401:
            // The OAuth error body has its own shape ({reason, error}) and says
            // which half is wrong — far more actionable than "bad credentials".
            let reason = (try? JSONDecoder().decode(OAuthErrorBody.self, from: data))?.reason
            throw ZoomError.invalidCredentials(reason: reason)
        case 429:
            throw ZoomError.rateLimited(retryAfter: http.retryAfterSeconds)
        default:
            let body = try? ZoomJSON.makeDecoder().decode(ZoomDTO.APIError.self, from: data)
            throw ZoomError.server(status: http.statusCode, code: body?.code, message: body?.message)
        }

        do {
            let decoded = try ZoomJSON.makeDecoder().decode(ZoomDTO.TokenResponse.self, from: data)
            let scopes = Set((decoded.scope ?? "").split(separator: " ").map(String.init))
            return AccessToken(
                value: decoded.accessToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn)),
                scopes: scopes
            )
        } catch {
            throw ZoomError.decoding("Could not read the token response")
        }
    }
}

/// zoom.us/oauth/token reports failures as {"reason": …, "error": …} rather
/// than the {code, message} shape the v2 API uses.
private nonisolated struct OAuthErrorBody: Decodable {
    let reason: String?
    let error: String?
}

// MARK: - Helpers

extension URLSession {
    /// Shared configuration for Zoom traffic: no caching of authenticated
    /// responses, sane timeouts.
    nonisolated static let zoomDefault: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ZoomConfig.requestTimeout
        configuration.timeoutIntervalForResource = ZoomConfig.requestTimeout * 2
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()
}

extension HTTPURLResponse {
    nonisolated var retryAfterSeconds: TimeInterval? {
        guard let raw = value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw)
    }
}
