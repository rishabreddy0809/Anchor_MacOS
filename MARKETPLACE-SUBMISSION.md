# Anchor — Zoom Marketplace publication

Everything needed to submit the **Anchor** General app for Marketplace
publication, assembled so the submission itself is form-filling rather than
research. Publication is what unlocks the per-teacher account model; the
per-school route (`ADMIN-SETUP.md`) needs none of this and works today.

> **Read `ZOOM_INTEGRATION.md` §2 first if you are deciding *whether* to do
> this.** The short version, from the 2026-08-20 correction: **publish, do not
> Beta.** Beta demands a Secure SDLC evidence pack, SAST/DAST results and three
> of five security policies, expires at 12 weeks — shorter than a school term —
> and carries a publicity ban. Publication requires none of that; Zoom does the
> security testing themselves against the OWASP Top 10.

---

## Before you open the console

- **Account Owner or Admin** privileges on the Zoom account that owns the app.
  No plan tier is named anywhere in Zoom's publication requirements — Basic is
  not a stated barrier.
- **Identity.** Zoom accepts a government-issued ID in place of business
  registration for sole proprietors. Publishing means entering the **Marketplace
  Developer Agreement**, which is a contract: if the developer is under 18, the
  account and the submission need to sit with a parent or guardian. Arranging
  that first costs nothing; discovering it at review costs a cycle.

---

## 1. The Production credential trap — do this before anything else

**This is the single most expensive thing on the page, because it fails after a
teacher has already approved Anchor.**

Publication moves teachers onto **Production** credentials, and the Production
tab is not a copy of Development:

- **The public-client toggle is OFF on Production, so no Public Client ID exists
  there at all.** Enabling it mints a **third** identifier — different again
  from the shipped Development one.
- `OAuthClientDefaults.zoomPublicClientID` currently ships
  `kzU8QEfESJKsvxA3EzCe9A`, which is the **Development** public client. Shipping
  that against Production fails the token exchange the same way the confidential
  id did, and fails it *after* consent.
- Zoom's own generated **OAuth URL** on that page is built with the
  **confidential** id, so copying it hands you the wrong one for a PKCE flow.
- The **Meeting SDK app** has its own Development/Production split too. Its
  Production Client ID/Secret are what `ZOOM_MEETING_SDK_KEY` /
  `ZOOM_MEETING_SDK_SECRET` must become on the Vercel deployment.

**Do not turn the Development public-client toggle off.** Every install a
teacher has today selects it whenever no secret is provisioned.

### Redirect registration, both fields

```
https://anchor-oauth-bounce.vercel.app/oauth/zoom
```

Into **OAuth Redirect URL** *and* the **OAuth allow list**, on the Production
tab. Zoom matches character for character — no trailing slash. Setting only one
is the most common failure and reports an unhelpful `Invalid redirect URL`.

> Why an HTTPS bounce rather than loopback: Zoom will not honour an `http://`
> numeric-loopback redirect. Its form stores one; the OAuth service never
> accepts it. The page at that URL forwards to `anchor://oauth/zoom` and is
> served from `Web/oauth-zoom-bounce.html`.

---

## 2. Scopes, and the justification for each

Zoom's authorize endpoint takes no `scope` parameter — scopes are fixed on the
app, and Anchor *verifies* what came back rather than requesting it. Reviewers
ask why each is needed; these are the answers.

| Scope | Why Anchor needs it |
|---|---|
| `meeting:read:list_meetings` | Find the class that is currently running. Anchor has no meetings of its own. |
| `user:read:user` | Identify the signed-in teacher, so the dashboard can say which account it is reading and so the teacher is excluded from their own class roster. |
| `user:read:zak` | Mint the token the in-meeting assistant joins with, so it joins **as the teacher** rather than as an anonymous guest. |
| `dashboard:read:list_meeting_participants:admin` | Read who is in the meeting and their participation state. **Gated by Zoom on Business/Education/Enterprise.** |
| `report:read:list_meeting_participants:admin` | Same data after the meeting ends, for the session record. **Same plan gate.** |

**State plainly in the listing that the last two are optional.** A teacher on
Basic or Pro cannot grant them — the scope picker does not offer the categories
— and Anchor is designed to degrade to the in-meeting assistant as its only
live signal in that case.

---

## 3. Technical Design

### Architecture

Anchor is a **macOS desktop application**. There is no Anchor server holding
class data — the analysis runs on the teacher's Mac, and the only backend
component is a stateless token-signing endpoint described below.

```
Teacher's Mac                          Zoom
─────────────                          ────
Anchor.app
  ├─ OAuth (PKCE, no secret) ────────► zoom.us/oauth/authorize
  │     ↳ redirect via HTTPS bounce ──► anchor://oauth/zoom
  ├─ REST polling ───────────────────► api.zoom.us/v2
  ├─ Meeting SDK (in-meeting bot) ───► Zoom meeting
  └─ Core ML scoring  ── stays local, never transmitted

anchorteach.vercel.app
  └─ POST /api/zoom/sdk-token  ── signs the Meeting SDK JWT only
```

### Security controls

