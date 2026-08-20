# Anchor — continue pilot readiness

Repo: `/Users/rishabreddypaili/Documents/Anchor`
Branch: `ship/pilot-readiness`; **default is `main`** since 2026-08-19
(`app-split` is retired — do not push it). **Both branches always point at the
same commit and are pushed** — `git log --oneline -1` for which one, because a
hash written here is stale the moment the commit writing it lands. Tests:
`xcodebuild test -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
→ **241 passing**, 14 test files. Release config builds clean.

Deadline: term starts ~31 Aug 2026. Goal is 1–3 real pilot users.

Three checklists must stay in step: `ship-checklist.md`, the Notion **Tasks**
database (under the *Anchor* page), and the Ship Readiness artifact
(https://claude.ai/code/artifact/44f67c4b-a54b-4c2c-af29-dce669095bea).
**The artifact is the one that silently rots** — it was a full day stale on
19 Aug while the other two were current. Its ticks are localStorage keyed on
`anchor-readiness-ticks-vN`; **bump N whenever you mark things done**, or a
returning browser keeps showing the old state forever. Currently `v10`
(36 of 60 ticked) — the 19 Aug findings edits did **not** bump it, correctly:
the rule is the authored *done-state*, and adding findings changed none of it.

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

Counts as of 2026-08-19, re-counted: `ship-checklist.md` **33 done / 9 partial
/ 20 open** (top-level boxes only — sub-bullets carry no box); Notion **46 done
of 87**, 1 in progress, 40 not started.

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
- SourceKit reports phantom "cannot find type in scope" errors. Trust xcodebuild.

---

## Done on 2026-08-19

- **The `_CORRECTED` fallback question is closed** (`bc6dd91`), and *not* the way
  it was written up. `usesAcademicFeatures` now requires the **full** academic
  set. Two corrections came out of reading the code rather than the note:
  dropping the model from `candidateResourceNames` **would have changed
  nothing** — the loader sweeps every `.mlmodelc` in the bundle and `Anchor/`
  is a synchronised Xcode group, so a model ships by existing in the directory
  — and the saving was **3.2 MB compiled, not 7.5 MB** (7.2 MB is the source
  `.mlmodel`; the app is 685 MB anyway). Keeping `_CORRECTED` is now safe, so
  reclaiming its 3.2 MB is an ordinary non-urgent call, not a correctness one.
- **The four §9 manual passes are scripted** in `QA-PROTOCOL.md` (`a6714a7`),
  left `[~]` because a protocol is not a pass.

## Next, in order

Everything Claude-owned and unblocked is done. What is left needs Rishab's
accounts, his hardware, his decisions, or a partner who does not exist yet.

1. **Send the outreach emails.** `OUTREACH.md` has both drafts ready — academy
   and co-op — with the reasoning beside each, and **`PROSPECTS.md` (2026-08-19)
   now has the fourteen organisations to send them to**, with contact routes and
   which draft fits each. This is the real gate on the whole timeline and
   nothing else moves without it. **Read `PROSPECTS.md`'s findings section
   first** — three of the four contradict something the plan assumed:
   - The segment mostly runs **Canvas, not Google Classroom** (0 of 6
     discoverable LMSs were Google Classroom). Small, biased sample — **not** a
     reason to build the Canvas connector, but it makes question 1 in the
     emails the most load-bearing line in them.
   - **Most local homeschool co-ops meet in person**, so that pool is far
     smaller than the academy pool. The co-op *draft* is still right; its real
     audience is the founder-led online programme. Do not split 50/50.
   - **Kepler Education is the per-teacher branch in disguise** — independent
     contractors, no school Zoom account, no admin. Cut the "hour of a Zoom
     admin's time" sentence from that one email.
   - Two warm routes the prospects publish themselves: The Potter's School runs
     a **public Zoom open house every Monday, 11:00 and 20:00 US ET**, and
     Excelsior Classes publishes a Calendly for a free 30-minute call.
2. ~~Submit the pilot form once and check spam.~~ **Done 2026-08-19 — it
   lands, and `/apply` is linkable.** See *Do not redo* above. What this
   changes for item 1: the outreach drafts keep their `/apply` sentence, so
   there is no edit to make before sending.
3. **Apple Developer enrollment** — still the longest lead, and it gates the
   certificate → notarization → anyone installing at all → QA Pass A.
4. **Decide the Zoom account model.** The per-teacher branch is now *priced*
   three ways, not two: no participant scopes, a 40-minute cap, **and no bot**
   (see *Do not redo* above). Per-school is no longer a review-queue dodge —
   it is the only branch where Anchor has a live signal at all.
5. **Settle whether Zoom accepts a PKCE-only token exchange.** Found 2026-08-19
   and not resolved on purpose. `OAuthClientDefaults` says Zoom *"requires this
   on the token exchange even for a native app"*; `ZoomOAuthHandler.post` has a
   PKCE-only branch that assumes it does not. Both cannot be right, the shipped
   secret is empty so the PKCE-only branch is what runs on a teacher's Mac, and
   it has **never run**. `hasClientCredentials` is only `clientID != nil`, so
   Connect Zoom is *live* on a fresh install. If the comment is the true one,
   every pilot teacher clears Zoom's consent screen and then fails at the token
   exchange. **Do not settle it by reading docs** — that is the mistake this
   project keeps making. It wants the one click, or a throwaway manual exchange
   against the Development app.

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
