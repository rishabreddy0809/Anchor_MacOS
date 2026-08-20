//
//  ZoomModels.swift
//  Anchor
//
//  Domain models for Zoom data, the wire DTOs they are decoded from, and the
//  error type the service layer throws.
//
//  Fields that Zoom's REST API cannot supply during a live meeting are modelled
//  as Optional rather than defaulted, so the UI can distinguish "muted" from
//  "we don't know". See ZoomCapabilities.
//

import Foundation

// MARK: - Meeting

nonisolated struct ZoomMeeting: Identifiable, Hashable, Sendable {
    let id: String                 // numeric meeting ID, e.g. "89012345678"
    var uuid: String?              // instance UUID — required by metrics/report endpoints
    var topic: String
    var hostID: String?
    var hostEmail: String?
    var startTime: Date?
    var durationMinutes: Int?
    var participantCount: Int
    var isLive: Bool
    var timezone: String?

    var elapsed: TimeInterval {
        guard let startTime else { return 0 }
        return max(0, Date().timeIntervalSince(startTime))
    }
}

// MARK: - Participant

nonisolated struct ZoomParticipant: Identifiable, Hashable, Sendable {
    let id: String                 // Zoom participant UUID (stable within an instance)
    var participantID: String?     // the short in-meeting participant id
    var userID: String?
    var name: String
    var email: String?
    var joinTime: Date?
    var leaveTime: Date?
    var isInMeeting: Bool

    // MARK: Signals
    //
    // These are Optional on purpose. The REST API does not report live mute or
    // camera state; they stay nil unless a richer source (Meeting SDK, webhooks)
    // fills them in. Never default these to `false` — a false "unmuted" reading
    // would silently corrupt every struggle score.
    var isMuted: Bool?
    var hasVideo: Bool?
    var handRaised: Bool?
    var speakingSeconds: Int?
    var audioLevel: Int?           // 0...100
    var isSharing: Bool?

    var device: String?
    var status: String?            // "in_meeting", "in_waiting_room"

    /// The account-level Zoom user id, when the source reports one separately
    /// from the in-meeting participant id. A meeting's `hostID` is an account
    /// id, so this is what host matching compares against on the REST path.
    var accountUserID: String?

    // MARK: Role
    //
    // Optional for the same reason the signals above are: only a client that is
    // *in* the meeting knows these, and REST reports neither. Nil means "we
    // don't know" — MeetingRoles then falls back to identity matching rather
    // than treating an unknown role as "student".
    var isHost: Bool?
    /// True for the participant the reporting client *is* — on the bot path,
    /// Anchor's own bot.
    var isSelf: Bool?

    var sessionDuration: TimeInterval {
        guard let joinTime else { return 0 }
        return max(0, (leaveTime ?? Date()).timeIntervalSince(joinTime))
    }
}

// MARK: - Chat

nonisolated struct ZoomChat: Identifiable, Hashable, Sendable {
    let id: String
    var senderID: String?
    var senderName: String
    var message: String
    var timestamp: Date
    var meetingID: String?
}

// MARK: - Account

nonisolated struct ZoomAccountInfo: Hashable, Sendable {
    var userID: String
    var displayName: String
    var email: String?
    var accountID: String?
    var planType: Int?
}

// MARK: - Capabilities

/// What the connected Zoom account can actually deliver. Probed once after
/// connecting so Settings can explain *why* a signal is blank instead of
/// leaving the teacher guessing.
nonisolated struct ZoomCapabilities: Hashable, Sendable {
    var liveMeetingList = false
    var liveParticipants = false     // Dashboard API — needs Business/Edu/Enterprise
    var muteState = false            // Meeting SDK or webhooks only
    var videoState = false           // Meeting SDK or webhooks only
    var handRaised = false           // Meeting SDK or webhooks only
    var audioLevel = false           // Meeting SDK only
    var chat = false                 // post-meeting cloud recording only

    static let restOnly = ZoomCapabilities(
        liveMeetingList: true,
        liveParticipants: true,
        muteState: false,
        videoState: false,
        handRaised: false,
        audioLevel: false,
        chat: false
    )

    /// Signals the dashboard cannot score with, in teacher-readable form.
    var unavailableSignals: [String] {
        var missing: [String] = []
        if !muteState { missing.append("mute state") }
        if !videoState { missing.append("camera state") }
        if !handRaised { missing.append("raised hands") }
        if !audioLevel { missing.append("audio levels") }
        if !chat { missing.append("in-meeting chat") }
        return missing
    }
}

// MARK: - Identity verification

