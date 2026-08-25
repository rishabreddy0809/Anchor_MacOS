//
//  MeetingBot.swift
//  Anchor
//
//  The "bot joins the meeting" path.
//
//  A bot is what makes real engagement signals possible: mute state, camera
//  state, raised hands and active speaker are in-meeting client state, and the
//  only way to observe them is to *be* a client in the meeting. The Zoom Meeting
//  SDK cannot attach to a call the desktop client is already in — it joins as an
//  additional participant.
//
//  Everything here except the SDK call itself is implemented and tested. See
//  ZoomMeetingSDKBot for exactly what remains.
//

import CryptoKit
import Foundation

// MARK: - Protocol

nonisolated struct BotJoinRequest: Sendable, Equatable {

    /// The name the bot joins under. Named rather than inlined because
    /// MeetingRoles matches on it: on the REST path this string is the only
    /// thing that distinguishes Anchor's own participant from a student.
    static let defaultDisplayName = "Anchor (engagement assistant)"

    var meetingNumber: String
    var passcode: String?
    var displayName: String = Self.defaultDisplayName

    /// Zoom displays meeting IDs grouped ("812 3456 7890") and the invite link
    /// spells them with dashes, but both the SDK and the REST API want bare
    /// digits. Normalising here covers every entry point rather than trusting
    /// each caller to have pasted it cleanly.
    var normalizedMeetingNumber: String {
        meetingNumber.filter(\.isNumber)
    }
}

nonisolated struct BotSession: Sendable, Equatable {
    var meetingNumber: String
    var joinedAt: Date
    var displayName: String
}

/// One line of Zoom's live transcript, exactly as the SDK reported it.
///
/// Deliberately un-attributed: the SDK knows a speaker's in-meeting id and
/// display name, but not whether that person is the teacher, a student or
/// Anchor's own bot. That judgement belongs to `MeetingRoles`, which needs the
/// participant list, so it happens one layer up in TranscriptCaptureService.
nonisolated struct RawTranscriptLine: Identifiable, Hashable, Sendable {
    /// Zoom's message id. Stable across the revisions of one utterance, which is
    /// what lets a corrected line replace its earlier self instead of appending.
    let id: String
    var speakerID: String?
    var speakerName: String
    var text: String
    var timestamp: Date
    /// True once Zoom says it has stopped revising this line.
    var isFinal: Bool
}

protocol MeetingBotProviding: Sendable {
    var isJoined: Bool { get async }
    func join(_ request: BotJoinRequest) async throws -> BotSession
    func leave() async throws
    /// Full-fidelity participant state — the reason the bot exists.
    func participants() async throws -> [ZoomParticipant]
    /// In-meeting chat, oldest first. Only a client in the meeting can see it —
    /// the REST API has no equivalent for a live meeting.
    func chatMessages() async throws -> [ZoomChat]
    func capabilities() async -> ZoomCapabilities

    // MARK: Live transcript
    //
    // Same shape as chat, and for the same reason: captions are in-meeting
    // client state, so only a joined client can read them. Zoom has no REST
    // equivalent for a live meeting.

    /// Asks Zoom to start transcribing. Idempotent — safe to call on every poll,
    /// and a no-op once transcription is already running.
    func startTranscription() async
    /// The transcript so far, oldest first.
    func transcript() async throws -> [RawTranscriptLine]
    /// Whether transcription is running, and if not, why not.
    func transcriptAvailability() async -> TranscriptAvailability
}

// MARK: - Meeting SDK JWT