- **OAuth 2.0 authorization code + PKCE.** The shipped client is a **public
  client**; no client secret is embedded in the binary. PKCE (`S256`) is what
  proves the request is Anchor's.
- **`state` is generated per request and verified on return.** A mismatch is
  rejected before the code is redeemed.
- **Tokens live in the macOS Keychain** (`kSecAttrAccessibleAfterFirstUnlock`),
  scoped per signed-in Anchor account. Never in preferences, a file, or source.
- **Refresh tokens rotate.** Zoom invalidates the used token on every refresh;
  Anchor persists the rotated pair to the Keychain *before* handing the new
  access token to any caller, so a crash mid-refresh cannot orphan the grant.
- **TLS 1.2+** for every request; `URLSession` defaults, no certificate or ATS
  exceptions.
- **Disconnect revokes.** Signing out of Zoom calls Zoom's revoke endpoint and
  deletes the stored grant.

### The Meeting SDK signing endpoint

The Meeting SDK JWT is signed **HS256 with the SDK secret**, so the secret is a
signing key rather than an identifier — embedding it in a shipped binary would
let anyone who extracts it mint tokens as Anchor. It therefore lives in the
server environment and is never distributed.

- `POST https://anchorteach.vercel.app/api/zoom/sdk-token`
- **Authorised with the caller's own Zoom access token**, which the server
  verifies against `api.zoom.us/v2/users/me` before signing anything. Anyone
  entitled to run the assistant has necessarily authorised Anchor's Zoom app, so
  a live Zoom grant proves exactly the right entitlement.
- **Per-teacher rate limiting**, keyed by Zoom user id rather than IP so that
  teachers sharing a school's outbound address are not throttled as a group.
- **Nothing else crosses the wire.** No roster, no scores, no transcript, not
  even a meeting number — the native macOS SDK token authenticates the *app*,
  so the claim set is `appKey` / `iat` / `exp` / `tokenExp` and nothing more.
  The Zoom token is used for verification and never stored.
- A deployment that provisions its own SDK secret signs **locally** and never
  contacts this endpoint.

### Data handling

- **Student data never leaves the teacher's Mac.** Rosters, participation
  signals, engagement scores and session history are stored locally and are
  never transmitted to Anchor or any third party. This is the claim the live
  privacy policy makes, and the app is built to keep it.
- **No recordings.** No video is analysed and no meeting recording is made.
- **The in-meeting assistant is visible**, named
  *"Anchor (engagement assistant)"* in the participant list. It is never hidden.
- **Retention is teacher-controlled** — 120 days, 365 days, or until deleted —
  and enforced locally on every launch.

---

## 4. Listing fields

| Field | Value |
|---|---|
| App name | `Anchor` — set on **App Listing**, not the pencil beside the page header. The consent screen shows this string verbatim. |
| Privacy Policy URL | `https://anchorteach.vercel.app/privacy` ✅ live |
| Terms of Use URL | `https://anchorteach.vercel.app/terms` ✅ live |
| Support URL | `https://anchorteach.vercel.app/support` ✅ live |
| Developer contact | Recorded in `ZOOM_INTEGRATION.md`; confirm it is current before submitting. |
| Market vertical | **Education / K-12** |

> **The market vertical costs you something and should stay anyway.** Zoom's own
> wording on the App Listing page: *"The 'Education' Market Vertical has
> additional review requirements, and should only be selected for apps which are
> used in K-12 & Higher Education environments."* It is accurate for Anchor, so
> it stays — but it means the stricter review, which is a further argument for
> running the per-school route in parallel rather than waiting on this.

---

## 4b. Ready-to-paste copy

### Technology Stack — **the version in the console is now wrong**

The Technical Design → Technology Stack field is already filled, and it says:

> *"There is no backend service, no database and no hosted infrastructure other
> than a single static redirect page."* … *"one static HTML page on Vercel
> serving only as the OAuth redirect target … and stores nothing."*

**That stopped being true on 2026-08-25** and was made live on 2026-08-28.
`POST /api/zoom/sdk-token` on `anchorteach.vercel.app` now receives a Zoom
access token, verifies it against Zoom, and signs a Meeting SDK JWT with a
secret held in the server environment. Submitting the old text would describe an
architecture that does not exist, in the one section Zoom reviews for security.
Replace the two hosted-components paragraphs with this:

> **Hosted components:** two, both on Vercel, neither holding user data.
>
> (1) A static HTML page that serves only as the OAuth redirect target. It
> forwards the authorization code and state to a loopback listener on the user's
> own machine and stores nothing. It exists because Zoom does not honour an
> `http://` loopback redirect.
>
> (2) A stateless token-signing endpoint, `POST /api/zoom/sdk-token`. The Zoom
> Meeting SDK authenticates the application with an HS256 JWT signed by the SDK
> secret; that secret is a signing key rather than an identifier, so it is held
> in the server environment and never distributed in the client. The endpoint is
> authorised with the caller's own Zoom access token, which it verifies against
> `api.zoom.us/v2/users/me` before signing anything — every user entitled to run
> the in-meeting assistant necessarily holds a live Zoom grant, so this proves
> exactly the right entitlement. Requests are rate limited per Zoom user id. No
> roster, engagement score, transcript or meeting number is sent to it; the
> native macOS SDK token authenticates the app rather than a meeting, so the
> claim set is `appKey`, `iat`, `exp` and `tokenExp` and nothing else. The Zoom
> access token is used for verification and is never stored.
>
> There is still no database, no analytics, no telemetry and no crash reporting.
> A deployment that provisions its own Meeting SDK secret signs locally and never
> contacts this endpoint at all.

