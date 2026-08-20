# Anchor — continue pilot readiness

Repo: `/Users/rishabreddypaili/Documents/Anchor`
Branch: `ship/pilot-readiness`; **default is `main`** since 2026-08-19
(`app-split` is retired — do not push it). **Both branches always point at the
same commit and are pushed** — `git log --oneline -1` for which one, because a
hash written here is stale the moment the commit writing it lands. Tests:
`xcodebuild test -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
→ **299 passing**, 19 test files. Release config builds clean.

Deadline: term starts ~31 Aug 2026. Goal is 1–3 real pilot users.

Three checklists must stay in step: `ship-checklist.md`, the Notion **Tasks**
database (under the *Anchor* page), and the Ship Readiness artifact
(https://claude.ai/code/artifact/44f67c4b-a54b-4c2c-af29-dce669095bea).
**The artifact is the one that silently rots** — it was a full day stale on
19 Aug while the other two were current. Its ticks are localStorage keyed on
`anchor-readiness-ticks-vN`; **bump N whenever you mark things done**, or a
returning browser keeps showing the old state forever. Currently `v18`
(45 of 69 ticked). It went v10 → v18 across 20 Aug, once per batch of authored
done-items; the findings-only edits on 19 **and** 20 Aug did not bump it,
correctly — the rule is the authored *done-state*, and rewriting a finding
changes none of it. **v17 also carried a text edit to an existing `li`**, which
needs a bump for a different reason: ticks are hashed on `textContent`, so an
edited item silently renders unticked under the old key.

**Read the published artifact back after every publish.** The v17 publish
returned success while the *Manual QA* gate still quoted "All 264 tests" — only
the *Test suite* gate had been updated — and a sentence I had edited myself was
left ungrammatical. Both were caught by fetching the page, neither by the tool's
own success. That is the second class of rot on this page: not just going stale
between sessions, but going stale *within one edit* because a number lives in
two gates.

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

Counts as of 2026-08-20 (evening), re-counted with the commands above:
`ship-checklist.md` **41 done / 11 partial / 16 open** (top-level boxes only —
sub-bullets carry no box). Notion gained nine Done rows on 20 Aug.

**Do not copy those numbers forward.** They were 33/9/20 two handoffs ago,
35/11/18 when the next session re-counted, and 39/10/17 in the version of this
paragraph written this morning — stale within a day, in the paragraph warning
about staleness, for the third handoff running.

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

## Blocked on the human

- **Apple Developer Program enrollment** — longest lead; gates the certificate →
  notarization → anyone installing at all.
- **A real domain** — gates the Resend verified sender, which gates
  `PILOT_FROM_EMAIL`. **It no longer gates the inbound path**: that sentence
  used to read "pilot applications from strangers fail silently", and the live
  test on 19 Aug disproved it. What the domain still buys is credibility —
  `anchorteach.vercel.app` in a footer and `onboarding@resend.dev` in a
  forwarded thread are both read by the same cautious reviewer — not delivery.
- **Partner outreach** — still the real gate on the whole timeline.
- **The fresh-install click** — press both Connect buttons on a Mac that has
  never had Anchor, and watch what happens *after* browser consent.

---

## Gotchas that cost real time

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
