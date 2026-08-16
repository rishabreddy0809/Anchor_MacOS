# Zoom Beta Test submission — one step left

State as of 2026-08-13.

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
