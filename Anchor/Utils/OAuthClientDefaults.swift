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
//  Anything set here is a *default*: an override in the Keychain always wins.
//  Leave a value empty and Anchor asks for it instead of opening a browser.
//
//  **How an override gets into the Keychain differs by build**, and this is
//  easy to get wrong from the outside. Settings → Advanced is `#if DEBUG` —
//  ship-checklist §4 compiled it out at the declaration, not just the call
//  site, because a teacher must never be asked for a credential. So in a
//  Release build the *only* way to override these is the environment, read
//  once at launch by `AppDelegate.seedCredentialsFromEnvironmentIfNeeded`:
//  `ANCHOR_ZOOM_OAUTH_CLIENT_ID` / `_SECRET`, `ANCHOR_ZOOM_SDK_KEY` /
//  `_SECRET`. That path is not DEBUG-gated and is what a per-school
//  deployment uses — see ADMIN-SETUP.md step 3.
//
//  ── Filling these in ────────────────────────────────────────────────────────
//
//  Zoom (once, by whoever ships the build):
//    1. marketplace.zoom.us → Develop → Build App → **General App**
//       (a *user-managed* OAuth app — a Server-to-Server OAuth app cannot do
//       browser sign-in, it has no authorization page at all)
//    2. App Listing → App Name. The consent screen shows this verbatim, so a
//       default like "General app 392" is what a teacher is asked to approve.
//       It is *not* the pencil beside the page header.
//    3. OAuth Redirect URL: the value in `ZoomOAuthConfig.bounceURL`, currently
//       https://anchor-oauth-bounce.vercel.app/oauth/zoom
//       Paste the identical string into the **OAuth allow list** below it too;
//       setting only one of the two fields is a common way this breaks. Zoom
//       matches character for character — no trailing slash.
//
//       It must be HTTPS. `anchor://oauth/zoom` is rejected at registration
//       ("Use HTTPS or numeric loopback addresses instead of custom URI
//       schemes"), and an `http://127.0.0.1` loopback is accepted by the form
//       but never honoured at authorisation — every redirect_uri then comes
//       back `Invalid redirect URL`, which reads like a typo rather than a
//       transport that cannot work. That URL is served by
//       `Web/oauth-zoom-bounce.html`, which forwards `code` and `state` to the
//       loopback listener Anchor is already running. See ZOOM_INTEGRATION.md
//       §2a — this is easy to re-introduce.
//    4. Scopes → add what Anchor reads: see ZoomOAuthConfig.requiredScopes.
//    5. Paste the Client ID and Client Secret below.
//
//       Development and Production carry *separate* Client IDs and separate,
//       independently-registered redirect URLs. Everything today runs on the
//       Development pair; going live means switching both this value and the
//       Keychain secret, and registering the bounce URL again on the
//       Production tab.
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

    /// Client ID of the same app's **public client**, used when no secret is
    /// available — which is every install not provisioned by an admin.
    ///
    /// **A separate identifier from `zoomClientID`, and that is the whole
    /// point.** Zoom's Marketplace app carries two: the confidential Client ID
    /// above, which must be presented with `zoomClientSecret` over HTTP Basic,
    /// and this one, issued when **Use Public Client OAuth** is enabled and
    /// designed to be redeemed with PKCE and no secret at all. Anchor shipped
    /// only the confidential ID and used it on the secretless path, which can
    /// never work — see `ZoomOAuthConfig.effectiveClientID` for the probes.
    ///
    /// Public by design like every other identifier here: a public client's ID
    /// is not a credential, which is what "public client" means. PKCE is what
    /// proves the request is Anchor's.
    ///
    /// Read from the console 2026-08-20 on the *Anchor* app's Development tab,
    /// where **Use Public Client OAuth** is on.
    static let zoomPublicClientID = "kzU8QEfESJKsvxA3EzCe9A"

    /// Required alongside `zoomClientID` — but **not** required to sign a
    /// teacher in, because `zoomPublicClientID` above needs no secret. Left
    /// empty in source so it isn't committed; provision it once through the
    /// `ANCHOR_ZOOM_OAUTH_CLIENT_SECRET` environment variable — or Settings →
    /// Zoom → Advanced, which exists in **DEBUG builds only** — and it lives
    /// in the Keychain from then on. The environment is the only route in a
    /// shipped build.
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

    /// Client ID of the **Anchor macOS** Desktop client in the `anchor-504419`
    /// Cloud project.
    ///
    /// Public by design, like the Zoom one above — it appears in the address bar
    /// of every Google sign-in. It was empty until 2026-08-17, which meant the
    /// connect flow fell back to asking a teacher to paste a Client ID and
    /// Secret copied out of a console they have no reason to have ever opened.
    /// That is the manual credential entry ship-checklist §4 exists to remove.
    static let googleClientID = "150467027663-9e666lfgaq69bif315c05avvvti1gblk.apps.googleusercontent.com"

    /// Google's client secret for the Desktop client above.
    ///
    /// **Not optional, and this was measured rather than assumed.** Probed
    /// against Google's token endpoint on 2026-08-24 with a valid client id, a
    /// PKCE verifier and no secret:
    ///
    ///     {"error":"invalid_request","error_description":"client_secret is missing."}
    ///
    /// So a Desktop-type client cannot complete the exchange on PKCE alone,
    /// however public the browser flow looks. Before this was provisioned, every
    /// teacher consented in Google's UI and *then* failed — after the consent
    /// screen, which is the worst place to meet an error. `ZoomOAuthConfig`
    /// solved the same problem differently, with a genuine public client id;
    /// Google offers no such thing for this client type.
    ///
    /// Read from the app bundle, not written here, because this repository is
    /// public: see `Config/Secrets.example.xcconfig`. Empty means "not
    /// configured" and the Classroom connect button says so *before* opening a
    /// browser.
    ///
    /// A Keychain override still wins over this, as it does for every value in
    /// this file — that is what a school provisioning its own client uses.
    static var googleClientSecret: String {
        let fromBundle = Bundle.main.object(forInfoDictionaryKey: "ANGoogleOAuthClientSecret") as? String
        return fromBundle ?? ""
    }

    // MARK: - Helpers

    /// Empty strings are "not configured" rather than a credential.
    static func value(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
