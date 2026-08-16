//
//  Constants.swift
//  Anchor
//
//  Non-secret Zoom configuration. Credentials never live here — they are
//  entered in Settings and stored in the Keychain (see KeychainStore).
//

import Foundation

nonisolated enum ZoomConfig {

    // MARK: - Endpoints

    static let tokenURL = URL(string: "https://zoom.us/oauth/token")!
    static let apiBaseURL = URL(string: "https://api.zoom.us/v2")!

    // MARK: - Polling

    /// The dashboard's default refresh cadence.
    static let defaultPollInterval: TimeInterval = 10

    /// Dashboard endpoints are "heavy" rate-limited; never poll REST faster
    /// than this, whatever the refresh setting says.
    static let minimumPollInterval: TimeInterval = 30

    /// Floor for the bot path. Reading participants from a joined Meeting SDK
    /// client is in-process state, not a Zoom API call, so there is no rate
    /// limit to respect — only the cost of rebuilding the roster and re-scoring
    /// it, which is milliseconds. This is what makes 10-second updates real.
    static let minimumBotPollInterval: TimeInterval = 5

    /// Backoff ladder used after a retryable failure.
    static let backoffLadder: [TimeInterval] = [15, 30, 60, 120, 300]

    /// Refresh the access token this long before it actually expires.
    static let tokenRefreshSkew: TimeInterval = 120

    static let requestTimeout: TimeInterval = 30
    static let maxPageSize = 300
    static let maxPages = 10

    // MARK: - Scopes

    /// Scopes the Server-to-Server OAuth app needs. Classic names first, with
    /// the granular equivalents Zoom now issues for new apps.
    static let requiredScopes: [(classic: String, granular: String, purpose: String)] = [
        ("user:read:admin",
         "user:read:user:admin",
         "Verify the connection and identify the host"),
        ("user:read:admin",
         "user:read:token:admin",
         "Mint the bot's ZAK so the Meeting SDK can join as its Zoom user"),
        ("meeting:read:admin",
         "meeting:read:list_meetings:admin",
         "Find the live meeting and read its details"),
        ("dashboard_meetings:read:admin",
         "dashboard:read:list_meeting_participants:admin",
         "Read live participants (needs a Business/Education/Enterprise plan)"),
        ("report:read:admin",
         "report:read:list_meeting_participants:admin",
         "Read participant reports after a meeting ends")
    ]

    // MARK: - Keychain

    static let keychainService = "com.anchor.zoom.credentials"
    /// The teacher's own Zoom account — used to find the live meeting.
    static let keychainAccount = "server-to-server-oauth"
    /// The bot's Zoom account — a separate login that joins the meeting.
    static let botKeychainAccount = "bot-server-to-server-oauth"
}
