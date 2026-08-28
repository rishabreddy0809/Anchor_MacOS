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

    /// Anchor's own Meeting SDK signing endpoint.
    ///
    /// Only used by installs with no local SDK secret — see
    /// `MeetingSDKRemoteSigner`. Not a credential and not secret: it is a URL
    /// that refuses everyone who cannot present a live Zoom grant.
    ///
    /// `ANCHOR_SDK_TOKEN_URL` overrides it, so a preview deployment can be
    /// tested without a rebuild. Read once, at first use.
    static let meetingSDKTokenURL: URL = {
        let fallback = URL(string: "https://anchorteach.vercel.app/api/zoom/sdk-token")!
        guard let raw = ProcessInfo.processInfo.environment["ANCHOR_SDK_TOKEN_URL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let override = URL(string: raw) else {
            return fallback
        }
        return override
    }()

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
    ///
    /// **Two of these cannot be granted on every plan, and that is a product
    /// constraint rather than a configuration mistake.** Verified in the
    /// Marketplace console on 2026-08-17: the scope picker offers only the
    /// categories the signed-in account is entitled to, and on a Pro or Basic
    /// account it lists no Dashboard and no Report category at all — Zoom's own
    /// wording is "the following scopes are available based on your account
    /// privileges. For additional scopes, contact your account admin."
    ///
    /// The two affected rows are the *only* ones that read participants. Without
    /// them the OAuth path can find the live meeting and identify the host and
    /// then see nobody inside it, so every engagement signal has to come from
    /// the Meeting SDK bot. The bot is therefore not an enhancement to the REST
    /// path on those accounts; it is the whole signal source.
    ///
    /// Consequence for a deployment: "which Zoom plan is the account on" is a
    /// qualifying question, not a detail. Business, Education or Enterprise gets
    /// both paths; Pro or Basic gets the bot alone, and `ZoomCapabilities`
    /// should be the thing that says so rather than a roster that silently
    /// stays empty.
    // The five-entry `requiredScopes` table that stood here until 2026-08-28
    // is gone. It had **no callers**, and it listed five scopes while the table
    // Anchor actually checks a grant against —
    // `ZoomOAuthConfig.requiredScopes` — listed three. Two tables that disagree
    // and cannot drift-check each other are worse than one, and the dead one
    // was the more complete, which is the direction that misleads: a reader
    // confirming "does Anchor verify the ZAK scope?" would have found it here
    // and concluded yes.
    //
    // The two it had and the live one did not are now *in* the live one, so a
    // missing ZAK or report scope is reported instead of discovered in a class.
    // For what a school admin must add, see `ADMIN-SETUP.md` step 1.4.

    // MARK: - Keychain

    static let keychainService = "com.anchor.zoom.credentials"
    /// The teacher's own Zoom account — used to find the live meeting.
    static let keychainAccount = "server-to-server-oauth"
    /// The bot's Zoom account — a separate login that joins the meeting.
    static let botKeychainAccount = "bot-server-to-server-oauth"
}
