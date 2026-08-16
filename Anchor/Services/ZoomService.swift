//
//  ZoomService.swift
//  Anchor
//
//  Zoom REST client. Every dashboard-facing call goes through ZoomDataProviding
//  so the app can run against the live API or the mock without knowing which.
//

import Foundation

// MARK: - Protocol

protocol ZoomDataProviding: Sendable {
    /// Confirms the credentials work and identifies the account.
    func verifyConnection() async throws -> ZoomAccountInfo

    /// A Zoom Access Key for `userID` ("me" for the authenticated user).
    ///
    /// The ZAK is what lets the Meeting SDK enter a meeting *as that Zoom user*
    /// rather than as an anonymous guest. It is short-lived (about two hours),
    /// so it is fetched per join rather than cached.
    func zakToken(userID: String) async throws -> String

    /// Meetings currently in progress for the authenticated user.
    func liveMeetings() async throws -> [ZoomMeeting]

    func meetingDetails(id: String) async throws -> ZoomMeeting

    /// Live participants via the Dashboard API.
    func liveParticipants(meeting: ZoomMeeting) async throws -> [ZoomParticipant]

    /// In-meeting chat. Not available live over REST — see the implementation.
    func chatMessages(meeting: ZoomMeeting) async throws -> [ZoomChat]

    /// What this account can actually deliver.
    func probeCapabilities(meeting: ZoomMeeting?) async -> ZoomCapabilities
}

// MARK: - Live implementation

