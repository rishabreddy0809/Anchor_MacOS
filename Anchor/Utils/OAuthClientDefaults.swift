//
//  OAuthClientDefaults.swift
//  Anchor
//
//  The OAuth client registrations Anchor ships with, so a teacher never types a
//  credential to connect an account.
//
//  These are *client* identifiers, not user credentials. They identify the app
//  to Zoom and Google; the teacher's own tokens are minted in the browser and
//  kept in the Keychain. A client ID is public by design — it appears in the
//  address bar of every sign-in — and the accompanying secret is not a real
//  secret in a desktop app either, which is why both flows use PKCE (see
//  PKCE.swift) rather than relying on it.
//
//  Anything set here is a *default*: Settings → Advanced can override it, and
//  an override in the Keychain always wins. Leave a value empty and Anchor asks
//  for it instead of opening a browser.
//
//  ── Filling these in ────────────────────────────────────────────────────────
//
//  Zoom (once, by whoever ships the build):
//    1. marketplace.zoom.us → Develop → Build App → **General App**
//       (a *user-managed* OAuth app — a Server-to-Server OAuth app cannot do
//       browser sign-in, it has no authorization page at all)
//    2. OAuth Redirect URL: anchor://oauth/zoom
//       Add the same value to the OAuth allow list.
//    3. Scopes → add what Anchor reads: see ZoomOAuthConfig.requiredScopes.
//    4. Paste the Client ID and Client Secret below.
//
//  Google:
//    1. console.cloud.google.com → new project → enable the Classroom API
//    2. OAuth consent screen → add the Classroom scopes under Data access
//    3. Credentials → Create OAuth client ID → **Desktop app**
//       (Desktop clients redirect to loopback; Google rejects custom URI
//        schemes like anchor:// for this client type, which is why only Zoom
//        appears in Info.plist)
//    4. Paste the Client ID and Client Secret below.
//

import Foundation

nonisolated enum OAuthClientDefaults {

    // MARK: - Zoom

    /// Client ID of the Zoom **General app** used for browser sign-in.
    ///
    /// Distinct from the Server-to-Server OAuth app whose Account ID / Client ID
    /// / Client Secret Settings → Advanced still accepts: that one authenticates
    /// the *account* with no teacher present, and is what the in-meeting bot
    /// uses. This one authenticates the teacher.
    static let zoomClientID = "SMDINiavSZKmyIoF4XmM_A"

    /// Zoom requires this on the token exchange even for a native app. Left
    /// empty in source so it isn't committed; provision it once through
    /// Settings → Zoom → Advanced, or the ANCHOR_ZOOM_OAUTH_CLIENT_SECRET
    /// environment variable, and it lives in the Keychain from then on.
    static let zoomClientSecret = ""

    // MARK: - Meeting SDK

    /// Client ID of the Zoom app with **Embed → Meeting SDK** enabled, used as
    /// the SDK key when signing the Meeting SDK JWT.
    ///
    /// A third registration, distinct from both `zoomClientID` above and the
    /// Server-to-Server pair in Settings → Advanced. The in-meeting bot
    /// authenticates the *app* to the SDK with this, then joins as whichever
    /// Zoom user the ZAK belongs to — the signed-in teacher, in the normal
    /// case. Using the Server-to-Server Client ID here instead makes `sdkAuth`
    /// fail locally, before any network request, which is indistinguishable
    /// from a malformed token.
    static let meetingSDKKey = "QdI3h9EXTtWgQWmZB9frVQ"

    /// Left empty in source like every other secret. Provision once through
    /// `ANCHOR_ZOOM_SDK_SECRET` and it lives in the Keychain from then on —
    /// see `MeetingSDKCredentialStore`.
    static let meetingSDKSecret = ""

    // MARK: - Google

    static let googleClientID = ""
    static let googleClientSecret = ""

    // MARK: - Helpers

    /// Empty strings are "not configured" rather than a credential.
    static func value(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