### Architecture Diagram — the one missing Technical Design field

`Overview (4/5)` — the gap is the diagram upload. `zoom-architecture-diagram.png`
and `.pdf` exist at the repo root, **but they are dated 13 Aug and predate the
signing endpoint by twelve days.** Uploading either as-is contradicts the
corrected text above. Redraw with the second hosted component before uploading.

### Long Description (App Listing → App Information)

Zoom's own instruction on this field: *"Avoid jargon or exaggerated claims e.g.
'most secure' or 'most popular'."* Written to that, and to fit 2000 characters:

> Anchor helps a teacher see who is struggling during a live Zoom class, while
> there is still time to do something about it.
>
> In a room, a teacher reads the class constantly , who has stopped following,
> who is about to give up, who is quietly lost. Over video most of that
> disappears. Anchor gives some of it back.
>
> Once connected to Zoom, Anchor watches a class you have explicitly approved and
> builds a live reading for each student from how they are taking part: whether
> they are muted, whether their camera is on, whether they have raised a hand,
> how the pattern is changing as the lesson goes on. Students who look like they
> are drifting are surfaced during the lesson, not in a report afterwards.
>
> Teachers who connect Google Classroom also see each student's recent
> coursework, grades and missing work alongside the live reading, so a quiet
> student who is also three assignments behind stands out from one who is simply
> quiet today.
>
> Anchor runs on the teacher's Mac. Engagement readings, rosters and class
> history are analysed and stored on that machine and are not sent to us.
> Nothing is recorded: no audio, no video, no transcript of the class leaves the
> teacher's computer. The in-meeting assistant appears in the participant list as
> "Anchor (engagement assistant)" and is never hidden.
>
> Students install nothing and need no account. They join the class exactly as
> they always have.
>
> Anchor reads Zoom. It never posts, schedules, changes settings, or acts on the
> teacher's behalf. It can be disconnected from inside the app at any time, which
> revokes the connection with Zoom immediately.

---

## 5. Before you submit

- [x] **`ZOOM_MEETING_SDK_KEY` / `ZOOM_MEETING_SDK_SECRET` — done 2026-08-28.**
      Set on `anchor-landing` (Production) and the deployment redeployed.
      Verified live: unauthenticated `POST /api/zoom/sdk-token` returns
      `401 "Missing Zoom authorization."` and a bogus bearer returns
      `401 "That Zoom sign-in is no longer valid."` — the second proves the
      request reached Zoom's `/users/me` verification rather than merely passing
      a config check. **Rotate this secret**: it was pasted through a chat
      transcript, which `ZOOM_INTEGRATION.md` §1 treats as compromised.
- [x] **EU availability turned off — 2026-08-28.** App Listing → EU &
      Discoverability → *Available in the EU* is off, dropping Zoom's required
      field count from **18 to 9**. This removes the DSA trader verification
      entirely: business bank account digits, Trade Register / DUNS number, bank
      name, an identification document of the trader, and a declaration of
      compliance with union law. **EU users can no longer authorize the app** —
      revisit this only with an accountant, since it needs a registered
      business.
- [x] **Documentation URL page written — 2026-08-28.** `website/landing/src/routes/docs.zoom.tsx`,
      serving `/docs/zoom`; covers adding, using and removing the app, which is
      what Zoom asks that field for. Builds clean and the route is registered.
      **Not yet deployed to production** — see below.
- [ ] Production public-client toggle enabled, and its **new** id shipped in
      `OAuthClientDefaults.zoomPublicClientID`.
- [ ] Production redirect URL **and** allow list both hold the bounce URL.
- [ ] Consent screen reads `Anchor`, verified by looking at it.
- [ ] A teacher who is **not** the app owner completes Connect Zoom end to end.
      The owner succeeding proves less than it looks, because internal users
      authorise an unpublished app regardless.
- [ ] Identity/age arrangements settled for the Developer Agreement.
- [ ] **Deploy `/docs/zoom` to production**, then paste the four Link & Support
      URLs. Production serves from `main`; the page is committed nowhere yet and
      the working tree also holds the account-scoping work, so how it reaches
      `main` is a release decision rather than a mechanical step.
- [ ] Company Name, Long Description (draft in §4b), App Icon (160×160), Cover
      Image (1824×176) and Gallery (1200×780). The app's `DemoData` screenshot
      mode exists for the gallery.
- [ ] Replace the Technology Stack text and redraw the architecture diagram —
      both currently describe an app with no backend. See §4b.

---

*Written 2026-08-27. The architecture and security sections describe the app as
built; if either drifts, this file is wrong and a reviewer will find it before
you do.*
