# Anchor — continue pilot readiness

Repo: `/Users/rishabreddypaili/Documents/Anchor`
Branch: `ship/pilot-readiness` (default is `app-split`). Both are currently at
`71db659` and pushed. Tests:
`xcodebuild test -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
→ **220 passing**, 13 test files. Release config builds clean.

Deadline: term starts ~31 Aug 2026. Goal is 1–3 real pilot users.

Three checklists must stay in step: `ship-checklist.md`, the Notion **Tasks**
database (under the *Anchor* page), and the Ship Readiness artifact
(https://claude.ai/code/artifact/44f67c4b-a54b-4c2c-af29-dce669095bea).
**The artifact is the one that silently rots** — it was a full day stale on
19 Aug while the other two were current. Its ticks are localStorage keyed on
`anchor-readiness-ticks-vN`; **bump N whenever you mark things done**, or a
returning browser keeps showing the old state forever. Currently `v4`.

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
- **§7 (the differentiator) is built** — all five lines. Only a live lesson is missing.
- **Zoom API ToU §3.2.9 forbids** training ML models on Customer Content without
  Zoom's written permission; the consent exception is per-customer and the model
  "may only be used by the Customer who consented". This blocks the pooled retrain.
- SourceKit reports phantom "cannot find type in scope" errors. Trust xcodebuild.

---

## Next, in order

1. **§9 manual QA** — none of the 220 tests touch Zoom, Google or a real class,
   so this section cannot be closed by writing more of them. Needs a borrowed
   Mac and a real class.
2. **Decide the Zoom account model** (recorded as *proposed: per-school*, left
   unticked because it is Rishab's call). It decides whether §7's bot is
   optional or load-bearing.
3. **Decide the `_CORRECTED` fallback question** — a latent gap is written up in
   §11 and Notion: a 13-feature model counts as "academic", stands
   `AcademicEscalation` down wholesale, and is blind to the column the rules
   escalate on. Latent only (needs `_16` *and* `_PRODUCTION` to fail).
   Recommendation: drop it, which also removes 7.5 MB.
4. **Connect `anchor-oauth-bounce` to Git** — same trap as `anchor-landing`,
   still armed. Deliberately untouched: it is load-bearing for Zoom OAuth and
   should not be changed while nobody can verify it.

## Blocked on the human

- **Apple Developer Program enrollment** — longest lead; gates the certificate →
  notarization → anyone installing at all.
- **A real domain** — gates the Resend verified sender, which gates
  `PILOT_FROM_EMAIL`. Until then pilot applications from strangers fail
  silently; the outbound support path works, the inbound one does not.
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
