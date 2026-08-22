# Anchor — continue pilot readiness

Repo: `/Users/rishabreddypaili/Documents/Anchor`
Branch: `ship/pilot-readiness`; **default is `main`** since 2026-08-19
(`app-split` is retired — do not push it). **Both branches always point at the
same commit and are pushed** — `git log --oneline -1` for which one, because a
hash written here is stale the moment the commit writing it lands. Tests:
`xcodebuild test -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
→ **311 passing**, 21 test files. Release config builds clean.

Deadline: term starts ~31 Aug 2026. Goal is 1–3 real pilot users.

Three checklists must stay in step: `ship-checklist.md`, the Notion **Tasks**
database (under the *Anchor* page), and the Ship Readiness artifact
(https://claude.ai/code/artifact/44f67c4b-a54b-4c2c-af29-dce669095bea).
**The artifact is the one that silently rots** — it was a full day stale on
19 Aug while the other two were current. Its ticks are localStorage keyed on
`anchor-readiness-ticks-vN`; **bump N whenever you mark things done**, or a
returning browser keeps showing the old state forever. Currently `v22`
(47 of 72 ticked), bumped on 21 Aug for the privacy-policy done-item. It went v10 → v18 across 20 Aug, once per batch of authored
done-items; the findings-only edits on 19 **and** 20 Aug did not bump it,
correctly — the rule is the authored *done-state*, and rewriting a finding
changes none of it. **v17 also carried a text edit to an existing `li`**, which
needs a bump for a different reason: ticks are hashed on `textContent`, so an
edited item silently renders unticked under the old key.

**Read the published artifact back after every publish.** It earned its keep
again on 21 Aug: the v22 publish returned success with the *standfirst* still
reading *"only if you cut **three** things"* while the section heading directly
below it had become *"Cut these **four** first"* — the publication card was
added and one of the two numbers describing it was not. **Exactly the v17
failure, in a new pair of places**, and caught by fetching the page rather than
by the tool. The lesson is not "check the gates"; it is that **adding an item to
a counted set means grepping for every place that states the count**, which on
this page is never only one. The v17 publish
returned success while the *Manual QA* gate still quoted "All 264 tests" — only
the *Test suite* gate had been updated — and a sentence I had edited myself was
left ungrammatical. Both were caught by fetching the page, neither by the tool's
own success. That is the second class of rot on this page: not just going stale
between sessions, but going stale *within one edit* because a number lives in
two gates.

**And a narrower hazard, hit twice in one evening: the Test-suite gate note is
one long comma list, and every session appends to it.** Both times, a
search-and-replace whose `old` string began mid-list swallowed the `and` or a
comma and left the sentence ungrammatical — published, then caught on read-back.
**After editing that note, print it as plain text and read it as a sentence**,
not as HTML. One command:

```sh
python3 -c "import re,html,io;s=io.open('readiness.html').read();m=re.search(r'gate-state pass\">[0-9]+ passing</span>\s*<span class=\"gate-note\">(.*?)</span>',s,re.S);print(' '.join(html.unescape(re.sub(r'<[^>]+>','',m.group(1))).split()))"
```

**These numbers were themselves stale when re-counted on 19 Aug** — the line
above used to read `v5` (29 of 56) while the artifact was live on `v9`, and
the checklist counts were out by three, one and four. That is the same rot
this paragraph exists to warn about, arriving in the paragraph doing the
warning. **Re-count rather than copying the previous handoff forward.** The
two commands, so there is no excuse:

```sh
grep -c '^- \[x\]' ship-checklist.md   # and '^- \[~\]', '^- \[ \]'
python3 -c "import re,io;s=io.open('ship-checklist.md').read();print([len(re.findall(r'^- \['+c+r'\]',s,re.M)) for c in ('x','~',' ')])"
```

Counts as of 2026-08-22, re-counted with
the commands above: `ship-checklist.md` **47 done / 15 partial / 19 open**
(top-level boxes only — sub-bullets carry no box). Notion gained eleven Done
rows on 20 Aug and none on 21 Aug. **The open count went up rather than down**,
because 21 Aug added one `[ ]` to §3 for the Zoom publication finding; that is
the honest direction when a session's work is discovering that a task is bigger
than recorded. The `[x]` is the privacy-policy fix in §1.

**Do not copy those numbers forward.** They were 33/9/20 two handoffs ago,
35/11/18 when the next session re-counted, 39/10/17 the morning after that, and
42/11/17 on the evening of 20 Aug — stale within a day, in the paragraph warning
about staleness, for the fourth handoff running.

The seed only runs when the key has *no* stored value — after that
localStorage beats the markup, which is correct for hand ticks and is exactly
why an authored change needs a **new key** rather than an edit to the old one.

---

## The pattern that has found almost every real bug

Read the code, don't trust the task title. On 18–19 Aug, **nine** tracked tasks
turned out to be already done, and separately six defects were found by reading
things nobody had asked about. Three habits did it:

1. **Check the deployed artifact, not the repo.** The privacy policy
   contradiction was only visible by fetching the live page.
2. **Verify every guard is non-vacuous.** Plant a violation, watch it fail,
   remove it. This caught `RetentionPolicyTests` shipping *wrong* — a bare
   `contains("120 days")` passed a canary it should have failed, because the
   policy states the number twice. Two other guards were validated this way.
3. **Ask "where does this leave the reader?"** Removing the Advanced disclosure
   made three strings wrong; asking that question found them, and a scan then
   found three more.
4. **Check that the recommendation on the table actually does what it claims.**
   On 19 Aug the recorded fix for the `_CORRECTED` gap — drop it from
   `candidateResourceNames` — turned out to be a **no-op**: the loader sweeps
   every `.mlmodelc` in the bundle regardless of that list. It would have
   looked like a fix, passed every test, shipped identical bytes, and left the
   gap where it was. The stated saving was wrong by 2× in the same note.
5. **Ask whether a guard can be caught being wrong in the shipped
   configuration.** The stand-down guard could not: the full model is bundled
   and wins, so the correct rule and the broken one both answered `true`, and
   every pure-function test passed the *unfixed* code. That needed a seam
   (`StruggleDetectionService(resourceNames:)`) before the test meant anything.

---

## Do not redo — settled with evidence

- **Google verification is not needed and not on the critical path.** Dropping
  `classroom.profile.emails` left nothing restricted; the consent screen
  publishes to Production without review. The 2–6 week clock does not exist.
- **Google `client_secret` is optional** for installed apps — Google's own docs
  list `client_id`, `code`, `code_verifier`, `grant_type`, `redirect_uri` as
  required, with PKCE standing in. Anchor's omission is correct.
- **All three Zoom Marketplace apps are correctly configured.** S2S is
  Activated; the sign-in app is Draft but *"Active for internal users"*, which
  §2a says is sufficient; the Meeting SDK app is installed (its Local Test page
  offers *Remove App*), with Embed → Meeting SDK and programmatic-join on. Its
  Development Client ID matches the shipped `meetingSDKKey`.
  **Do not "activate for production"** — that means Marketplace publication,
  which is the review queue the partner-account strategy exists to avoid.
- **Mac App Store is not viable** (nested `us.zoom.*` bundles).
- **Rishab's Zoom account is Basic, and that is measured, not assumed** (console,
  2026-08-19). The two participant scopes **cannot be added at all** — the Add
  Scopes picker says "available based on your account privileges" and the
  product list has **no Dashboard and no Report category**. So the bot is the
  *only* live-signal source, not the richer of two. **Basic also caps meetings
  at 40 minutes**, so a full-length class cannot run on this account — QA Pass B
  is gated on the partner's Business/Education account, not on finding a willing
  class. Do not re-litigate this by reading docs; it was checked in the UI.
- **All three Marketplace apps re-verified 2026-08-19** and match what was
  recorded. The *Anchor* app's Client ID begins `SMDINiavSZKmylo…` (matches
  `OAuthClientDefaults.zoomClientID`), carries exactly the three documented
  scopes, and its consent screen reads "Anchor".
- **§7 (the differentiator) is built** — all five lines. Only a live lesson is missing.
- **Zoom API ToU §3.2.9 forbids** training ML models on Customer Content without
  Zoom's written permission; the consent exception is per-customer and the model
  "may only be used by the Customer who consented". This blocks the pooled retrain.
- **The pilot form works and the mail is not filtered — submitted, not inferred**
  (2026-08-19). It arrives in the **Primary inbox** in seconds, flagged Important;
  `signed-by: resend.dev`, `mailed-by: amazonses.com`, TLS; `from:resend.dev in:spam`
  returns nothing across four sends. `reply-to` carries the applicant's address, so
  Reply on an application reaches the teacher rather than Resend's sandbox — worth
  knowing, because a dropped `reply_to` looks identical in the inbox and only fails
  when you answer the first real lead. **Do not re-submit to re-check.** The only
  thing that would change the answer is the sending domain, which changes when
  `PILOT_FROM_EMAIL` is finally set. **`/apply` can be linked from both outreach
  emails.** The one caveat, recorded so it is not over-read: that send came from the
  mailbox's own owner and three earlier test applications already sit in it, so a
  stranger does not inherit that history — only the domain and its DKIM reputation,
  which is what actually decides the filter.
- **The Meeting SDK secret cannot ship, and that decides more of the Zoom
  account model than §3 says** (read in the code, 2026-08-19).
  `MeetingSDKTokenProvider.token()` signs the SDK JWT **HS256 locally** and
  there is no server-side signing path in the repo, so the secret is a
  *signing key*, not a public identifier like the three that do ship —
  extract it from a binary and you can mint Meeting SDK tokens as Anchor.
  `MeetingSDKCredentialStore.resolved()` needs **both** halves, so on any
  install not provisioned through the environment the bot cannot start at all.
  Per-school is fine (admin provisions in one Terminal launch). Per-teacher has
  nobody to do it, and `scripts/provision-zoom-sdk-secret.sh` cannot stand in —
  it targets `DerivedData/.../Build/Products/**Debug**`, so it does not work
  against an installed `.dmg`. **Per-teacher therefore means no bot, and with
  the participant scopes already unreachable, no live signal at all.**
- **Zoom DOES accept a PKCE-only token exchange — with the app's *Public
  Client ID*, which is not the id Anchor used to ship.** Settled 2026-08-20,
  after getting it wrong once the same day. **Read this before touching
  anything Zoom-OAuth-shaped.**
  - The *Anchor* Marketplace app has **Use Public Client OAuth** switched on,
    and that mints a **second identifier**: Public Client ID
    `kzU8QEfESJKsvxA3EzCe9A`, distinct from the confidential
    `SMDINiavSZKmyIoF4XmM_A`. Only the public one is redeemable with PKCE and
    no secret.
  - Measured: confidential id + PKCE + no secret → `400 invalid_client`;
    **public id, same request → `400 invalid_grant "Invalid authorization
    code"`**; public id + refresh grant → `invalid_grant` too. `invalid_grant`
    means the client authenticated and the deliberately bogus code was
    rejected, which is as far as a probe gets without a real one.
  - **How it was got wrong first, because the mistake is repeatable.** The
    original probe used the confidential id, saw `invalid_client` identical to
    sending garbage or nothing, confirmed with a control that Zoom really does
    reach client authentication, and concluded Zoom refuses PKCE-only. Every
    step was sound except the subject. **An error naming a credential can mean
    the credential is *wrong* rather than *missing*** — nothing in the response
    distinguishes those, and only the console did.
  - **Do not turn the toggle off**, and do not copy the console's own generated
    *OAuth URL*: it is built with the **confidential** id, so it is the wrong
    one for a PKCE flow.
  - `ZoomOAuthConfig.effectiveClientID` is the single accessor both the
    authorize call and the token exchange read. **They must never differ** — a
    code is issued to a client, so obtaining it under one id and redeeming it
    under the other fails *after* the teacher approves Anchor.
  - **Console state read 2026-08-20, both tabs, values taken from the DOM.**
    Development: toggle **on**, public id `kzU8QEfESJKsvxA3EzCe9A`.
    **Production: toggle off, and therefore no Public Client ID exists at
    all**; its confidential id is `Vgi566QtQhaoeAOptZpqug`. Redirect URL *and*
    allow list hold the bounce URL on **both** tabs; Strict Mode and Subdomain
    Check off on both.
  - **Switching to Production is not a client-id swap.** Enabling the toggle
    there mints a *third* identifier, different again from the Development
    public id, and that is what `zoomPublicClientID` would have to become.
    Shipping the Development public id against Production fails the exchange
    exactly as the confidential id did — after consent.
  - **An earlier note here said the allow list "looked empty". It is not.**
    Zoom renders a populated field in the same grey as a placeholder, so a
    screenshot cannot tell them apart; reading `input.value` can. Worth
    remembering for any console this project reads again.
  - **Google is unaffected** and its same-shaped branch is correct: Google
    documents `client_secret` as optional for installed apps.
  - **What this does NOT do, because it was claimed on 20 Aug and is false:
    it does not let other teachers sign in.** The *Anchor* app is Draft /
    "Active for internal users", so a teacher on any other Zoom account fails
    at `/oauth/authorize` with **"You cannot authorize"** and never reaches the
    token exchange. The credential fix sits *behind* the distribution limit.
    What it genuinely buys: anyone on the app's own account can now sign in
    with **no provisioning at all** — which is what makes QA Pass A on a
    borrowed Mac meaningful — and a partner school with its own app has a
    working secretless path if they want it. **Per-teacher at large still needs
    Marketplace publication, exactly as before.**
- **The three Zoom identifiers belong to ONE registration and Anchor must never
  present halves of two.** `ZoomOAuthConfig.offeredPublicClientID`, added
  2026-08-20 after the public-client fix introduced the hole. If a school
  provisions `ANCHOR_ZOOM_OAUTH_CLIENT_ID` without its secret,
  `effectiveClientID` used to fall through to the *shipped* public client and
  authorize under **Anchor's** Marketplace app while the deployment had named
  another — producing "You cannot authorize", the page ADMIN-SETUP.md calls the
  most misleading in the flow. **The rule keys on the provisioned *id*, never on
  the secret**: a provisioned secret with no provisioned id is legitimate, it
  completes the *shipped* registration, and that is how Rishab's own Mac is set
  up. A rule of "either half overridden" breaks the developer machine. Do not
  "simplify" it into one.
- **Anchor is per-teacher by architecture. The per-school route is a Zoom
  distribution workaround, not a product design.** Checked in code 2026-08-20
  after the claim "individual teachers cannot use Anchor" was made in a session
  and challenged by Rishab, correctly. `ZoomViewModel.makeLiveService()` returns
  `ZoomService(userTokens: .shared)` whenever a teacher is signed in and only
  falls back to Server-to-Server otherwise, and `hasAnyZoomCredential` is
  satisfied by a teacher sign-in alone. The bot joins as the teacher on their own
  ZAK; Classroom is per-teacher; scoring is local. **Nothing in the app is
  school-shaped.** Keep the three questions apart, because collapsing them is
  what produced the wrong claim: (1) can it work per-teacher — yes; (2) can an
  outside teacher sign in *today* — no, the app is unpublished; (3) what would
  they get — the Classroom half, no live signal until there is a bot.
- **Publishing to the Marketplace is not gated on a Zoom plan, and Beta Test is
  the harder path, not the easier one.** Settled 2026-08-20 against Zoom's own
  docs and their forum post for independent developers. Zoom: *"participation in
  Beta is optional. Your app can still qualify for publication in our
  Marketplace without supporting evidence."* Beta demands SSDLC evidence,
  SAST/DAST results and a Privacy Policy, **plus three of** five security
  policies including a penetration test summary, and it **expires after 12 weeks
  maximum** — shorter than a school term. Publication needs metadata, Technical
  Design and security information, with Zoom doing the OWASP testing themselves
  and **no third-party pen test mandated**. Requirement is **Account Owner or
  Admin**, not a plan tier. Full detail and the two things publication does
  *not* fix are in `ZOOM_INTEGRATION.md` §2a.
- **The published privacy policy matches the app.** Re-fetched 2026-08-20: 120
  days, one term, "Last updated August 17, 2026", and the dropped-email-scope
  paragraph. The `[~]` warning that said otherwise was two days stale.
- **The deployed bounce page works and matches the app** (2026-08-20): 200, and
  it forwards to `127.0.0.1:51789/oauth/zoom`. `/apply`, `/support`, `/terms`,
  `/pilot-terms` all 200; a bogus path still 404s. Now pinned by
  `OAuthBounceContractTests` — but **only the committed file, not the
  deployment**, since `anchor-oauth-bounce` has no Git connection.
- **The app icon and branding assets are done** — verified 2026-08-20 against
  the built artifact, not the source. `AppIcon.icns` ships, the Icon Composer
  document compiles into `Assets.car`, and `og.png` is exactly the 1200×630 the
  meta tags declare. The tenth tracked task found already done.
- **The site says "macOS 14 or later" while Apple Intelligence needs macOS 26, and that is NOT a discrepancy.** Checked 2026-08-21 and recorded here because it looks exactly like the privacy-policy defect and is not one, so the next reader does not spend an hour on it. `RecommendationGenerator` has **zero** `@available(macOS 26)` gates: recommendations are generated on macOS 14. Its own header states the split — *"The model writes the words; this type decides the facts. When the model is unavailable, refuses, or times out, `fallback` states the same facts in Anchor's own voice, so the feature degrades in phrasing quality and never in correctness."* The in-app string agrees (*"Until then it composes them from the matched signals, and everything else works exactly the same"*), and the site labels Apple Intelligence **Optional**. Deployment target is 14.0, measured. **All three artifacts agree. Nothing to fix.**
- **The deployed OAuth bounce page is byte-identical to `Web/oauth-zoom-bounce.html`** and forwards to `127.0.0.1:51789`, which matches `ZoomOAuthConfig.loopbackPort`. Measured 2026-08-21 with a real `diff`, which closes — for today — the gap `OAuthBounceContractTests` explicitly cannot cover, since `anchor-oauth-bounce` has no Git connection and `Web/deploy.sh` is the only thing that ships it. **It is a snapshot, not a guarantee:** the next hand-deploy can still drift it, and nothing watches.
- **"Google verification is not needed" is confirmed in Google's own words, and *branding* verification is a different thing that has failed.** Read in the console 2026-08-21. Verification Center, verbatim: *"Verification is not required since your app is not requesting any sensitive or restricted scopes."* Data Access bears it out: **all five scopes sit under "Your non-sensitive scopes"**, and sensitive and restricted both read **"No rows to display."** The 100-user cap on the Audience page binds only on unapproved sensitive/restricted scopes, so it does not bind here.
  - **But branding verification was submitted at some point and rejected**, and the Verification Center says *"Your branding is not being shown to users."* **Do not read that as the consent screen being anonymous** — I checked the live screen rather than inferring it, and it reads *"Sign in with Google — Choose an account — to continue to **Anchor**"* with *"you can review Anchor's Privacy Policy and Terms of Service."* **Name and both legal links are shown.** What the failure costs is the **logo** and the verified-publisher treatment. It is not the Google twin of "General app 392".
  - Three rejection issues: the home page URL *"is not registered to you"* (needs the real domain, Search Console cannot verify a `vercel.app` subdomain); the home page *"does not explain the purpose of your app"*; and the configured name *"does not match the app name on your home page"* — where the evidence is that `<title>` and `og:site_name` both say **Anchor** while the **`<h1>` is "See what your students aren't saying." and never says it.** **The last two are homepage copy and therefore Rishab's**, by the same rule as the pilot form.
- **A plant that does not compile is indistinguishable from a plant that does not fire, and this page's own advice made that trap worse.** Hit 2026-08-21 while canary-testing the log guard. Two plants reported firing nothing, which this project treats as *information* — and they were not information: both referenced properties that do not exist (`user` in a scope without one, and `.email` on `ClassroomStudent`, which stopped existing when the email scope was dropped on 17 Aug). **Compilation failed, no test ran, and a grep for a failing test counted zero** — identical to a guard that does not fire. **Check the build succeeded before believing a silent canary.** Re-run with compile-safe plants and both fired.
- SourceKit reports phantom "cannot find type in scope" errors. Trust xcodebuild.

---

## Done on 2026-08-19

- **The `_CORRECTED` fallback question is closed** (`bc6dd91`), and *not* the way
  it was written up. `usesAcademicFeatures` now requires the **full** academic
  set. Two corrections came out of reading the code rather than the note:
  dropping the model from `candidateResourceNames` **would have changed
  nothing** — the loader sweeps every `.mlmodelc` in the bundle and `Anchor/`
  is a synchronised Xcode group, so a model ships by existing in the directory
  — and the saving was **3.2 MB compiled, not 7.5 MB**.
- **The four §9 manual passes are scripted** in `QA-PROTOCOL.md` (`a6714a7`),
  left `[~]` because a protocol is not a pass.

## Done on 2026-08-20

Five commits, `7fdc61f` → `a95cdbb`. Tests 241 → **260**.

1. **The PKCE question is settled — twice, and the second answer reverses the
   first** (`7fdc61f`, then `4fd94eb`). Zoom *does* accept PKCE-only; Anchor
   was sending the wrong client id. See *Do not redo* — the most important
   entry on this page, and the only one where the reasoning matters more than
   the conclusion.
2. **The findings were carried into the artifact, and two cards there were
   stale** (`81edacb`). The privacy-policy card was still a red Blocker for a
   contradiction fixed on 18 Aug; the onboarding card said "Zoom is probably
   fine, Google is the one to check" and had it exactly backwards.
   `ZOOM_INTEGRATION.md` §2a carried the same error at its source and is fixed.
3. **The retention *deletion* is tested, not just the sentence** (`41bb9cc`).
   The old note called `pruneExpiredSessions` untestable and the obstacle was
   real: it ends in `saveNow()`, which writes the **developer's own**
   `session-archive.json`, so a direct test would have deleted real class
   history. Rule lifted out pure as `sessionsSurvivingRetention`.
4. **The OAuth bounce contract is pinned** (`dde1c4a`), plus
   `isPrunableSidecar` (`250bd4d`) — the predicate standing between the
   retention sweep and `removeItem` on a file that is not Anchor's.
5. **`ADMIN-SETUP.md` is pinned against the code that reads it** (`a95cdbb`).

**Thirty-six canaries across ten rules.** Every rule added on 19–20 Aug was
checked by planting the violation it exists to catch and watching it fail.
**Three of them failed *fewer* cases than expected on the first plant, and one
failed none at all** — dropping the duplicate-id fold in `AcademicMatchTable`
fired nothing, because a roster of `[A, A]` never becomes ambiguous (the loop
compares ids) so the collected list was never read. That is how you find out a
case is passing for an unrelated reason. **Plant the violation even when the
test reads obviously correct; a plant that fires nothing is information.**

## Also done on 2026-08-20 (evening) — four findings, none of them tracked

All four came from the same method and none was on any list. **Tests 264 → 299,
16 test files → 19.** Commits `5c70423` → `a10026d`.

1. **A half-provisioned school would have signed its teachers into Anchor's own
   Zoom app** (`5c70423`). Introduced by the morning's public-client fix. Found
   by noticing that *every* case in `ZoomTokenExchangeTests` built its config
   with the **shipped** client id — none modelled a school that provisioned its
   own. The blind spot was in the test file. See *Do not redo* above.
2. **The roster told teachers to fix a name collision by renaming the student in
   Zoom** (`1cfba59`) — the name they are already using, which is why the match
   failed. `AcademicMatchTable` refused ambiguous names correctly and *silently*,
   so downstream "two students normalise alike" and "nobody is called that" were
   the same `nil`. It had **no tests at all** before this.
3. **The Meeting SDK JWT is pinned** (`e35643b`). Only a comment held it, and on
   Basic/Pro the bot is the only live-signal source. `mn`/`role` are Web-SDK
   claims that every online tutorial shows and that make `sdkAuth` reject the
   token — reporting itself as a wrong Key or Secret.
4. **The Classroom panel told every teacher their whole class was unmatchable**
   (`2aa7b82`). `unmatchableStudentCount` was `matchKey == nil`, which after the
   17 Aug scope drop is the entire roster; the note also claimed their coursework
   would not affect any score. Both false, on the first screen after connecting
   Classroom. Same pass fixed a snapshot lookup by `matchKey` that had emptied
   `CourseStudentHistoryView` on every install, and renamed a
   `let matchKey = student.rosterKey` binding that is how the next reader makes
   the same mistake.

**The generalisable lesson from all four: the 17 Aug scope drop and the 20 Aug
public-client fix were both correct, and both left code behind that still
treated the old world as the normal one.** After a change that flips what is
typical, grep for every site that branched on the thing that changed.

## And five more, later the same evening — all teacher-facing copy

Commits `7495f89`, `6ae3ed4`. Tests 299 → **308**. Every one is prose in a Model
or a Service that reaches the screen, where **neither existing scan could see
it**: `TeacherFacingCopyTests` reads `Anchor/Views`, `SupportContactTests`
enumerates `ZoomError` and `ClassroomError`.

- **Start here, because it is the whole lesson.** `SupportContactTests`' own
  header quotes *"add the scope to your Server-to-Server OAuth app, then
  re-activate it"* as the sentence it exists to prevent — **and a sentence of
  exactly that shape was live in `ZoomEmailVerification.detail` the entire
  time.** The guard was real. Its *reach* was smaller than its stated contract,
  and the gap held the example it was written about. **A vocabulary scan is
  worth its list × the surfaces it enumerates, and nobody re-checks the second
  factor when a new type starts talking to teachers.**
- **`ZoomError.invalidCredentials`, where the classification was the hole.** It
  told teachers to "regenerate the Client Secret in the Zoom Marketplace" and to
  check credentials in Settings — a panel that is `#if DEBUG`. It survived
  because `isSetupProblem` said **false**, and the scan only reads setup
  problems: the misclassification removed it from the guard *and* justified
  giving it an instruction. **When a guard is gated on a predicate, the
  predicate is part of the guard.**
- **The Classroom scope message was wrong about the cause.** It sent teachers to
  the Google Cloud console; Google presents the four Classroom permissions as
  separate tick boxes, and one left unticked is the common way to get there.
  Nothing in any console is missing. This is the most likely Google failure in a
  real pilot.
- **Two dual-audience sites**, now split: the Meeting SDK auth description (log)
  was handed to `ZoomError.unsupported` (screen), and the refresh-token failure
  named the Marketplace app type at a teacher. `describe` →
  `diagnosticDescription`: **the rename is the guard** — the old name said
  nothing about who reads it, which is how it came to be rendered.

`TeacherFacingSourceScanTests` now scans all non-DEBUG source, skipping only
audiences **declared in the code** (`technicalDetail`,
`AnchorDiag.operatorMessage`, `diagnosticDescription`) — never by file, because
`TeacherFacingCopyTests` records that its own first version carried a per-file
exemption and that the exemption was the hole.

## And one on the site — made, then reverted, and the reason is the lesson

**The pilot form's requirements were changed to name the Zoom-admin step, and
Rishab reverted it the same evening** (`78f0720`, reverted by `da6d699`; the
live `/apply` is verified back to what it was). **Do not redo it without asking.**

The *observation* stands and is recorded as an open `[ ]` in the checklist:
`REQUIREMENTS` describes itself as the hard gates, "shown next to the
application form so nobody fills it in and finds out afterwards", and neither it
nor the checkbox mentions the hour with the school's Zoom administrator — while
both `OUTREACH.md` drafts are built around exactly that ask. The site and the
emails disagree about what matters.

**What was wrong was the response, not the finding.** Adding it to the form is
*friction on the top of the funnel*, which is a conversion decision rather than
a factual correction. With fourteen prospects and a target of one to three
yeses, the emails already ask both qualifying questions at the point in the
conversation where Rishab can handle the answer himself. **Inbound form and
outbound email are different funnels.** The checkbox reasoning was over-literal
too: "I teach live on Zoom and can connect my account" reads to a teacher as "I
am not blocked from using Zoom integrations", which they can answer fine.

**The general rule this earned, and it is the most useful thing on this page for
an agent working unsupervised:** *"complete everything that does not require me
personally"* does **not** extend to copy on the conversion path. A finding that
resolves into a judgement about positioning, pricing, funnel or tone gets
**written down and handed back**, never shipped — however well-evidenced the
finding is. Ask whether the fix has a single correct form. If two reasonable
people would pick differently, it is not yours.

**And separate the two authorisations.** Pushing was pre-authorised; deciding
funnel copy was not. But `anchor-landing` tracks `main`, so **any push that
touches `website/landing` is an outward-facing deploy** even when the commit
feels routine. Treat that path as needing its own consent.

## Done on 2026-08-21

**One thing, and it was the item the previous session flagged as the single
unverified question: why the Zoom Publish page says "Not ready".** It is now
answered, and the answer is worse than the file it corrects assumed.

- **Publish lists eighteen missing required fields, not one architecture
  diagram.** App Listing → App Information 4, Links & Support 4, EU &
  Discoverability 9, Technical Design 1. Full detail, with the field-by-field
  reading, in `zoom-submission-remaining.md`; a new `[ ]` in §3 of the
  checklist.
- **Nine of them are EU Digital Services Act trader disclosures** — business
  bank account digits, a DUNS or equivalent, bank name, and an uploaded
  identification document of the trader. **Four of those nine cannot be produced
  by an individual with no registered company.** They hang off an *"Available in
  the EU"* switch that is currently **on**; turning it off should drop all nine.
  **Not flipped** — it changes which markets a live listing is offered in, which
  is Rishab's call under the same rule as the pilot-form copy.
- **Two entries in that file's own *Done* table were wrong**, and both are struck
  through in place rather than deleted. "App Listing — Complete" (Long
  Description is empty, the App Icon is still Zoom's placeholder) and "Link &
  Support — Privacy, Terms, and Support URLs" (**only** Support is entered).
  Checked in Development as well as Production and identical in both, so this
  was never a case of reading the wrong tab — those two URLs were never typed,
  while both pages have been live on the site for days.
- **The method note.** Nothing here needed a new idea: it is *check the artifact,
  not the sentence about the artifact*, applied to a console page instead of a
  deployed HTML page. The file said "everything is filled in except one file
  upload"; the page said eighteen.
- **A new instance of an old trap.** For a checkbox, `input.value` is the string
  `"on"` whether or not it is ticked, so the first probe reported every checkbox
  set — including the EU switch and the data-subject-rights attestation. Read
  `.checked`. Same family as the allow list that "looked empty": **the Zoom
  console cannot be read off its own rendering, and now also not off its own
  DOM defaults.**
- **Also read on the way past:** Zoom warns that the *Education* market vertical
  *"has additional review requirements"*. Anchor has Education and K-12
  selected, correctly — so publication draws the stricter review. One more
  argument for the per-school route.
**And then a second finding, from the same method pointed at a different
artifact.** Not on any list, and it is the one with a deadline attached.

- **The published privacy policy disclosed the Google Keychain entry and not the
  Zoom one** (`8b55127`). §5 *"Where the data lives"* named exactly one Keychain
  entry, *"Your Google refresh token"*, while `ZoomOAuthStore` has been writing
  the teacher's whole Zoom grant — refresh token, access token, expiry, scopes,
  account label — under `com.anchor.zoom.oauth`. §10 had the matching hole:
  how to disconnect and revoke **Google**, nothing about Zoom. **Fixed,
  deployed, and read back on the live page** — both bullets render and
  `LEGAL_LAST_UPDATED` shows August 21.
- **It mattered this week because of the other finding.** The Marketplace
  submission answered **Yes** to *"stores Zoom OAuth tokens?"* and the listing's
  Privacy Policy URL field is **empty** — so the page got corrected *before*
  that field is filled, rather than after a reviewer read the two side by side
  and found them disagreeing.
- **Zoom got its own bullet rather than joining Google's, and that is the part
  worth copying.** Google's bullet says the access token *"is held in memory
  only and never written to disk"* — true of Google, **false of Zoom**, which
  persists it deliberately so a mid-lesson relaunch does not bounce the teacher
  through Zoom's sign-in page. **Folding the two would have replaced an omission
  with a false statement.** Check that before merging any two items in a list.
- **The guard's first version was vacuous, and planting proved it.** It asserted
  the section contained *"Zoom"*. Deleting the Zoom bullet outright **left it
  passing**, because the session-history bullet in the same section says
  *"engagement scores and Zoom signals"*. It now demands the provider and
  `Keychain` in the **same `<li>`**. Four canaries, all confirmed firing.
  **Four more canaries on three new rules, taking the running total to 47
  across 15** — but that total is *carried forward* from the 43/12 the last
  handoff recorded, not re-derived, and the first draft of this line said
  *thirty-nine*, which is **below** the number it was adding to. **Treat the
  cumulative canary figure as the one number on this page nobody has ever
  actually re-counted**, unlike the checklist boxes, which have two commands.
  Tests 308 → **311**, 20 test files → **21**.
- **A new shape for the guard-gap collection: `RetentionPolicyTests` already
  reads `privacy.tsx`.** This was never an unguarded artifact — it was a
  **guarded file with an unguarded section**, because that test reads the file
  for retention day-counts only. *"The file has a test"* answers neither factor
  of list × surfaces.

## Also on 2026-08-21: two outreach segments opened, one refused

Rishab asked to start outreach to **smaller K-12 online academies**, **tutoring
agencies**, and **individual tutors "if they can sign in and use the app"**.
**Nothing was sent** — that is his, and the drafts have to be read first.

- **Six new prospects, 20 to 25, taking `PROSPECTS.md` to twenty-five**, and a
  new **Email 3 for tutoring agencies** in `OUTREACH.md`. Em dash rule checked
  on the send text specifically, not on the file: 45 quoted lines, zero em or
  en dashes.
- **Individual tutors were refused, and the condition in the question is why.**
  "If personal tutors can sign in and use this app" is a conditional and it
  fails on three gates in series, checked in the build: the Release app is
  `Signature=adhoc` / `TeamIdentifier=not set` with only a free Apple
  Development cert, so **nobody can install it**; the Marketplace app is
  Draft/internal-only so an outside tutor cannot authorize; and
  `meetingSDKSecret` ships empty, so past both gates they get the coursework
  half and **no live signal**. **This confirmed the handoff's own claim rather
  than trusting it** — `DEVELOPMENT_TEAM = SYLM5655ZW` is set in the pbxproj,
  which reads like a real team until you check the artifact and find the
  signature is ad-hoc anyway.
- **The workaround is the argument against, and it is the part worth keeping.**
  A solo tutor *is* their own Zoom admin, so they could self-provision through
  `ANCHOR_ZOOM_SDK_KEY`/`_SECRET` where a school teacher could not. That means
  handing **Anchor's own Meeting SDK signing secret** to people found by cold
  email; it is HS256 signed locally, so whoever holds it can mint tokens as
  Anchor. **The mechanism that unblocks the segment is what makes it unsafe at
  scale.**
- **A tutoring agency is a school or it is Kepler, and one question separates
  them:** employees on a company Zoom account, or contractors on their own.
  Email 3 asks account ownership as question 1 and **drops the plan-tier
  question**, because ownership is the disqualifying one and two account
  questions in one email read as an audit.
- **Widening made finding 1 worse, which was the opposite of the hope.**
  Apologia is Canvas, so it is now **seven organisations with a discoverable
  LMS and still zero Google Classroom**. And Brilliant Microschools names **no
  LMS at all**, which is a third case no connector fixes.
- **One positioning question handed back unshipped:** selling an agency owner
  *supervision of their tutors* rather than *a tutor's instrument*. Different
  buyer, different privacy story. Recorded, not written into the draft.

## Decided on 2026-08-21: the Zoom publication path is parked

Put to Rishab with the deploy question; he delegated the call back, so it was
made rather than left open. **The "Available in the EU" switch stays on and
publication is not being pursued for this pilot.** Full reasoning in
`zoom-submission-remaining.md`.

**Revised later the same day, when Rishab said he had started Apple Developer
enrollment and asked why publication was parked.** One of the three stated
reasons was *"nobody can install Anchor at all"*, and he is removing it. **The
decision survives, because that reason was never the load-bearing one** — but
the honest version of the load-bearing one is much stronger than what was
written, and it was found by reading `ZoomCapabilities` instead of re-reading
the summary.

- **`ZoomService.probeCapabilities` hard-codes `muteState`, `videoState`,
  `handRaised`, `audioLevel` and `chat` to `false`** — *"REST cannot see them at
  all"* — while `MeetingBot.capabilities()` returns **all seven true**. So the
  bot is not the richer of two live-signal sources. **It is the only source for
  every signal Anchor scores on except who is in the room.**
- **Read the outreach draft against that.** Email 1 promises *"speaking time,
  hand raises, chat, and whether someone has gone quiet"*. Speaking time and
  gone-quiet need `audioLevel`, hand raises need `handRaised`, chat needs
  `chat`. **All bot-only.** The bot needs the Meeting SDK secret, which is
  HS256 signed locally and cannot ship. **So a published Anchor installed by an
  arbitrary teacher cannot do what the email says it does.**
- **The obvious lever does not rescue it, and that is worth knowing before
  anyone spends a week on it.** The participant scopes are ungrantable because
  the *owning* account is Basic; upgrading Rishab's own Zoom plan would
  plausibly make them addable — **unverified**. But `liveParticipants` is
  presence. Even granted, on a teacher who is themselves Business or Education,
  it buys who joined and left and **still no speaking time, hand raises or
  chat**. The best possible REST outcome is short of the pitch, so the scope
  question is not on this decision's critical path whatever its answer.
- **The generalisable bit: this is two gates in series again**, the failure mode
  this page already warns about. Apple Developer is the gate on **installing**,
  and it gates the whole per-school pilot, so working on it is right. Marketplace
  publication is the gate on **per-teacher reach**, which is a growth question
  for after the pilot and is separately blocked by the bot. **Clearing the first
  does not move the second**, and the phrasing of reason 1 invited exactly that
  reading.

**So the switch was not flipped, even though flipping it is one click and would
drop the requirement from eighteen fields to nine.** A setting changed on a live
listing for a path nobody has chosen is a setting nobody remembers changing, and
the evidence that it gates the nine is recorded and does not decay. **If
publication is ever pursued, flipping it is step one and the count is the
check** — eighteen should fall to nine, before any App Listing copy is written.

- **Session note:** the Marketplace console had lapsed to signed-out and its
  Sign In button is a JS handler that did not respond to a synthetic click.
  `zoom.us/profile` loaded signed in, and re-visiting the console URL after that
  completed the handshake with no password. Worth trying before asking for a
  human click next time.

## Next, in order

Everything Claude-owned and unblocked is done, and that sentence has now
survived **two** sessions that each found four more things to do after writing
it. **Treat it as false on sight.** The evening session of 20 Aug wrote it,
went looking anyway, and found four defects — two of them teacher-facing
sentences that were simply untrue, on screens a pilot teacher meets in their
first ten minutes. **The
way they were found is the only reliable method this project has: pick a claim
that is load-bearing for a pilot teacher, and check the artifact rather than
the sentence about the artifact.** All four came from that — the token
endpoint, the live privacy page, the deployed bounce page, the setup document.

1. **Send the outreach emails.** `OUTREACH.md` has both drafts; `PROSPECTS.md`
   has the fourteen organisations. **Read `PROSPECTS.md`'s findings first** —
   three of four contradict something the plan assumed: the segment mostly runs
   **Canvas, not Google Classroom**; **most local co-ops meet in person**, so
   that pool is far smaller than the academy pool; and **Kepler Education is
   the per-teacher branch in disguise**, so cut the "hour of a Zoom admin's
   time" sentence from that one. Two warm routes the prospects publish
   themselves: The Potter's School's **public Zoom open house, Mondays 11:00
   and 20:00 US ET**, and Excelsior Classes' Calendly.
2. **Apple Developer enrollment** — still the longest lead, gating certificate
   → notarization → anyone installing at all → QA Pass A.
3. **Decide the Zoom account model — and note that 20 Aug did not actually
   move it**, despite two claims that day saying it had. Per-teacher at large
   still needs Marketplace publication (see *Do not redo*), still has no
   grantable participant scopes, still caps at 40 minutes on Basic, and still
   has no bot. Per-school remains the only branch with a live signal. Still
   `[ ]`: this is the call to make and record.
4. **The fresh-install click has a predicted outcome now, and this is the
   thing 20 Aug really did buy.** Connect Zoom should be **enabled** and should
   complete on a Mac with no provisioning — *signed in as you*, since you are
   the app's account. Previously that test could only ever have failed for want
   of a secret, which would have told you nothing about the app. If it fails
   after the consent screen, the public client id did not reach the build.
   (Expectation flipped twice on 20 Aug; trust `4fd94eb` or later.)
5. ~~Glance at the OAuth Allow List.~~ **Done 2026-08-20 — it is populated on
   both tabs, and the "looked empty" reading was a misread of Zoom's grey
   styling.** Nothing to do. The Production finding above came out of the same
   pass and is the part worth carrying forward.
6. ~~Find out why Publish says "Not ready".~~ **Done 2026-08-21 — see *Done on
   2026-08-21* above.** What replaces it is a decision rather than a task: the
   *"Available in the EU"* switch. Turn it off and publication needs nine fewer
   fields, none of the remaining nine needing a company; leave it on and
   publication needs a registered business. **Decide that before spending any
   time on the App Listing copy**, because the copy is four minutes and the
   trader block is the whole question.

## Blocked on the human

- **Apple Developer Program enrollment** — longest lead; gates the certificate →
  notarization → anyone installing at all.
- **A real domain** — gates the Resend verified sender, which gates
  `PILOT_FROM_EMAIL`. **It no longer gates the inbound path**: that sentence
  used to read "pilot applications from strangers fail silently", and the live
  test on 19 Aug disproved it. What the domain still buys is credibility —
  `anchorteach.vercel.app` in a footer and `onboarding@resend.dev` in a
  forwarded thread are both read by the same cautious reviewer — not delivery.
- ~~**Google's consent screen publishing status has never been checked.**~~ **Checked 2026-08-21 with the right account, and the worry was wrong: it is *In production*.** No seven-day token expiry, no test-user list. Left struck through rather than deleted because the *reasoning* was sound — a Testing-status app really does expire refresh tokens at seven days and really would have broken a pilot mid-term — and only the premise was untested. **The account was the whole obstacle:** the project is `anchor-504419` under `rishabreddy6956@gmail.com`, and Chrome defaults to a different Google account that owns no projects at all, which reads as "no access" rather than "wrong account".
- **Partner outreach** — still the real gate on the whole timeline.
- **The fresh-install click** — press both Connect buttons on a Mac that has
  never had Anchor, and watch what happens *after* browser consent.

---

## Gotchas that cost real time

- **`grep` treats the site's HTML as binary, and silently reports no match.**
  `curl -s https://anchorteach.vercel.app/apply > f.html; file f.html` says
  `data` — there are bytes in the payload that make grep switch to binary mode,
  where a plain `grep -c` prints **nothing at all** rather than `0`. A live check
  written the obvious way therefore reports "not deployed" for a page that
  deployed fine. **Always `grep -a`.** This defeats the one habit this project
  relies on most, and it fails in the direction that wastes a redeploy.
- **Vercel: check the production alias, never the deployment URL.**
  `anchor-landing-<hash>.vercel.app` returns ~478 KB of Vercel SSO login page,
  not the site. It reads exactly like a broken deploy.
- **Vercel defaulted the production branch to `main`**, which does not exist
  here. Connecting a repo and stopping there looks successful and deploys
  nothing, forever.
- **Retraining:** use `.venv/bin/python`, not `python3`. Use
  `train_production_model.py`, not `train_struggle_model.py`. Use
  `generate_messy_data.py --rows N` (not `--n`). Each model trains on its own
  population via the `_academic_observed` marker; intercepts are solved per
  population so both are ~32% struggling.
- **Tuning is finished on the current feature set.** 4× data and 2× search moved
  engagement AUC 0.7933 → 0.7930. The ~10% gap to the Bayes ceiling is
  irreducible noise. The next gain is academic coverage or real labels.

## Style

Very high comment density; every comment explains **why**, never what. Commit
messages carry the reasoning, including what was *not* done and why. Use `[~]`
for partially-done, and never mark `[x]` what has not been verified end to end —
several lines were found stale precisely because someone did.