/// Meeting SDK authentication.
///
/// Note this is genuinely a signed JWT, unlike the REST API — Zoom retired JWT
/// *apps* in 2023, but the Meeting SDK still authenticates with a short-lived
/// HS256 token signed locally with the SDK Key/Secret. These are a *different*
/// credential pair from the Server-to-Server OAuth Client ID/Secret: create a
/// "Meeting SDK" app in the Marketplace to get them.
/// Fetches a Meeting SDK token from Anchor's signing endpoint.
///
/// Used when this install has no local SDK secret — which is every install an
/// admin did not provision by hand, i.e. every individual teacher.
///
/// The secret stays on the server, and `ship-checklist.md:136` is why: the SDK
/// secret is an HS256 *signing key*, so anyone who extracts it from a shipped
/// binary can mint Meeting SDK tokens as Anchor. That ruled out shipping it,
/// which ruled out the bot for per-teacher installs, which — since the
/// participant REST scopes are gated on the teacher's own account being
/// Business or Education — meant no live signal at all for them. A signing
/// endpoint is the third option that framing was missing, and the one Zoom
/// documents as standard.
///
/// Authorised with the teacher's own Zoom access token: anyone entitled to run
/// the bot has necessarily authorised Anchor's Zoom app, so a live Zoom grant
/// is exactly the right thing to prove. The server verifies it with Zoom before
/// signing anything.
nonisolated struct MeetingSDKRemoteSigner: Sendable {

    var endpoint: URL
    /// Supplies a current Zoom access token, refreshing it if needed.
    var zoomAccessToken: @Sendable () async throws -> String

    private struct TokenResponse: Decodable { var token: String }
    private struct FailureBody: Decodable { var error: String? }

    func token(session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await zoomAccessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZoomError.unsupported(
                "Anchor could not reach its meeting service. Check your connection and try again."
            )
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // The server's message is already written for a teacher: 503 means
            // this build is unconfigured, 401 means reconnect Zoom. Passing it
            // through beats inventing a second vocabulary for the same states.
            let detail = (try? JSONDecoder().decode(FailureBody.self, from: data))?.error
            throw ZoomError.unsupported(detail ?? "Anchor's meeting service returned an error.")
        }

        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !decoded.token.isEmpty else {
            throw ZoomError.unsupported("Anchor's meeting service returned no token.")
        }
        return decoded.token
    }
}

