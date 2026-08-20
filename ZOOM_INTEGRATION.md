# Zoom Integration

How Anchor talks to Zoom, what it can and cannot see, and how to set it up.

---

## 1. Rotate the secret first

The Client Secret for this app was shared in a screenshot and must be treated as
compromised. Before using Anchor against a real class:

**Zoom Marketplace → Develop → your Server-to-Server OAuth app → Regenerate Client Secret.**

No credential is stored in this repository. Anchor reads credentials only from
the macOS Keychain, written via Settings.

---

## 2a. Create the Zoom app teachers sign in with (General app)

This is the one a teacher pilot needs. It is what makes **Connect Zoom** open a
browser instead of asking anybody to type a credential.

1. <https://marketplace.zoom.us> → **Develop → Build App → General App**
   (user-managed). A Server-to-Server OAuth app **cannot** be used here — it has
   no sign-in page at all.
2. **OAuth Redirect URL**: `https://anchor-oauth-bounce.vercel.app/oauth/zoom` — exactly this,
   on the **Development** credentials tab (Zoom keeps separate redirect
   registrations per environment; editing Production has no effect on the dev
   Client ID/Secret pair). Add the identical string to the **OAuth allow
   list** below it too — setting only one of the two fields is a common way
   this breaks. Zoom matches character for character: no trailing slash.

   It must be **HTTPS**. Neither `http://127.0.0.1:51789/oauth/zoom` nor
   `anchor://oauth/zoom` works, for two different reasons: Zoom rejects custom
   URI schemes outright at registration ("Use HTTPS or numeric loopback
   addresses instead of custom URI schemes"), and it silently fails to honour
   an `http://` numeric loopback at authorisation — the form stores the string
   but the OAuth service never matches it. See the OPEN ISSUE box below for the
   evidence. That URL is served by `Web/oauth-zoom-bounce.html`, which forwards
   `code` and `state` to the loopback listener Anchor is already running, so
   the redirect still lands back in the app.
3. **Scopes**: add the rows in the table below. A teacher who is not a Zoom
   account admin can only be granted the non-`:admin` spellings, and that is
   fine — Anchor degrades to the bot for live signals and says so in Settings.
   The app as it stands carries exactly three: `meeting:read:list_meetings`,
   `user:read:user`, `user:read:zak` — find the class, identify the teacher,
   mint the bot's ZAK.
4. Paste the **Client ID** into `OAuthClientDefaults.zoomClientID`. Provision the
   **Client Secret** through Settings → Zoom → Advanced, or
   `ANCHOR_ZOOM_OAUTH_CLIENT_SECRET`, so it stays out of source control.

Teachers then click **Settings → Zoom → Connect Zoom**, sign in, and land back in
Anchor. The tokens go to the Keychain; the refresh token rotates on every use and
is rewritten each time.

> **The two participant scopes are not on this app, and cannot be added from
> this account.** `dashboard:read:list_meeting_participants:admin` and
> `report:read:list_meeting_participants:admin` are absent, and the Marketplace
> scope picker offers no Dashboard and no Report category at all to select them
> from — the categories themselves are gated on a Business, Education or
> Enterprise plan, so this is not an oversight that a checkbox fixes. §2b's note
> about a 403 describes the plan failing at request time; here the request can
> never be built in the first place.
>
> What that means for a deployment: on an account below those plans the REST
> path can never read participants, so it contributes the meeting itself and the
> teacher's identity and nothing about who is in the room. **The Meeting SDK bot
> is then the only source of live engagement signal** — not the richer of two
> sources, the only one. A pilot on a Basic or Pro account that cannot run the
> bot has no live signal at all, and the dashboard will correctly stay empty
> (§6). This is the concrete cost of the per-teacher account model still listed
> as open in `ship-checklist.md`; the per-school route on an Education account is
> what makes the REST path viable.

> **Only the developer's own Zoom account can sign in today.** While the app is
> unpublished, users *outside* that account cannot authorize it at all — they
> get the same `You cannot authorize` page as a bad redirect, which is easy to
> mistake for the bug fixed above.
>
> **The escape hatch, if the pilot allows it:** create the Marketplace app under
> the *school's* Zoom account. Every teacher on that account is then an internal
> user, and none of the review below applies. Only cross-account distribution
> needs Zoom's approval.
>
> Otherwise external access goes through **Production → Beta Test**, which as of
> 2026-08-09 requires all of: Basic Information (OAuth Redirect URL + developer
> contact), one Scopes field, one App Listing field, a complete listing
> (company name, descriptions, Privacy Policy URL, Terms of Use URL, Support
> URL), and — Zoom's wording — *"submission of supporting security evidence is
> mandatory for beta testing"*. Budget well beyond the 3–4 business days the
> docs quote for sharing an authorization URL; that figure covers the review,
> not assembling the evidence.
>
> **Renamed 2026-08-17 — done.** The consent screen shows the app's name
> verbatim, and it used to read *"General app 392 would like permission to…"*,
> which is not what a teacher should be asked to approve. It now reads *"Anchor
> would like permission to:"*. Recorded because the name is edited on **App
> Listing → App Name**, not the pencil beside the header, and a freshly created
> app arrives carrying its generated name — so any second app built for
> production starts out saying "General app N" again.

> **Production uses different credentials from Development.** The Production tab
> carries its own Client ID (`Vgi566QtQhaoeAO…`) and its own, initially empty,
> OAuth Redirect URL — everything that works today runs on the *Development*
> pair (`SMDINiavSZKmyIoF4XmM_A`). Going live is therefore not just a Zoom
> approval: `OAuthClientDefaults.zoomClientID` and the Keychain client secret
> must both switch to the production pair, and the bounce URL must be
> registered again on the Production tab, in both the redirect field and the
> allow list. Re-verify the flow after switching — a production redirect that
> was never registered fails exactly like the bug documented below, with the
> same misleading message.

`ZoomOAuthConfig.redirect` defaults to `.loopback(port: 51789, path: "oauth/zoom")`.
The listener for that path already exists — see `LoopbackRedirectListener` — and
Google Classroom uses the same mechanism for its own, unrelated reason (Google
rejects custom URI schemes for Desktop clients too, but for a different
underlying reason than Zoom's).

> **RESOLVED 2026-08-08.** Zoom rejected the *loopback* redirect at the consent
> step with `Invalid redirect URL`, even registered exactly right. The fix was
> to stop using a loopback redirect with Zoom at all: Anchor now registers the
> HTTPS bounce URL above, `Web/oauth-zoom-bounce.html` forwards `code` and
> `state` to `127.0.0.1:51789`, and `LoopbackRedirectListener` catches it
> unchanged. Verified end to end — Zoom's consent screen renders for the
> registered HTTPS URL and still returns `Invalid redirect URL` for an
> unregistered one, so the check is genuinely passing rather than being
> skipped. The history below is kept because the failure is easy to
> re-introduce and the error message points at the wrong thing.
>
> What was ruled out, by direct verification against the Development app
> `SMDINiavSZKmyIoF4XmM_A`:
>
> - The **OAuth Redirect URL** and the **OAuth allow list** both hold
>   `http://127.0.0.1:51789/oauth/zoom`. Read back from the form after a full
>   reload, so they are persisted server-side, not unsaved edits — 33
>   characters, no trailing slash or stray whitespace, matching
>   `OAuthRedirectTransport.loopback` byte for byte.
> - Scopes are present (`meeting:read:list_meetings`, `user:read:user`,
>   `user:read:zak`).
> - The Client Secret is valid: `POST /oauth/token` with a deliberately bogus
>   code returns `invalid_grant` ("Invalid authorization code"), whereas a
>   wrong secret returns `invalid_client`. The credential pair is accepted.
> - Zoom's own **Local Test → Add app now** builds
>   `https://zoom.us/oauth/authorize?response_type=code&client_id=…&redirect_uri=http://127.0.0.1:51789/oauth/zoom`
>   — identical to what `ZoomOAuthHandler` sends, and it fails identically.
>
> **Confirmed cause.** Zoom's Marketplace UI stores the `http://` loopback
> string, but its OAuth service never honours it — the app's effective redirect
> list stays empty, so *every* candidate fails the match. Proof, by probing
> `marketplace.zoom.us/v2/authorize` while signed in:
>
> | App | `redirect_uri` sent | Result |
> |---|---|---|
> | General app 392 | its own registered `http://127.0.0.1:51789/oauth/zoom` | `Invalid redirect URL.` |
> | General app 392 | anything else, incl. never-registered URLs | `Invalid redirect URL.` |
> | Anchor Meeting SDK | its own registered `https://anchor-app.com/oauth/callback` | **no error — consent renders** |
> | Anchor Meeting SDK | a deliberately wrong URL | `Invalid redirect URL.` |
>
> The sibling app is *also* a Draft, so Draft status is not the blocker, and the
> check demonstrably discriminates correctly when a redirect is genuinely
> registered. The only material difference is the scheme: **HTTPS works, the
> `http://` numeric loopback does not.** Toggling **Use Public Client OAuth**
> (PKCE, no secret) does not change this — it was tried and the failure is
> identical, so this is not the confidential-vs-public-client distinction that
> Zoom's docs describe for loopback redirects.
>
> **Consequence:** `OAuthRedirectTransport.loopback` cannot be used with Zoom.
> Anchor now ships `.hostedBounce` instead: it registers an HTTPS URL with
> Zoom, while `LoopbackRedirectListener` still catches the callback on
> `127.0.0.1:51789` exactly as before. Only the string handed to Zoom changed.
>
> Both ends are already in place: the page is deployed on Vercel (project
> `anchor-oauth-bounce`, redeploy with `Web/deploy.sh`), and the URL is
> registered on the Development app in **both** the OAuth Redirect URL field
> and the OAuth allow list.
>
> The authorization code transits that page, so keep it static — no analytics,
> no tag managers, no third-party scripts, any of which could read the code out
> of the URL. It forwards only `code`, `state`, `error` and
> `error_description`, and is served `no-store` with a restrictive CSP. The
> code is single-use and PKCE-bound to a verifier that never leaves the Mac.
>
> Change `ZoomOAuthConfig.bounceURL` and the Marketplace registration together
> if the URL ever moves; `Web/deploy.sh` rewrites the constant automatically.
> Use `vercel deploy --prod`, never a preview deployment: previews get a fresh
> URL each time and Zoom matches character for character. Note the
> deployment-specific URL sits behind Vercel's Deployment Protection SSO — only
> the production alias is publicly reachable, which is what teachers hit. §2b (Server-to-Server, the bot) is unaffected and still
> works — it never touches a browser.
>
> Note: **Use Public Client OAuth** was enabled on the Development app while
> diagnosing this. It is not required by the above and did not change the
> outcome.
>
> **This note used to call the toggle "harmless and arguably correct for a
> desktop client". It is not harmless — it is load-bearing, and Anchor was not
> using it. Corrected 2026-08-20.**
>
> Enabling **Use Public Client OAuth** mints a **second identifier**: a
> *Public Client ID*, shown beneath the toggle and distinct from the app's
> confidential Client ID. That is the one redeemable with PKCE and no secret.
> Anchor shipped only the confidential id and sent it on the secretless path,
> which returns `400 invalid_client` forever.
>
> Measured against `zoom.us`:
>
> | request | result |
> |---|---|
> | confidential id, PKCE, no secret | `400 invalid_client` |
> | **public id, PKCE, no secret** | **`400 invalid_grant` "Invalid authorization code"** |
> | public id, `refresh_token` grant | `400 invalid_grant` "Invalid refresh token" |
> | public id + a bogus Basic header | `400 invalid_grant` — the header is ignored |
>
> `invalid_grant` means the client authenticated and the deliberately bogus
> code was rejected, which is as far as a probe reaches without a real one.
>
> **Console state, read 2026-08-20** (Development tab, *Anchor* app): toggle
> **on**; Public Client ID `kzU8QEfESJKsvxA3EzCe9A`; OAuth Redirect URL
> `https://anchor-oauth-bounce.vercel.app/oauth/zoom`, matching
> `ZoomOAuthConfig.bounceURL` character for character; **Use Strict Mode for
> Redirect URLs** off; **Subdomain Check** off. Note that Zoom's own generated
> *OAuth URL* on that page uses the **confidential** id — so the console will
> hand you the wrong one for a PKCE flow if you copy it.
>
> **Do not turn this toggle off.** `OAuthClientDefaults.zoomPublicClientID` is
> shipped and `ZoomOAuthConfig.effectiveClientID` selects it whenever no secret
> is provisioned, which is every install a teacher gets. Turning it off breaks
> Connect Zoom for all of them, and breaks it *after* the consent screen.

---

## 2b. Create the Server-to-Server app (optional, for the bot)

Still needed for the in-meeting bot, which signs in as its own robot account
rather than as a teacher, and for reading an account's meetings with nobody
signed in.

1. <https://marketplace.zoom.us> → **Develop → Build App → Server-to-Server OAuth**.
2. Copy the **Account ID**, **Client ID** and **Client Secret**.
3. Add these scopes, then **Activate** the app:

| Purpose | Classic scope | Granular scope |
|---|---|---|
| Verify connection, identify host | `user:read:admin` | `user:read:user:admin` |
| Mint the bot's ZAK (Meeting SDK join) | `user:read:admin` | `user:read:token:admin` |
| Find the live meeting | `meeting:read:admin` | `meeting:read:list_meetings:admin` |
| Live participants (Dashboard) | `dashboard_meetings:read:admin` | `dashboard:read:list_meeting_participants:admin` |
| Post-meeting participant report | `report:read:admin` | `report:read:list_meeting_participants:admin` |

Granting **none of these but `meeting:read:meeting:admin`** is the default for a
freshly created app, and it is not enough for anything — `/users/me` fails, so
Anchor cannot even verify the connection. Add every row above, then click
**Activate** again; scope changes do not apply to already-issued tokens.

> A missing scope comes back as **HTTP 400 with code 4711**, not 403, and the
> message names the exact scope required. Anchor parses that and surfaces it as
> `insufficientScope` rather than retrying — see `ZoomService.scopes(fromScopeError:)`.

> The Dashboard (`/metrics`) endpoints require a **Business, Education or
> Enterprise** plan. On Pro or Free, Anchor gets a 403 and reports
> `planRequired` — it keeps running on the signals that are available.
>
> On the account these apps live on today the plan bites a step earlier than
> that: the last two rows of the table above cannot be granted at all, because
> the Marketplace scope picker lists no Dashboard and no Report category to pick
> them from (§2a). A 403 is what you get on a plan that has the scopes and not
> the entitlement; here there is nothing to send.

## 3. Connect

**Anchor → Settings (⌘,) → Zoom connection → Connect Zoom.** The browser opens,
the teacher signs in, and Zoom redirects to `http://127.0.0.1:51789/oauth/zoom`,
which `LoopbackRedirectListener` catches on a one-shot local HTTP listener and
hands back to the app. Nothing is typed, and Anchor reconnects on every
subsequent launch from the Keychain.

The Server-to-Server credentials (Account ID / Client ID / Client Secret) now
live under **Advanced** in the same panel. They are optional and only needed for
the bot or for account-wide reads.

> A stale build can still be the one racing for the redirect if two copies of
> Anchor are running at once — quit any old instance before testing a fresh
> sign-in, otherwise the callback may land in the wrong process's listener or
> hit a socket already bound to port 51789.

### Or provision from the environment (one time)

```bash
# Launch the executable directly — `open` does NOT pass environment
# variables through to the app.

# The General app teachers sign in with (§2a). Only needed where
# OAuthClientDefaults was left blank.
ANCHOR_ZOOM_OAUTH_CLIENT_ID='…' \
ANCHOR_ZOOM_OAUTH_CLIENT_SECRET='…' \
# The Server-to-Server app (§2b), for the bot.
ANCHOR_ZOOM_ACCOUNT_ID='…' \
ANCHOR_ZOOM_CLIENT_ID='…' \
ANCHOR_ZOOM_CLIENT_SECRET='…' \
  /path/to/Anchor.app/Contents/MacOS/Anchor
```

The values are written to the Keychain on that launch and are not needed again —
do not put them in a shell profile, a script committed to the repo, or a
`.env` file.

Anchor is **live by default** once credentials exist. `ANCHOR_NO_AUTOCONNECT=1`
stops it connecting at launch. If Zoom can't be reached, the dashboard stays
empty and shows the reason — there is no fallback data (see §6).

Credentials go to the Keychain — the teacher's browser sign-in under
`com.anchor.zoom.oauth`, the Server-to-Server pair under
`com.anchor.zoom.credentials`, both with
`kSecAttrAccessibleAfterFirstUnlock`. They are never written to UserDefaults, a
plist, a log line, or source. Only the last four characters of the secret are
ever displayed, and no token is ever logged.

**Never hardcode credentials.** If you need them in CI, inject them at runtime
and write them to the Keychain on first launch — do not add them to
`Constants.swift`, which holds non-secret configuration only.

### Who the bot joins as (2026-08-08)

**"Yes, monitor" does not need Server-to-Server credentials.** A pilot cannot
ask every teacher to register their own S2S app, so the join runs off whatever
Zoom identity is already present. Two credentials are involved, and only one is
per-teacher:

| | What it does | Where it comes from |
|---|---|---|
| **Meeting SDK Key/Secret** | Authenticates *Anchor* to the Meeting SDK | App-level, same for everyone. Key ships in `OAuthClientDefaults.meetingSDKKey`; secret lives in the Keychain (`com.anchor.zoom.meetingsdk`) |
| **Account identity → ZAK** | Decides *who* the bot joins as | The teacher's own browser sign-in. `ZoomViewModel.makeLiveService()` already prefers it over S2S |

So a teacher clicks **Connect Zoom**, signs in, and that is the whole setup.
`joinBotUsingStoredCredentials` mints the ZAK from their grant — the
`user:read:zak` scope in §2a exists for exactly this — and the bot joins as
them. The Server-to-Server pair remains supported as a fallback for a school
that wants a dedicated robot account, but is no longer required.

Both preconditions are checked *before* the bot is built, so a missing
credential reports `missingSDKCredentials` or `notSignedIn` by name. Previously
the completeness check looked only at `accountID`/`clientID`/`clientSecret` and
never at `sdkKey`, so the one field that was actually missing was the one field
nothing validated — and the join failed several steps later inside `sdkAuth`,
which is indistinguishable from a malformed token.

The Meeting SDK app is a **third** Marketplace registration, separate from the
browser sign-in app in §2a and the Server-to-Server app in §2b. It needs
**Embed → Meeting SDK** on, plus *"Are you developing a programmatic join use
case?"*. Provision its secret once:

```bash
# Copy the Client Secret from the Meeting SDK app in the Marketplace, then:
./scripts/provision-zoom-sdk-secret.sh
```

That reads the clipboard and hands the value to the app, which writes it to the
Keychain — it is never echoed, written to a file, or left in shell history.

### The bot's credentials

The bot's own account is a separate Keychain entry
(`bot-server-to-server-oauth`) holding its S2S OAuth pair *and* its Meeting SDK
Key/Secret. **The Keychain is the only copy** — nothing in source holds a
literal secret.

This used to be seeded on every launch from a hardcoded
`Anchor/Utils/BotCredentials.swift`. That file was deleted on 2026-08-07, along
with the `seedBotCredentialsIfNeeded()` path in `KeychainStore.swift`, after the
Client Secret was rotated in the Marketplace and the new value written to the
Keychain. Do not reintroduce a source-level seed.

To provision the bot on a fresh Mac, or after another rotation, call
`ZoomCredentialsStore.shared.saveBot(_:)` with the new values from a one-off
debug action. A rotation that isn't written to the Keychain fails with
`invalid_client` against the stale stored copy.

---

## 4. What Zoom actually exposes

This is the most important section, and it differs from the original spec.

### Authentication: OAuth, not JWT

Zoom **retired JWT apps in June 2023**. Server-to-Server OAuth does not sign a
JWT locally. Anchor POSTs to `zoom.us/oauth/token` with
`grant_type=account_credentials`, HTTP Basic `client_id:client_secret`, and gets
a bearer token valid ~1 hour. `ZoomAuthenticator` caches it, refreshes 2 minutes
before expiry, collapses concurrent refreshes into one request, and re-auths once
on a 401.

### Signal availability

| Signal | REST API | Where it actually comes from |
|---|---|---|
| Participant ID, name, user ID | ✅ | `/metrics/.../participants` |
| Join / leave time | ✅ | same |
| In-meeting status | ✅ | same |
| Device, sharing, QoS | ✅ | same |
| Meeting ID, topic, start, duration, count | ✅ | `/users/me/meetings`, `/meetings/{id}` |
| **Mute state (`is_muted`)** | ❌ | Meeting SDK or webhooks |
| **Camera state (`has_video`)** | ❌ | Meeting SDK or webhooks |
| **Hand raised** | ❌ | Meeting SDK or webhooks |
| **Time unmuted / speaking seconds** | ❌ | Meeting SDK |
| **Audio level per participant** | ❌ | Meeting SDK (raw audio) |
| **In-meeting chat** | ❌ | Cloud recording `chat_file`, post-meeting only |

Every ✅ in the first four rows presumes the Dashboard participant scope, which
the app does not currently hold and cannot be granted on this account (§2a). On
such an account the REST column collapses to the meeting-level row alone, and
the bot is the only path to a roster, never mind to the ❌ rows.

The Dashboard payload has `microphone` and `camera` fields, but those name the
**device** ("MacBook Pro Microphone"), not whether the person is muted. Anchor
deliberately does **not** map them to `isMuted`/`hasVideo` — that would
manufacture a signal.

Unavailable signals are `nil` on `ZoomParticipant`, never `false`. A defaulted
`false` would read as "unmuted and engaged" and silently corrupt every score.

### Consequence: confidence

With REST only, roughly **25%** of the scoring model is covered (presence). So:

- `StruggleScoreCalculator.calibratedScore` shrinks the raw score toward 0.5 in
  proportion to confidence. Without this, every student scored ~2% — the
  dashboard would have told a teacher the whole class was thriving on no evidence.
- Below 40% confidence, `Student.hasReliableScore` is false and the UI shows
  **"—"** with a hollow grey dot instead of a percentage and a traffic light.
- Settings lists exactly which signals are missing.

To get the full signal set you need a **Meeting SDK** app running inside the
meeting, or **webhook** subscriptions. Both drop into `ZoomDataProviding`
without touching the dashboard.

---

## 5. Architecture

```
Anchor/
  Models/ZoomModels.swift          domain models, wire DTOs, ZoomError, capabilities
  Utils/Constants.swift            endpoints, intervals, scopes  (no secrets)
  Utils/KeychainStore.swift        Keychain wrapper + ZoomCredentials(Store)
  Utils/ZoomAuthenticator.swift    S2S OAuth token cache/refresh   (actor)
  Services/ZoomService.swift       REST client, retry, throttle    (actor)
  Services/MeetingBot.swift        SDK JWT + in-meeting bot adapter (actor)
  Services/CallDetector.swift      local "you're in a call" detection
  Services/MeetingNotifier.swift   the connect prompt
  Services/StruggleScoreCalculator.swift   signals → score + confidence
  Services/ZoomStudentMapper.swift         ZoomParticipant → Student
  Services/ZoomViewModel.swift     polling loop, connection state  (@MainActor)
  Data/EngagementStore.swift       .ingest(...) merges live data into the dashboard
```

Data flow:

```
launch → credentials from Keychain → OAuth token
       → GET /users/me                    (verify)
       → GET /users/me/meetings?type=live (find the class)
       → GET /metrics/meetings/{uuid}/participants?type=live
       → StruggleScoreCalculator + ZoomStudentMapper
       → EngagementStore.ingest(...)      → popover + window update
       → sleep(refresh interval) → repeat
```

`ZoomDataProviding` is the seam. Swap in a Meeting-SDK-backed or webhook-backed
implementation and nothing above it changes.

### Reliability

- **Polling**: the Settings interval (default 2 min), floored at 30s.
- **Backoff**: 15s → 30s → 60s → 120s → 300s with 20% jitter; reset on success.
- **Rate limits**: `Retry-After` honoured; Dashboard calls throttled to one per
  7.5s minimum.
- **401**: token invalidated and retried once, then surfaced as `invalidCredentials`.
- **Terminal errors** (bad credentials, missing scope) stop the loop instead of
  burning quota — `ZoomError.requiresUserAction`.
- **Pagination**: `next_page_token` followed up to 10 pages × 300 records.
- **Meeting UUIDs** beginning with `/` or containing `//` are double
  URL-encoded, as Zoom requires.

---

## 6. No fallback data

Anchor contains **no generated, demo or mock data**. If Zoom has not delivered a
roster, the dashboard is empty and states why — "Waiting for a meeting",
"Zoom disconnected", "Connect Zoom" — with the underlying error and what to do
about it.

This is deliberate. A dashboard that invents students is worse than one showing
nothing, because a teacher can act on it. The store starts empty, `clear()` drops
the roster when a meeting ends or the connection fails, and nothing ever
synthesises a `Student`.

Consequence to be aware of: until the Meeting SDK framework is linked, or you
host a meeting on an account whose plan exposes the Dashboard API, the app will
show the empty state permanently. That is accurate, not broken.

Launch switches (see `AppDelegate.configureDataSource`):

```bash
ANCHOR_NO_AUTOCONNECT=1     # don't connect at launch
ANCHOR_ZOOM_ACCOUNT_ID / _CLIENT_ID / _CLIENT_SECRET   # one-shot provisioning
```

## 7. Call detection → notification → bot

Anchor watches locally for Zoom calls and offers to send a bot in. This is the
only path that yields real engagement signals, because mute/camera/hand-raise
are in-meeting client state.

```
CallDetector  (CptHost process + CoreAudio input-is-live, 5s poll,
               2 consecutive positives before firing)
   → MeetingNotifier  "Zoom call detected — connect Anchor?"  [Yes, connect] [No]
   → Yes → ZoomViewModel.connectToDetectedCall()
            ├─ host?  REST finds the live meeting number automatically
            └─ guest? Settings asks for the meeting number
   → MeetingBotProviding.join(...)
   → bot participants replace REST as the data source (full signal set)
```

Detection reads a CoreAudio **device property** (`DeviceIsRunningSomewhere`) —
no microphone permission, no audio opened or captured. "No" suppresses the
prompt until the call ends.

### Finishing the bot

`MeetingBotProviding` has two implementations:

- **`ZoomMeetingSDKBot`** — the only implementation. `join()` splits into two
  halves:

  - **`prepareJoin(_:)` — works today.** It signs the bot into its own Zoom
    account over S2S OAuth, normalises the meeting number to bare digits, signs
    the Meeting SDK token (HS256 HMAC, cross-checked against an independent
    implementation), and mints a **ZAK** via
    `GET /users/{userId}/token?type=zak` so the SDK can join *as the bot's Zoom
    user* rather than an anonymous guest. The result is a
    `MeetingSDKJoinContext` carrying everything `joinMeeting` needs.

    The ZAK fetch is deliberately non-fatal: an open meeting accepts a guest
    join, so a failed fetch degrades to `zak == nil` instead of blocking.

  - **`connect(_:)` — throws until the framework is linked.** To finish it:

  1. Marketplace → Build App → **Meeting SDK** → note the SDK Key/Secret
     (a *different* pair from the S2S OAuth Client ID/Secret).
  2. Download the Zoom Meeting SDK for macOS; add `ZoomSDK.framework`
     (Embed & Sign).
  3. Set `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT` and `..._CAMERA`, add usage
     strings — the SDK needs mic/camera even for an observer bot.
  4. Replace the body of `connect(_:)` with SDK auth using `context.sdkToken`,
     then `joinMeeting` passing `context.zak`, and return a `BotSession` from
     the join callback.
  5. Map SDK participant callbacks into `ZoomParticipant`, filling `isMuted`,
     `hasVideo`, `handRaised`, `audioLevel`. Leave any signal the SDK does not
     report as `nil` — never default it to `false`.

### Things to decide before shipping the bot

- The bot **appears as a participant** in the meeting. Students will see it.
- A host may need to **admit it from the waiting room**.
- Raw audio access requires Zoom **ISV approval**; participant metadata does not.
- Students being scored by a bot in the room is a consent/disclosure question,
  not just a technical one.

## 8. Not implemented

- **Meeting SDK.** Requires embedding Zoom's binary framework and having the
  teacher join through Anchor. This is the only way to get mute, camera,
  hand-raise and audio levels live.
- **Webhooks.** `meeting.participant_joined` / `_left` would replace polling with
  push, but need a public HTTPS endpoint — a server component, not a menu bar app.
- **Live chat.** Not available over REST during a meeting (see above).