/// Whether Anchor can put a *verified* email against the people in the meeting,
/// and if not, why.
///
/// The Meeting SDK reports no addresses at all, so the bot path depends on the
/// REST Dashboard API to supply them. When that source is unavailable every
/// participant falls back to display-name matching against the Classroom
/// roster — which is unverified, and refused outright when two students share a
/// name. That is a big enough behavioural difference that the reason belongs on
/// screen rather than in a debug log.
nonisolated enum ZoomEmailVerification: Equatable, Sendable {
    /// The bot hasn't polled yet, or every participant already had an address.
    case notAttempted
    /// Zoom supplied addresses for `filled` of the `of` participants missing one.
    case verified(filled: Int, of: Int)
    /// The lookup succeeded and simply carried no addresses. Zoom omits the
    /// email of anyone who isn't a member of the account making the call.
    case unreported(participants: Int)
    /// The lookup itself was refused — plan tier, scope, or network.
    case unavailable(ZoomError)

    /// True when identities are going unverified for a reason worth showing.
    var isDegraded: Bool {
        switch self {
        case .notAttempted, .verified: false
        case .unreported, .unavailable: true
        }
    }

    /// One line for a status row.
    var headline: String {
        switch self {
        case .notAttempted:
            "Email verification hasn't run yet."
        case .verified(let filled, let total):
            "Verified \(filled) of \(total) participant\(total == 1 ? "" : "s") by email."
        case .unreported:
            "Email verification unavailable: Zoom reported no addresses."
        case .unavailable(.planRequired):
            "Email verification unavailable: needs a Business or higher Zoom plan."
        case .unavailable(.insufficientScope(let scope)):
            "Email verification unavailable: missing the \(scope ?? "Dashboard") scope."
        case .unavailable(let error):
            "Email verification unavailable: \(error.errorDescription ?? "Zoom refused the request")."
        }
    }

    /// The explanation under the headline — what it costs and what fixes it.
    var detail: String? {
        switch self {
        case .notAttempted, .verified:
            nil
        case .unreported(let count):
            "Zoom answered but carried no address for \(count) participant"
            + "\(count == 1 ? "" : "s") — it omits the email of anyone who isn't a "
            + "member of your Zoom account, which includes students on personal "
            + "accounts. Ask them to join from a Zoom account on your organisation, "
            + "or Anchor will match them by display name only."
        case .unavailable(.planRequired):
            "Zoom's Dashboard API is the only REST source of participant email "
            + "addresses, and it's restricted to Business, Education and Enterprise "
            + "accounts. The Meeting SDK the bot uses can't supply addresses at all, "
            + "so on this plan every student is matched by display name only — and "
            + "two students sharing a name are matched to neither."
        case .unavailable(.insufficientScope):
            // Was: "Add <scope> to the bot's Server-to-Server OAuth app in the
            // Zoom Marketplace, then re-activate the app." Three problems, and
            // SupportContactTests is written against the first two.
            //
            // It handed a teacher an instruction only a Zoom account admin can
            // carry out, in vocabulary the whole file forbids — the header of
            // SupportContactTests quotes a sentence of exactly this shape as
            // its motivating example, and this one was live the entire time
            // because the scan enumerated ZoomError and ClassroomError and
            // never reached this enum.
            //
            // Third, it named the wrong app. The bot authenticates with the
            // teacher's own grant now; the Server-to-Server registration is
            // optional and only used by a school that wants a dedicated robot
            // account. So even the admin reading over the teacher's shoulder
            // was being sent to the wrong place.
            //
            // What replaces it says what happened, what it costs, and who can
            // act — the pattern the Connect-button copy already uses.
            "Zoom hasn't granted Anchor permission to read participant addresses "
            + "on this account, so students are matched by display name instead. "
            + "That works, but two students whose names match are matched to "
            + "neither. Whoever set Anchor up for your school can change this."
        case .unavailable(let error):
            // The name-matching consequence holds for *every* degraded state,
            // including a transient one — while Anchor cannot read addresses,
            // matching is by name, and that is the only part of this a teacher
            // actually observes. Appended rather than substituted so a network
            // failure keeps its own recovery advice.
            [error.recoverySuggestion, "Until this clears, students are matched by display name."]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    /// A clause for the per-student panel, where the sentence is already long.
    var studentClause: String? {
        switch self {
        case .notAttempted, .verified:
            nil
        case .unreported:
            "Zoom answered but withheld the address — it only shares emails for "
            + "members of your own Zoom account."
        case .unavailable(.planRequired):
            "Zoom's Dashboard API, the only place Anchor can read addresses from, "
            + "needs a Business or higher plan."
        case .unavailable(.insufficientScope):
            // Named a scope and an app at a teacher. Says the same thing in
            // terms of what they can see instead.
            "Zoom hasn't granted Anchor permission to read addresses on this account."
        case .unavailable(let error):
            error.errorDescription
        }
    }
}

// MARK: - Errors

nonisolated enum ZoomError: LocalizedError, Equatable, Sendable {
    case missingCredentials
    /// Meeting SDK Key/Secret — a different credential pair from the S2S OAuth
    /// Client ID/Secret, so this needs its own message.
    case missingSDKCredentials
    /// Carries Zoom's own reason (e.g. "Invalid client_id or client_secret").
    case invalidCredentials(reason: String?)
    /// No teacher has connected their Zoom account yet. Distinct from
    /// `missingCredentials`, which is about the bot's Server-to-Server pair.
    case notSignedIn
    /// No Zoom OAuth app is configured, so Connect has no sign-in page to open.
    /// A build problem rather than anything a teacher can fix — see
    /// OAuthClientDefaults.
    case missingOAuthClient
    /// The teacher closed the browser, or declined on Zoom's consent screen.
    case authorizationCancelled
    /// Browser sign-in failed for a reason Zoom explained.
    case authorizationFailed(String)
    /// The stored grant is gone — revoked in the teacher's Zoom account, or
    /// rotated past. Only a fresh sign-in fixes it.
    case authorizationExpired
    /// Signed in, but the Keychain refused the write. Reported rather than
    /// ignored: a connection that isn't stored evaporates at the next launch.
    case keychainUnavailable
    case insufficientScope(String?)
    case planRequired(String)
    case noActiveMeeting
    case meetingEnded
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case decoding(String)
    case server(status: Int, code: Int?, message: String?)
    case unsupported(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Anchor hasn't been set up with a Zoom account yet."
        case .missingSDKCredentials:
            "Anchor can't join the meeting itself — part of its Zoom setup is missing."
        case .invalidCredentials(let reason):
            reason.map { "Zoom rejected these credentials: \($0)." }
                ?? "Zoom rejected these credentials."
        case .notSignedIn:
            "No Zoom account is connected."
        case .missingOAuthClient:
            "Anchor has no Zoom app configured to sign in with."
        case .authorizationCancelled:
            "Zoom sign-in didn't finish."
        case .authorizationFailed(let detail):
            "Zoom sign-in failed: \(detail)"
        case .authorizationExpired:
            "Your Zoom sign-in has expired."
        case .keychainUnavailable:
            "Anchor couldn't save the Zoom sign-in to your Keychain."
        case .insufficientScope:
            // The scope name is deliberately dropped here and kept in
            // `technicalDetail`: it means nothing to a teacher, and naming it
            // invites them to go looking for a setting that isn't theirs.
            "Anchor hasn't been given permission to see who's in your meetings."
        case .planRequired(let detail):
            "This data needs a paid Zoom plan. \(detail)"
        case .noActiveMeeting:
            "No live meeting found on this account."
        case .meetingEnded:
            "The meeting ended."
        case .rateLimited:
            "Zoom is rate limiting requests."
        case .network(let detail):
            "Network problem: \(detail)"
        case .decoding(let detail):
            "Unexpected response from Zoom: \(detail)"
        case .server(let status, _, let message):
            message.map { "Zoom error \(status): \($0)" } ?? "Zoom returned HTTP \(status)."
        case .unsupported(let detail):
            detail
        case .cancelled:
            "Request cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingCredentials:
            "Anchor hasn't been given its Zoom account details yet. Whoever set Anchor up can add them."
        case .missingSDKCredentials:
            "This copy of Anchor is missing part of its Zoom setup, so it can't join the meeting itself. "
                + "Everything else still works."
        case .invalidCredentials:
            // Was: "Check the credentials in Settings, or regenerate the Client
            // Secret in the Zoom Marketplace." Both halves were impossible.
            // Settings → Advanced is `#if DEBUG`, so the credential UI it sent
            // teachers to does not exist in their build; and regenerating a
            // secret needs a Marketplace account they do not have.
            //
            // It survived because `isSetupProblem` said `false`, and the scan
            // in SupportContactTests only reads setup problems. The
            // classification was the hole, not the list.
            "The Zoom details Anchor was set up with aren't being accepted. "
                + "Whoever set Anchor up for your school can put this right."
        case .notSignedIn:
            "Open Settings → Zoom and click Connect Zoom."
        case .missingOAuthClient:
            "This copy of Anchor is missing part of its Zoom setup. It isn't something you can fix from here."
        case .authorizationCancelled:
            "Click Connect Zoom to try again."
        case .authorizationFailed:
            "Click Connect Zoom to try again. If it keeps failing, check that the Zoom app's "
                + "redirect URL is exactly \(ZoomOAuthConfig.redirectURIForDisplay)."
        case .authorizationExpired:
            "Click Connect Zoom to sign in again."
        case .keychainUnavailable:
            "Anchor still works for this session, but you'll have to reconnect next launch."
        case .insufficientScope:
            "Anchor's Zoom app hasn't been granted one of the permissions it needs. "
                + "It isn't something you can fix from here."
        case .planRequired:
            "Anchor will keep running on the signals your plan does expose."
        case .noActiveMeeting:
            "Start your Zoom class, then click Reconnect."
        case .rateLimited:
            "Anchor will back off and retry automatically."
        case .network:
            "Anchor will retry automatically."
        default:
            nil
        }
    }

    /// The provider's own "come back in N seconds", when it sent one.
    ///
    /// Zoom returns `Retry-After` on a 429 and it is better information than any
    /// ladder Anchor invents. `PollSchedule.retryInterval` takes it as a floor —
    /// see the reasoning there for why a floor rather than an override.
    var retryAfterSeconds: TimeInterval? {
        guard case .rateLimited(let retryAfter) = self else { return nil }
        return retryAfter
    }

    /// Whether a failure is worth trying again at all.
    ///
    /// Read by the participant-email refresh, which gives up permanently on a
    /// failure this rejects. Deliberately *not* what the main polling loop
    /// branches on: that loop stops only for `requiresUserAction`, so a
    /// `.decoding` or `.unsupported` failure keeps retrying there even though
    /// this says it is not retryable. That difference is intended — a transient
    /// malformed response should not end a lesson's monitoring outright, and
    /// stopping mid-class is a worse failure than a few wasted polls — but the
    /// two must not be confused for one another.
    var isRetryable: Bool {
        switch self {
        case .network, .rateLimited, .noActiveMeeting, .meetingEnded, .server:
            true
        case .missingCredentials, .missingSDKCredentials, .invalidCredentials,
             .insufficientScope, .planRequired, .decoding, .unsupported, .cancelled,
             .notSignedIn, .missingOAuthClient, .authorizationCancelled,
             .authorizationFailed, .authorizationExpired, .keychainUnavailable:
            false
        }
    }

    /// True where the teacher reading this cannot be the one to fix it.
    ///
    /// The split that matters for wording is not severity but *audience*.
    /// `.authorizationExpired` and `.noActiveMeeting` are things a teacher
    /// resolves in one click; a missing scope or an unconfigured Meeting SDK
    /// key is a property of the build they were handed. Telling a teacher to
    /// re-activate a Server-to-Server OAuth app does not just fail to help —
    /// it implies the mistake was theirs, which is how a misconfigured install
    /// goes unreported. Views branch on this to offer `SupportContact`
    /// instead of an instruction.
    var isSetupProblem: Bool {
        switch self {
        case .missingCredentials, .missingSDKCredentials, .missingOAuthClient,
             .insufficientScope, .invalidCredentials:
            // `.invalidCredentials` moved here on 2026-08-20. It sat in the
            // `false` list beside `.notSignedIn` and `.noActiveMeeting`, which
            // genuinely *are* the teacher's to fix — and it is not: on a shipped
            // build no teacher ever typed a Zoom credential, so credentials that
            // are wrong are wrong at the setup that installed them.
            //
            // The misclassification was not cosmetic. `isSetupProblem` decides
            // which cases the vocabulary scan reads, so calling this
            // teacher-fixable removed it from the guard *and* justified giving
            // it an instruction, and it got both.
            true
        case .notSignedIn, .authorizationCancelled, .authorizationFailed,
             .authorizationExpired, .keychainUnavailable, .planRequired, .noActiveMeeting,
             .meetingEnded, .rateLimited, .network, .decoding, .server, .unsupported, .cancelled:
            false
        }
    }

    /// The sentence that used to be `recoverySuggestion` for a setup problem,
    /// kept for the person who can act on it.
    ///
    /// Not shown on screen. `SupportContact.reportURL` folds it into the mail
    /// a teacher sends, which is the one place it reaches its actual reader —
    /// so making the teacher-facing copy plainer costs the maintainer nothing.
    var technicalDetail: String? {
        switch self {
        case .missingCredentials:
            "Server-to-Server Account ID / Client ID / Client Secret are not in the Keychain."
        case .missingSDKCredentials:
            "No Meeting SDK Key/Secret. Provision via scripts/provision-zoom-sdk-secret.sh."
        case .missingOAuthClient:
            "OAuthClientDefaults.zoomClientID resolved empty, and no Keychain override is set."
        case .insufficientScope(let scope):
            "Missing scope \(scope ?? "(unnamed)"). Note that the two participant scopes "
                + "cannot be granted below a Business/Education plan — see ZOOM_INTEGRATION.md."
        case .invalidCredentials(let reason):
            // Zoom's own words, which are the whole diagnostic value here —
            // "Invalid client_id or client_secret" says which half to look at.
            // A setup problem with no technicalDetail sends a support mail that
            // says only "something is misconfigured", so this is required, not
            // decorative: `testEverySetupProblemKeepsItsTechnicalDetail`.
            "Zoom rejected the client credentials: \(reason ?? "no reason given"). "
                + "Check the pair provisioned by ADMIN-SETUP.md step 3 against the "
                + "Marketplace app's Development tab."
        default:
            nil
        }
    }

    /// Terminal auth problems that should stop polling and prompt the teacher.
    var requiresUserAction: Bool {
        switch self {
        case .missingCredentials, .missingSDKCredentials, .invalidCredentials, .insufficientScope,
             .notSignedIn, .missingOAuthClient, .authorizationExpired, .authorizationFailed:
            true
        default:
            false
        }
    }
}

// MARK: - Wire DTOs

/// Raw shapes returned by api.zoom.us. Kept separate from the domain models so
/// a Zoom API change never leaks into the dashboard.
nonisolated enum ZoomDTO {

    struct TokenResponse: Decodable, Sendable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
        let scope: String?
    }

    struct APIError: Decodable, Sendable {
        let code: Int?
        let message: String?
    }

    struct User: Decodable, Sendable {
        let id: String
        let firstName: String?
        let lastName: String?
        let email: String?
        let accountId: String?
        let type: Int?
    }

    /// GET /users/{userId}/token — the ZAK, and nothing else.
    struct UserToken: Decodable, Sendable {
        let token: String
    }

    struct MeetingList: Decodable, Sendable {
        let meetings: [Meeting]?
        let nextPageToken: String?
    }

    struct Meeting: Decodable, Sendable {
        let id: ZoomIdentifier
        let uuid: String?
        let topic: String?
        let hostId: String?
        let hostEmail: String?
        let startTime: Date?
        let duration: Int?
        let timezone: String?
        let participants: Int?
    }

    struct MetricsParticipantList: Decodable, Sendable {
        let participants: [MetricsParticipant]?
        let nextPageToken: String?
        let totalRecords: Int?
    }

    /// GET /metrics/meetings/{id}/participants?type=live
    ///
    /// Zoom's Dashboard payload is wide and inconsistent between plans, so every
    /// field here is optional and decoded defensively.
    ///
    /// Property names must match what `.convertFromSnakeCase` produces — do NOT
    /// add snake_case CodingKeys here. The strategy rewrites incoming keys
    /// first, so a `case userName = "user_name"` would never match and every
    /// field would silently decode as nil.
    struct MetricsParticipant: Decodable, Sendable {
        let id: String?
        let userId: String?
        let participantUserId: String?
        let userName: String?
        let email: String?
        let joinTime: Date?
        let leaveTime: Date?
        let device: String?
        let status: String?
        let shareApplication: Bool?
        let shareDesktop: Bool?
        let microphone: String?
        let camera: String?
        let audioQuality: String?
        let videoQuality: String?
    }

    struct ReportParticipantList: Decodable, Sendable {
        let participants: [ReportParticipant]?
        let nextPageToken: String?
    }

    struct ReportParticipant: Decodable, Sendable {
        let id: String?
        let userId: String?
        let name: String?
        let userEmail: String?
        let joinTime: Date?
        let leaveTime: Date?
        let duration: Int?
    }
}

/// Zoom returns meeting IDs as a JSON number in some payloads and a string in
/// others; this normalises both to String.
nonisolated struct ZoomIdentifier: Decodable, Hashable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let number = try? container.decode(Int64.self) {
            value = String(number)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected String or Int meeting id")
            )
        }
    }
}

// MARK: - JSON coding

nonisolated enum ZoomJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = zoomDate(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised Zoom date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    /// Zoom mixes ISO-8601 with and without fractional seconds.
    static func zoomDate(from string: String) -> Date? {
        if let date = fractional.date(from: string) { return date }
        if let date = plain.date(from: string) { return date }
        return nil
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