nonisolated struct MeetingSDKTokenProvider: Sendable {

    var sdkKey: String
    var sdkSecret: String

    /// Set when there is no local secret to sign with. Nil means local-only,
    /// which is the per-school case where an admin provisioned the secret.
    var remote: MeetingSDKRemoteSigner?

    /// Signs the SDK authentication token. Zoom requires `exp` between 30
    /// minutes and 48 hours out, and `tokenExp` >= `exp`.
    ///
    /// The claim set is deliberately minimal. `mn` and `role` belong to the
    /// *Web* Meeting SDK signature, which binds a token to one meeting and one
    /// role; the native macOS SDK authenticates the **app**, not a meeting, and
    /// takes the meeting number through `ZoomSDKJoinMeetingElements` instead.
    /// Sending the web claims here makes `sdkAuth` reject the token. `sdkKey` is
    /// likewise a deprecated alias for `appKey` and is left out.
    func token(
        lifetime: TimeInterval = 2 * 60 * 60,
        issuedAt: Date = Date()
    ) throws -> String {
        guard !sdkKey.isEmpty, !sdkSecret.isEmpty else {
            throw ZoomError.missingSDKCredentials
        }

        let iat = Int(issuedAt.timeIntervalSince1970)
        let exp = Int(issuedAt.addingTimeInterval(lifetime).timeIntervalSince1970)

        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let payload: [String: Any] = [
            "appKey": sdkKey,
            "iat": iat,
            "exp": exp,
            "tokenExp": exp
        ]

        let encodedHeader = try Self.base64URLEncodedJSON(header)
        let encodedPayload = try Self.base64URLEncodedJSON(payload)
        let signingInput = "\(encodedHeader).\(encodedPayload)"

        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: Data(sdkSecret.utf8))
        )

        return "\(signingInput).\(Self.base64URLEncode(Data(signature)))"
    }

    /// The token to actually authenticate with: signed here when a local secret
    /// exists, fetched from the signing endpoint otherwise.
    ///
    /// Local wins deliberately. A school that provisioned its own Meeting SDK
    /// app must keep using it — falling through to Anchor's endpoint would
    /// quietly authenticate their bot as Anchor's app instead of theirs, which
    /// is the same class of substitution the school-id canary caught once
    /// already.
    func resolvedToken(
        lifetime: TimeInterval = 2 * 60 * 60,
        issuedAt: Date = Date(),
        session: URLSession = .shared
    ) async throws -> String {
        if !sdkKey.isEmpty, !sdkSecret.isEmpty {
            return try token(lifetime: lifetime, issuedAt: issuedAt)
        }
        guard let remote else { throw ZoomError.missingSDKCredentials }
        return try await remote.token(session: session)
    }

    private static func base64URLEncodedJSON(_ object: [String: Any]) throws -> String {
        // Sorted keys keep the output deterministic, which makes the token
        // testable against an independently computed signature.
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URLEncode(data)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Join payload

/// Everything the Meeting SDK needs for one `joinMeeting` call, assembled and
/// validated before the SDK is involved.
///
/// This exists so the parts Anchor *can* do without the framework — OAuth, the
/// ZAK fetch, signing the JWT — are testable on their own, and so the remaining
/// SDK work is a single function that consumes this.
nonisolated struct MeetingSDKJoinContext: Sendable, Equatable {
    /// Locally signed HS256 token from the SDK Key/Secret.
    var sdkToken: String
    /// Zoom Access Key for the bot's own user, from
    /// GET /users/{userId}/token?type=zak.
    ///
    /// Optional on purpose: a ZAK makes the bot join *as its Zoom user*, which
    /// is what the host sees and what "join as authenticated user" meetings
    /// require. Joining a stranger's open meeting as a plain guest does not need
    /// one, so a failed fetch degrades rather than blocking the join.
    var zak: String?
    var meetingNumber: String
    var passcode: String?
    var displayName: String
    /// The account the ZAK belongs to.
    var identity: ZoomAccountInfo
}

// MARK: - Real SDK adapter

/// Adapter for Zoom's Meeting SDK for macOS.
///
/// The framework is not linked in this project, so `join` fails with a
/// descriptive error rather than pretending to connect. To finish it:
///
///  1. Marketplace → Build App → **Meeting SDK**; note the SDK Key/Secret.
///  2. Download "Zoom Meeting SDK for macOS", add `ZoomSDK.framework` to the
///     target (Embed & Sign).
///  3. Set `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT` / `..._CAMERA` and add usage
///     strings — the SDK requires mic and camera even for an observer bot.
///  4. Replace the body of `connect(_:)` with `ZoomSDK.shared()` auth using
///     `context.sdkToken`, then `joinMeeting` with `context.zak`. Everything
///     that call needs is already assembled by `prepareJoin(_:)`.
///  5. Map the SDK's participant callbacks into `ZoomParticipant`, filling in
///     `isMuted`, `hasVideo`, `handRaised` and `audioLevel`.
///
/// Steps 1–3 are configuration; 4 and 5 are the only real code left.
actor ZoomMeetingSDKBot: MeetingBotProviding {

    private let tokenProvider: MeetingSDKTokenProvider
    /// The bot's own Zoom account. Authenticating proves the bot identity is
    /// real before we attempt to put it in a meeting.
    private let accountService: ZoomDataProviding?
    private var session: BotSession?
    private(set) var account: ZoomAccountInfo?

    init(tokenProvider: MeetingSDKTokenProvider, accountService: ZoomDataProviding? = nil) {
        self.tokenProvider = tokenProvider
        self.accountService = accountService
    }

    var isJoined: Bool { session != nil }

    /// Signs the bot into its Zoom account. This part is fully working — it is
    /// the "bot authenticates with Zoom OAuth" step.
    @discardableResult
    func authenticate() async throws -> ZoomAccountInfo {
        guard let accountService else { throw ZoomError.missingCredentials }
        let info = try await accountService.verifyConnection()
        account = info
        return info
    }

    func join(_ request: BotJoinRequest) async throws -> BotSession {
        let context = try await prepareJoin(request)
        let session = try await connect(context)
        self.session = session
        return session
    }

    /// Steps 1–3 of the join: authenticate, mint a ZAK, sign the SDK token.
    /// All of this runs for real against Zoom today.
    func prepareJoin(_ request: BotJoinRequest) async throws -> MeetingSDKJoinContext {
        let meetingNumber = request.normalizedMeetingNumber
        guard !meetingNumber.isEmpty else {
            throw ZoomError.unsupported("\"\(request.meetingNumber)\" is not a Zoom meeting number.")
        }

        // 1. Bot signs into its own Zoom account (real).
        let identity = try await authenticate()

        // 2. Sign the Meeting SDK auth token (real — verified against an
        //    independent HMAC implementation). It authenticates the app, not
        //    this meeting: the meeting number travels separately, in
        //    ZoomSDKJoinMeetingElements.
        let sdkToken = try await tokenProvider.resolvedToken()

        // 3. Mint a ZAK so the SDK joins as the bot's Zoom user rather than an
        //    anonymous guest. Non-fatal: a guest join is still a valid outcome
        //    for an open meeting, and failing here would turn a working join
        //    into an error.
        let zak = try? await accountService?.zakToken(userID: identity.userID)

        return MeetingSDKJoinContext(
            sdkToken: sdkToken,
            zak: zak,
            meetingNumber: meetingNumber,
            passcode: request.passcode,
            displayName: request.displayName,
            identity: identity
        )
    }

    /// Step 4 — authenticates the linked Meeting SDK with the locally signed
    /// JWT, then joins with the ZAK (or as a guest if none was minted). The
    /// SDK's own delegate callbacks are bridged to async/await by
    /// `ZoomMeetingSDKBridge`, which also runs on the main actor since Zoom's
    /// SDK expects its calls there.
    private func connect(_ context: MeetingSDKJoinContext) async throws -> BotSession {
        let bridge = ZoomMeetingSDKBridge.shared
        try await bridge.authenticate(jwtToken: context.sdkToken)
        try await bridge.joinMeeting(
            meetingNumber: context.meetingNumber,
            passcode: context.passcode,
            displayName: context.displayName,
            zak: context.zak
        )
        return BotSession(
            meetingNumber: context.meetingNumber,
            joinedAt: Date(),
            displayName: context.displayName
        )
    }

    func leave() async throws {
        await ZoomMeetingSDKBridge.shared.leaveMeeting()
        session = nil
    }

    func participants() async throws -> [ZoomParticipant] {
        guard session != nil else { throw ZoomError.unsupported("Bot has not joined a meeting.") }
        return await ZoomMeetingSDKBridge.shared.currentParticipants()
    }

    func chatMessages() async throws -> [ZoomChat] {
        guard session != nil else { throw ZoomError.unsupported("Bot has not joined a meeting.") }
        return await ZoomMeetingSDKBridge.shared.currentChatMessages()
    }

    // MARK: - Live transcript

    func startTranscription() async {
        guard session != nil else { return }
        await ZoomMeetingSDKBridge.shared.startLiveTranscription()
    }

    func transcript() async throws -> [RawTranscriptLine] {
        guard session != nil else { throw ZoomError.unsupported("Bot has not joined a meeting.") }
        return await ZoomMeetingSDKBridge.shared.currentTranscript()
    }

    func transcriptAvailability() async -> TranscriptAvailability {
        guard session != nil else { return .notStarted }
        return await ZoomMeetingSDKBridge.shared.transcriptAvailability
    }

    func capabilities() async -> ZoomCapabilities {
        ZoomCapabilities(
            liveMeetingList: true,
            liveParticipants: true,
            muteState: true,
            videoState: true,
            handRaised: true,
            audioLevel: true,
            chat: true
        )
    }
}
