# Zoom submission — read the correction first, the target has changed

State as of 2026-08-13, **corrected 2026-08-20 after checking the console and
Zoom's own docs. The goal this file describes is the wrong one.**

---

## Correction: stop aiming at Beta Test. Aim at publication.

This file says "one step left" and that step is an upload. Both halves are
misleading now.

**1. Beta Test would very likely be refused, and this file records why in its
own last table.** The console page says, verbatim: *"Kindly note that submission
of supporting security evidence is mandatory for beta testing."* The answers
given on 13 Aug were **No** to Secure SDLC, **No** to SAST/DAST, and **No** to
third-party penetration testing. Zoom's requirements for an independent
developer's Beta URL are exactly those items: mandatory SSDLC evidence, SAST or
DAST results and a privacy policy, **plus three of** penetration test summary,
security policy, incident management policy, vulnerability management
procedures, or infrastructure and dependency management policy. Clicking
**Request to Share** with three No answers spends a review cycle to be told that.

**2. Publication does not need any of it.** Zoom's own forum post for
independent developers: *"participation in Beta is optional. Your app can still
qualify for publication in our Marketplace without supporting evidence."* And
Beta expires anyway, 4 weeks standard and 12 weeks maximum, which is shorter
than a school term, so a term-long pilot on a Beta URL stops mid-pilot.

**So the diagram upload is still needed** (it is part of Technical Design, which
publication also requires) **but the button to press afterwards is Publish, not
Request to Share.**

### Console state, read 2026-08-20

| Thing | State |
|---|---|
| Production Client ID | `Vgi566QtQhaoeAOptZpqug` — matches what the repo records |
| Technical Design → Overview | **4/5**, Architecture Diagram upload box still empty |
| Technical Design → Security | **3/3** |
| Right-hand panel | "Ready for beta test" |
| Beta Test → Share within your account | **ACTIVE** |
| Beta Test → Share outside your account | **LIMITED**, with a **Request to Share** button present |
| Sidebar → Beta Test | "Local only" |
| Sidebar → Publish | **"Not ready"** |

**Unverified, and it is the one thing worth checking next:** *why* Publish says
"Not ready". The browser extension disconnected before that page could be
opened, so nothing here should be taken as a claim about what publication is
still missing beyond the diagram. Open
`/develop/applications/UcNDw-l5QkWaeKEOvXfXhA/publish?mode=prod` and read it.

**Also note a small inconsistency, unresolved:** the right panel says "Ready for
beta test" and **Request to Share** appears present, while Overview is 4/5 and
the 13 Aug note below says the button only becomes clickable after the upload.
One of those is stale. Read the page rather than either sentence.

---

**Everything is filled in except one file upload.** Drag
`zoom-architecture-diagram.png` (repo root) onto the Architecture Diagram
**Upload** box here:

<https://marketplace.zoom.us/develop/applications/UcNDw-l5QkWaeKEOvXfXhA/technical-design/application_overview?mode=prod>

Then click **Continue**, go to **Beta Test**, and **Request to Share** will be
clickable. That sends the request to Zoom's review team.

Why it has to be done by hand: uploading through browser automation attaches the
file (the counter moves to 5/5) but it never commits server-side — it is gone on
reload. Tried four times, as both PDF and PNG, so it is the upload mechanism
rather than the file. Both formats are in the repo root; either will do.

---

## Done

| Section | State |
|---|---|
| App name | **Anchor** |
| App Listing | Complete — company, descriptions, category (Learning & Development), industry (Education) |
| Link & Support | Privacy, Terms, and Support (`/support`) URLs |
| Basic Information | Contact name + email, production OAuth Redirect URL + allow list |
| Scopes | Scope description written |
| Technical Design → Security | **3/3** |
| Technical Design → Overview | **4/5** — only the diagram missing |
| Beta Test | "Share within your account" **ACTIVE**, Authorization URL generated |

## Website changes, deployed and verified live

- **Governing law filled in.** `terms.tsx` now names the Commonwealth of
  Massachusetts, and the courts clause names Massachusetts state and federal
  courts generally rather than a county — no county was given, and a general
  clause is valid and slightly broader. Narrow it to a county if you prefer.
- The internal `<mark>` note ("the two fields above are the last ones
  outstanding… not been reviewed by an attorney") was removed from the public
  page. It was a TODO to yourself, and publishing it would undercut the terms.
  **The advice still stands: have counsel review these before a school pilot.**
- **`/support` page added** (`src/routes/support.tsx`) — contact address, what to
  include in a report, the common failure modes, and an explicit "do not email
  student data" section. Added to `scripts/sitemap.mjs` and the sitemap
  regenerated.
- `LEGAL_LAST_UPDATED` bumped to August 13, 2026.

## Answers given on your behalf, in case Zoom queries them

| Question | Answer | Basis |
|---|---|---|
| TLS 1.2+ for all network traffic? | **Yes** | No ATS exceptions in Info.plist; the only `http://` in source is the loopback listener |
| Webhook events verified via token / x-zm-signature? | **No** | Anchor has no webhooks and no server |
| Collects/stores/retains Zoom user data incl. OAuth tokens? | **Yes** | Keychain tokens + local JSON archive; at-rest detail written in the follow-up box |
| Secure SDLC (SSDLC)? | **No** | Your answer |
| SAST / DAST? | **No** | Your answer — note you only said "no" to SSDLC and pen testing; this third question appeared on the same panel and was answered consistently. Change it if that is wrong. |
| 3rd-party penetration testing? | **No** | Your answer |