actor ZoomService: ZoomDataProviding {

    private let authenticator: ZoomTokenProviding
    private let session: URLSession

    /// Guards against hammering the "heavy" Dashboard endpoints.
    private var lastRequestAt: [String: Date] = [:]

    init(
        authenticator: ZoomTokenProviding,
        session: URLSession = .zoomDefault
    ) {
        self.authenticator = authenticator
        self.session = session
    }

    /// Server-to-Server OAuth: the bot's own account, and any deployment still
    /// provisioned that way.
    convenience init(credentialsProvider: @escaping @Sendable () async -> ZoomCredentials?) {
        self.init(authenticator: ZoomAuthenticator(credentialsProvider: credentialsProvider))
    }

    /// The teacher's browser sign-in.
    convenience init(userTokens provider: ZoomUserTokenProvider = .shared) {
        self.init(authenticator: provider)
    }

    // MARK: - Connection

    func verifyConnection() async throws -> ZoomAccountInfo {
        let user: ZoomDTO.User = try await get(path: "/users/me")
        let name = [user.firstName, user.lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmed

        return ZoomAccountInfo(
            userID: user.id,
            displayName: name.isEmpty ? (user.email ?? "Zoom user") : name,
            email: user.email,
            accountID: user.accountId,
            planType: user.type
        )
    }

    /// GET /users/{userId}/token?type=zak
    ///
    /// Requires `user:read:admin` (granular: `user:read:token:admin`) on the
    /// Server-to-Server OAuth app. A 400 here usually means the user id does not
    /// resolve on this account rather than a bad token.
    func zakToken(userID: String) async throws -> String {
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .zoomPathAllowed) ?? userID
        let response: ZoomDTO.UserToken = try await get(
            path: "/users/\(encoded)/token",
            query: [URLQueryItem(name: "type", value: "zak")]
        )

        let token = response.token.trimmed
        guard !token.isEmpty else {
            throw ZoomError.decoding("Zoom returned an empty ZAK for user \(userID)")
        }
        return token
    }

    // MARK: - Meetings

    func liveMeetings() async throws -> [ZoomMeeting] {
        let list: ZoomDTO.MeetingList = try await get(
            path: "/users/me/meetings",
            query: [
                URLQueryItem(name: "type", value: "live"),
                URLQueryItem(name: "page_size", value: "30")
            ]
        )

        return (list.meetings ?? []).map { dto in
            ZoomMeeting(
                id: dto.id.value,
                uuid: dto.uuid,
                topic: dto.topic ?? "Untitled meeting",
                hostID: dto.hostId,
                hostEmail: dto.hostEmail,
                startTime: dto.startTime,
                durationMinutes: dto.duration,
                participantCount: dto.participants ?? 0,
                isLive: true,
                timezone: dto.timezone
            )
        }
    }

    func meetingDetails(id: String) async throws -> ZoomMeeting {
        let dto: ZoomDTO.Meeting = try await get(path: "/meetings/\(id)")
        return ZoomMeeting(
            id: dto.id.value,
            uuid: dto.uuid,
            topic: dto.topic ?? "Untitled meeting",
            hostID: dto.hostId,
            hostEmail: dto.hostEmail,
            startTime: dto.startTime,
            durationMinutes: dto.duration,
            participantCount: dto.participants ?? 0,
            isLive: true,
            timezone: dto.timezone
        )
    }

    // MARK: - Participants

    func liveParticipants(meeting: ZoomMeeting) async throws -> [ZoomParticipant] {
        let identifier = Self.dashboardIdentifier(for: meeting)
        var collected: [ZoomParticipant] = []
        var pageToken: String?
        var pages = 0
        var hasMore = true

        while hasMore, pages < ZoomConfig.maxPages {
            var query = [
                URLQueryItem(name: "type", value: "live"),
                URLQueryItem(name: "page_size", value: String(ZoomConfig.maxPageSize))
            ]
            if let pageToken, !pageToken.isEmpty {
                query.append(URLQueryItem(name: "next_page_token", value: pageToken))
            }

            let page: ZoomDTO.MetricsParticipantList = try await get(
                path: "/metrics/meetings/\(identifier)/participants",
                query: query,
                throttleKey: "metrics"
            )

            collected.append(contentsOf: (page.participants ?? []).map(Self.map(metrics:)))
            pageToken = page.nextPageToken
            pages += 1
            hasMore = !(pageToken ?? "").isEmpty
        }

        return collected
    }

    private static func map(metrics dto: ZoomDTO.MetricsParticipant) -> ZoomParticipant {
        // `microphone` / `camera` describe the *device* in use, not whether the
        // participant is muted or has video on. They are deliberately not mapped
        // to isMuted/hasVideo — that would be an invented signal.
        ZoomParticipant(
            id: dto.id ?? dto.participantUserId ?? dto.userId ?? UUID().uuidString,
            participantID: dto.id,
            userID: dto.userId ?? dto.participantUserId,
            name: dto.userName ?? "Unknown participant",
            email: dto.email,
            joinTime: dto.joinTime,
            leaveTime: dto.leaveTime,
            isInMeeting: (dto.status ?? "in_meeting") == "in_meeting" && dto.leaveTime == nil,
            isMuted: nil,
            hasVideo: nil,
            handRaised: nil,
            speakingSeconds: nil,
            audioLevel: nil,
            isSharing: dto.shareApplication ?? dto.shareDesktop,
            device: dto.device,
            status: dto.status,
            // Kept apart from `userID`, which prefers the in-meeting id: this is
            // the account id a meeting's `hostID` is expressed in, and it is the
            // only way the REST path can recognise the host.
            accountUserID: dto.participantUserId,
            // REST reports no role at all — see MeetingRoles for what stands in.
            isHost: nil,
            isSelf: nil
        )
    }

    // MARK: - Chat

    func chatMessages(meeting: ZoomMeeting) async throws -> [ZoomChat] {
        // There is no REST endpoint that returns in-meeting chat while a meeting
        // is running. `/chat/users/me/messages` is Team Chat (a different
        // product), and meeting chat only becomes available afterwards as a
        // `chat_file` in the cloud recording, if cloud recording is enabled.
        //
        // Rather than silently return [], be explicit so the UI can explain it.
        throw ZoomError.unsupported(
            "Zoom does not expose in-meeting chat over REST while a meeting is live. "
            + "Chat becomes available after the meeting if cloud recording is on."
        )
    }

    // MARK: - Capabilities

    func probeCapabilities(meeting: ZoomMeeting?) async -> ZoomCapabilities {
        var capabilities = ZoomCapabilities()

        // Chat, mute, camera, hand-raise and audio levels are all in-meeting
        // client state; REST cannot see them at all.
        capabilities.muteState = false
        capabilities.videoState = false
        capabilities.handRaised = false
        capabilities.audioLevel = false
        capabilities.chat = false

        capabilities.liveMeetingList = (try? await liveMeetings()) != nil

        if let meeting {
            do {
                _ = try await liveParticipants(meeting: meeting)
                capabilities.liveParticipants = true
            } catch {
                capabilities.liveParticipants = false
            }
        }

        return capabilities
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        throttleKey: String? = nil,
        isRetry: Bool = false
    ) async throws -> T {
        if let throttleKey { try await throttle(key: throttleKey) }

        let token = try await authenticator.accessToken()

        var components = URLComponents(
            url: ZoomConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
            throw ZoomError.decoding("Response was not HTTP")
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try ZoomJSON.makeDecoder().decode(T.self, from: data)
            } catch {
                throw ZoomError.decoding("\(path): \(error.localizedDescription)")
            }

        case 401:
            // Token may have been revoked early — refresh once, then give up.
            guard !isRetry else { throw ZoomError.invalidCredentials(reason: nil) }
            await authenticator.invalidate()
            return try await get(path: path, query: query, throttleKey: nil, isRetry: true)

        case 400:
            // Zoom reports a missing scope as 400/4711, not 403 — and the
            // message names the exact scopes it wanted. Without this branch it
            // fell through to `.server`, which is retryable, so a permanent
            // misconfiguration was retried forever instead of being reported.
            let body = try? ZoomJSON.makeDecoder().decode(ZoomDTO.APIError.self, from: data)
            if body?.code == 4711 {
                throw ZoomError.insufficientScope(
                    Self.scopes(fromScopeError: body?.message) ?? Self.scopeHint(for: path)
                )
            }
            // A plan refusal also arrives as a 400 — the Dashboard endpoints
            // answer `{"code": 200, "message": "This API is only available for
            // ZMP and Business or higher accounts…"}`. Left as `.server` it
            // counted as retryable, so a permanent account-tier limit was
            // re-requested forever and reported as a transient glitch.
            if Self.isPlanRestriction(body?.message) {
                throw ZoomError.planRequired(body?.message ?? "")
            }
            throw ZoomError.server(status: 400, code: body?.code, message: body?.message)

        case 403:
            let body = try? ZoomJSON.makeDecoder().decode(ZoomDTO.APIError.self, from: data)
            let message = body?.message ?? ""
            if message.localizedCaseInsensitiveContains("plan")
                || message.localizedCaseInsensitiveContains("subscription") {
                throw ZoomError.planRequired(message)
            }
            throw ZoomError.insufficientScope(Self.scopeHint(for: path))

        case 404:
            throw ZoomError.meetingEnded

        case 429:
            throw ZoomError.rateLimited(retryAfter: http.retryAfterSeconds)

        default:
            let body = try? ZoomJSON.makeDecoder().decode(ZoomDTO.APIError.self, from: data)
            throw ZoomError.server(status: http.statusCode, code: body?.code, message: body?.message)
        }
    }

    /// Keeps at least `minimumPollInterval / 4` between calls to the same
    /// heavy endpoint family.
    private func throttle(key: String) async throws {
        let minimumGap = ZoomConfig.minimumPollInterval / 4
        if let last = lastRequestAt[key] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minimumGap {
                let wait = minimumGap - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        lastRequestAt[key] = Date()
    }

    /// Pulls the scope list out of a 4711 body, which reads:
    /// `Invalid access token, does not contain scopes:[a:b, a:b:admin].`
    /// Zoom's own answer beats the path-based guess below — it names the
    /// granular scope, which is what the Marketplace UI actually lists.
    static func scopes(fromScopeError message: String?) -> String? {
        guard let message,
              let open = message.firstIndex(of: "["),
              let close = message.firstIndex(of: "]"),
              open < close
        else { return nil }

        let listed = message[message.index(after: open)..<close]
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }

        // Every name Zoom listed, not a pick between them. Which one to add
        // depends on how this connection authenticates — a teacher's browser
        // sign-in wants the user-level scope and cannot be granted the `:admin`
        // one unless they administer the account, while the bot's
        // Server-to-Server app is the opposite. Choosing here got that backwards
        // half the time; Zoom's own list is the honest answer.
        guard !listed.isEmpty else { return nil }
        return listed.joined(separator: " or ")
    }

    /// Whether Zoom's message is "your account tier can't have this", which is
    /// a permanent no rather than a failure to retry.
    ///
    /// Matched on the message because the status/code pair doesn't identify it:
    /// the Dashboard family returns 400 with the *success* code 200 in the body.
    static func isPlanRestriction(_ message: String?) -> Bool {
        guard let message else { return false }
        let markers = [
            "only available for",
            "business or higher",
            "paid account",
            "subscription",
            "does not support this feature"
        ]
        return markers.contains { message.localizedCaseInsensitiveContains($0) }
    }

    private static func scopeHint(for path: String) -> String? {
        if path.hasPrefix("/metrics") { return "dashboard_meetings:read:admin" }
        if path.hasPrefix("/report") { return "report:read:admin" }
        if path.hasPrefix("/users") { return "user:read:admin" }
        if path.hasPrefix("/meetings") { return "meeting:read:admin" }
        return nil
    }

    /// The Dashboard/report endpoints key off the meeting *instance* UUID. A UUID
    /// that starts with "/" or contains "//" has to be URL-encoded twice, or Zoom
    ///404s. Falls back to the numeric meeting ID when no UUID is known.
    static func dashboardIdentifier(for meeting: ZoomMeeting) -> String {
        guard let uuid = meeting.uuid, !uuid.isEmpty else { return meeting.id }

        let needsDoubleEncoding = uuid.hasPrefix("/") || uuid.contains("//")
        guard needsDoubleEncoding else {
            return uuid.addingPercentEncoding(withAllowedCharacters: .zoomPathAllowed) ?? uuid
        }

        let once = uuid.addingPercentEncoding(withAllowedCharacters: .zoomPathAllowed) ?? uuid
        return once.addingPercentEncoding(withAllowedCharacters: .zoomPathAllowed) ?? once
    }
}

extension CharacterSet {
    /// Alphanumerics only — everything else in a Zoom UUID gets percent-encoded.
    nonisolated static let zoomPathAllowed = CharacterSet.alphanumerics
}
