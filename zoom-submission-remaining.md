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

### Answered 2026-08-21: why Publish says "Not ready"

The page opened this time (the Marketplace session had lapsed; `zoom.us/profile`
loaded fine, and re-visiting the console URL after that completed the handshake
without a password). **Publish lists eighteen missing required fields, not one
diagram.** Verbatim, under *"The following fields are required to submit your
app"*:

| Section | Missing |
|---|---|
| App Listing - App Information | **4** |
| App Listing - Links & Support | **4** |
| App Listing - EU & Discoverability | **9** |
| Technical Design | **1** |

**Field values below were read out of `input.value` / `input.checked`, not off a
screenshot** — the same reason the "allow list looked empty" misread happened.
Note the trap that cost a wrong reading here first: for a checkbox `e.value` is
the literal string `"on"` whether or not it is ticked, so a probe that prints
`value` reports every checkbox as set. Read `.checked`.

**Technical Design (1) is the diagram, exactly as this file says.** Overview
4/5, Security 3/3, re-read 2026-08-21. That part of the file was right.

**The other seventeen are new information, and two of them contradict the *Done*
table at the bottom of this file.** See the correction under it.

- **Links & Support (4)** — Privacy Policy URL **empty**, Terms of Use URL
  **empty**, Documentation URL **empty**, and the attestation checkbox *"This
  page includes language informing users of their data subject rights and how to
  exercise them"* **unticked**. Only Support URL is filled
  (`https://anchorteach.vercel.app/support`). **Checked on the Development tab
  too, and it is identical there** — so this is not a "recorded the wrong tab"
  error, the two URLs were never entered in either mode. Both pages exist and
  are live, so this is four minutes of typing, not a blocker.
- **App Information (4)** — Long Description **0/2000**, and the App Icon still
  renders Zoom's default placeholder. Cover Image and App Gallery are also
  empty; App Name, Company Name, Short Description (97/150), category and
  industry are filled. That is the likely four.
- **EU & Discoverability (9) is the one that changes the plan.** See below.

### The EU trader block, and why it is not a typing job

The nine are Digital Services Act trader disclosures, gated behind an
**"Available in the EU" switch that is ON** (read as a MUI `Mui-checked`
switch, not inferred from styling):

1. Business name
2. Business address
3. Business email address
4. Business telephone number
5. Last 4 digits of **business bank account number**
6. **Trade Register Number (DUNS or similar)**
7. Bank name
8. **Identification document of the trader** — *"10K form, articles of
   incorporation, or similar registration"*, uploaded
9. A declaration that the trader offers only union-law-compliant products

**Five through eight cannot be produced by an individual with no registered
company.** Company Name on the listing is currently `Rishab Reddy Paili`, which
is the honest answer and also the one with no DUNS number and no business bank
account behind it. So on the current reading, publication as it stands demands
either a registered entity or that switch turned off.

**The switch is the decision.** Turning "Available in the EU" off very probably
drops all nine — the fields are rendered underneath it and the count matches
exactly — which would take Publish from eighteen missing to nine. For a US
homeschool-co-op pilot starting 31 Aug, EU availability is worth nothing this
term. But it is a change to what markets the listing is offered in, made on a
live console, and it is reversible only in the sense that flipping it back is
easy — the submission it feeds is not.

### Decided 2026-08-21: leave it on, and park the publication path

Put to Rishab, who delegated the call back. **Not flipped, and the reason is
that flipping it is motion rather than progress.**

**Publication cannot help the 31 Aug pilot under any branch, so nothing on this
page is on the critical path.** Three independent reasons, each sufficient on
its own:

1. **Apple Developer enrollment sits upstream of everything.** The app is
   ad-hoc signed with no team identifier, so *nobody can install Anchor at all*,
   published Zoom app or not. Publication would deliver a Marketplace listing
   for software no teacher can run.
2. **Review takes weeks and this app draws the stricter queue** — Education
   plus K-12, per Zoom's own warning quoted below. There are ten days.
3. **Per-teacher has no live signal even after publication**, which is the
   reason to want it in the first place. The Meeting SDK secret cannot ship
   (HS256, signed locally), so an unprovisioned install has no bot; the
   participant scopes are ungrantable on Basic; and Basic caps a meeting at 40
   minutes. Publication removes the distribution limit and leaves all three.

**So the honest position is not "publication is nine fields away once the switch
is off". It is that publication may never be the right route at all**, and a
setting changed on a live listing for a path nobody has chosen is a setting
nobody remembers changing. The evidence that the switch gates the nine is
already recorded above and does not decay; re-deriving it costs one page load,
which is cheaper than carrying an unexplained console change.

**If publication is ever pursued, this is step one and it is one click.** Flip
"Available in the EU" off and re-read the Publish page — **the count is the
check, and it should fall from eighteen to nine.** Do that *before* writing any
App Listing copy, because the copy is four minutes and the trader block is a
company registration.

**One more thing read on the way past, unprompted and worth knowing before this
route is chosen.** The App Listing page carries Zoom's own warning next to the
industry picker: *"The 'Education' Market Vertical has additional review
requirements, and should only be selected for apps which are used in K-12 &
Higher Education environments."* Anchor has Education **and** K-12 selected.
That is accurate for what Anchor is, so it should stay — but it means the
publication review is the stricter one, which is an argument for the per-school
route rather than against the selection.

**The small inconsistency is still there and still unresolved:** the right panel
said "Ready for beta test" again on 2026-08-21, on every page of the console,
while Overview is 4/5 and the 13 Aug note below says **Request to Share** only
becomes clickable after the upload. It sits beside the sidebar's *Publish: Not
ready*, so the two panels are answering different questions — beta readiness and
publication readiness — and the right panel is the beta one. That resolves the
contradiction rather than the staleness; whether **Request to Share** is
genuinely clickable at 4/5 was not tested, because clicking it spends a review
cycle and this file already argues against aiming there at all.

---

**"Everything is filled in except one file upload" was true of Beta Test, and is
false of publication** — see the 2026-08-21 correction above, which found
seventeen more required fields. The upload below is still needed and still has
to be done by hand; it is just no longer the last thing.

Drag
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
| App Listing | ~~Complete~~ — **wrong, corrected 2026-08-21.** Company, Short Description, category (Learning & Development) and industry (Education) are filled; **Long Description, App Icon, Cover Image and App Gallery are empty** |
| Link & Support | ~~Privacy, Terms, and Support URLs~~ — **wrong, corrected 2026-08-21. Only the Support URL (`/support`) is entered.** Privacy Policy, Terms of Use and Documentation URLs are empty in *both* Development and Production |
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
