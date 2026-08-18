# Anchor — Ship Checklist (v1)

Decisions to lock in first, since they change what "done" means for everything below.

- [ ] **Zoom account model**: per-school (school's Zoom admin installs the S2S app under their Business/Education account — email matching + Dashboard data just works) vs. per-teacher on any plan (broader reach, but verified-email matching will never work for teachers on Basic/Pro — name-matching + manual override becomes the primary mechanism, not a fallback)
  - Still open, but the price of the per-teacher branch is now measured rather than assumed. Confirmed 2026-08-17: the two participant scopes (`dashboard:read:list_meeting_participants:admin`, `report:read:list_meeting_participants:admin`) are not on the app and cannot be added from an account below Business/Education/Enterprise — the Marketplace scope picker shows no Dashboard or Report category to select them from. So on a per-teacher pilot the REST path never returns a participant list at all, and the Meeting SDK bot is not the richer of two sources but the only source of live engagement signal. Picking per-teacher means the bot (§5, §7) is a hard dependency of shipping, not a differentiator on top of it.
- [ ] **Distribution channel**: direct download (Developer ID + notarization) vs. Mac App Store — see reasoning below, but pick one before building the packaging pipeline
- [ ] **Pricing model**: free, per-teacher subscription, per-school license — affects whether you need StoreKit (App Store) or your own payment integration (direct)

---

## 1. Legal & compliance — do this early, it gates everything else

- [ ] Privacy policy, hosted at a real public URL
- [ ] Terms of service, hosted at a real public URL
- [ ] Written data-retention policy — you already have real substance here (grades held in memory only, never written to disk; and since 2026-08-17 `SessionArchive` enforces a window instead of keeping everything forever — one term / 120 days by default, one school year or "keep everything" as alternatives, under Settings → Data & Privacy, pruning on load, when a class ends, and immediately when the window is shortened, with Anchor's own `session-archive.corrupt-*` / `.backup-*` sidecars ageing out on the same clock). The mechanism is done; the *document* is not, and that is what this line is about — get it into plain language a school's IT/legal reviewer can read in two minutes
- [ ] FERPA posture documented — Anchor's user is the teacher, not the student directly, but you're touching grades and assignment data, so be deliberate and explicit about this rather than silent
- [ ] Review Zoom's Marketplace developer terms for apps that process meeting audio/video/chat content
- [ ] A real homepage (needed for Google verification anyway, and for App Store / notarized-app credibility either way)

## 2. Google OAuth verification — start this immediately, it's the longest external clock

- [ ] Move OAuth consent screen off Testing mode
- [ ] Submit for Google verification (Classroom scopes are sensitive — expect to need a screen recording showing each scope's actual use)
- [ ] Have privacy policy + ToS URLs ready before submitting (Google requires them)
- [ ] Expect 2–6 weeks — kick this off in parallel with everything else, don't sequence it last

## 3. Zoom Marketplace readiness

- [x] **Rename the Marketplace app** — done 2026-08-17. The consent screen quotes the app name verbatim and read *"General app 392 would like permission to:"*; it now reads *"Anchor would like permission to:"*. Edited on App Listing → App Name, not the pencil beside the header. Re-check this on any second app created for production, which starts life with a generated name again.
- [ ] Confirm the Meeting SDK app and Server-to-Server app are both properly activated for production use (not just dev/test mode)
- [ ] If going per-teacher model: build a real "Connect your Zoom account" OAuth flow (Zoom's OAuth app type, not Server-to-Server) — mirror the pattern already built for Google
- [ ] If going per-school model: document the admin install process clearly, since a school's Zoom admin is doing this, not the end-user teacher

## 4. Credential distribution — get this out of Settings entirely

- [ ] Ship your own Zoom Meeting SDK key + Google OAuth client ID/secret baked into the app binary (both are already designed to be non-confidential per your own code's PKCE reasoning — don't make users paste keys)
- [ ] Cut Settings down to a single "Connect" button per service; remove the manual client ID/secret entry fields from the shipped build
- [x] **Confirm no secrets ship** — verified 2026-08-18, and this line was stale: `BotCredentials.swift` no longer exists anywhere in the repo. What ships is `OAuthClientDefaults`, and all three secret fields are empty strings (`zoomClientSecret`, `meetingSDKSecret`, `googleClientSecret`). Only the Zoom client ID, the Meeting SDK key and the Google client ID carry values, and none of those is confidential — they are public identifiers for a PKCE native client, which is the whole reason the flow uses PKCE. A source-wide scan for assigned secret-shaped literals returns nothing.

## 5. Known bugs to fix

- [x] `PKCE.makeCodeVerifier()` discarded the `SecRandomCopyBytes` status and used the buffer regardless — fixed 2026-08-17, it now checks the status and traps. A silent RNG failure would have handed out a predictable verifier while every other part of the flow looked correct, which is the kind of thing that never shows up in a successful sign-in test.
- [x] **Bot appears as a scored "student" in its own roster** — already fixed; this line was stale. `ZoomMeetingSDKBridge` sets `isSelf: info.isMySelf()` and `MeetingRoles.isBot` checks it first, ahead of the host check, so the bot is filtered even in a meeting it happens to host. REST reports no `isSelf`, so on that path the bot is matched by the name it joined under — as a prefix, to survive the suffix Zoom appends when a display name is already taken. Pinned by `MeetingRolesTests` on 2026-08-17. One trap left in place deliberately: `botName` is prefix-matched, so a deployment overriding the default with something short like "Anchor" *would* claim a student called "Anchor Patel" and drop them from the dashboard with nothing on screen to say so. The shipped default ("Anchor (engagement assistant)") is long and parenthesised precisely so that stays hypothetical — anything replacing it has to be too.
- [~] Reconnection handling: **the arithmetic is now verified; the live rehearsal is not.** Split out of `ZoomViewModel` into `PollSchedule` and covered by `PollScheduleTests` on 2026-08-17 — the backoff ladder, its ceiling, jitter bounds, and which failures keep polling versus stop and ask for the teacher. Two defects fixed on the way: (1) `rateLimited(retryAfter:)` had carried Zoom's own `Retry-After` since it was introduced and **nothing ever read it**, so a 429 saying "wait two minutes" was answered fifteen seconds later — earning another 429 and walking the ladder up exactly when the loop needed to stop; it is now taken as a floor against the ladder, capped so a bogus value can't park a lesson past the bell. (2) The wait loop re-drew the random jitter on every 500ms slice, so the "retrying in Ns" shown to the teacher was an independent sample from the wait actually in progress, and the jitter collapsed toward its base instead of decorrelating clients; it is now drawn once per cycle. Laptop sleep needs no handling and gets none — the loop measures against a wall clock, so a lid closed for an hour comes back with the interval long exceeded and syncs at once, which is what a teacher reopening mid-lesson wants. **Still open:** the actual manual pass — drop a real meeting, sleep a real laptop, pull real Wi-Fi — since none of the above exercises the loop, only the numbers it consults.
- [ ] Multi-participant scale: validate UI, polling cadence, and Classroom sync cost with a real class size (20–30 students), not just 2–3 known test accounts

## 6. Product polish for real (non-you) users

- [ ] First-run onboarding flow — currently assumes a technical user who understands OAuth client IDs and meeting passcodes
- [~] Simplify meeting join to accept a pasted Zoom link — **built and tested 2026-08-17**, but not yet seen on screen. `ZoomMeetingLink` parses the whole invitation a calendar sends: join URLs (`/j/`, `/w/`, `/s/`, vanity subdomains, `zoommtg://`), the grouped "Meeting ID: 812 3456 7890" label, a bare number typed by hand, and both passcode spellings. It collapses the paste into the two fields as it lands, so the teacher sees what Anchor understood before they join. Two decisions worth knowing: it *never* scans free text for a plausible digit run, because a Zoom invitation's dial-in block contains "+1 312 626 6799" — eleven digits stripped of punctuation, exactly a personal-meeting-id length — so digits are only read from somewhere that names them; and where an invitation carries both passcodes, the labelled one wins over the URL's `pwd=`, since the latter is encoded for the browser while `ZoomSDKJoinMeetingElements.password` wants what a human types. A personal-room link (`zoom.us/my/…`) carries no id at all and now says so in the panel instead of failing deep in the SDK. **Still open:** actually pasting into the running app — 19 parser tests pass and it compiles, but the field behaviour has not been watched by a human.
- [ ] Empty states and error states reviewed for plain-language clarity (a teacher, not a developer, is reading these)
- [ ] App icon and branding assets finalized
- [ ] In-app support/contact path (email or link) for when something breaks

## 7. The differentiator feature (optional for v1, but this is your actual moat)

- [ ] Live transcript capture via `ZoomSDKCloseCaptionController` (confirmed available in the SDK you're already linking)
- [ ] Topic extraction from the rolling transcript window
- [ ] Cross-reference extracted topic against Classroom assignment titles / academic snapshot
- [ ] Trigger-gated recommendation generation (only fire on silent + academically-weak-on-this-topic, not every transcript line)
- [ ] Surface generated recommendations in the existing "Suggested Next Steps" panel, clearly tagged as AI-generated

## 8. Distribution mechanics

**Either way:**
- [x] Deployment target lowered to **macOS 14.0** (was 26.5) on 2026-08-17. The 26.5 floor existed solely because `FoundationModelAnalyzer` referenced FoundationModels unconditionally — one optional phrasing feature setting the hardware requirement for the whole product, which for a pilot audience of teachers on school-issued Macs meant almost nobody could install it. FoundationModels is now behind `@available(macOS 26.0, *)` with `#available` at its three entry points, and the vendored Zoom SDK only ever asked for 10.15. 13.0 remains blocked by SwiftUI APIs newer than it — `ContentUnavailableView`, `SettingsLink`, the two-argument `onChange`, `symbolEffect` and `variableColor` need 14.0, and `scrollBounceBehavior` needs 13.3 — so dropping further is a UI rewrite rather than a build setting, and 14.0 is the floor unless that becomes worth doing.

**If direct download:**
- [ ] Enroll in Apple Developer Program ($99/yr)
- [ ] Sign with Developer ID Application certificate, hardened runtime enabled
- [ ] Notarize via `notarytool`, staple the ticket
- [ ] Package as a `.dmg`
- [ ] Host the download (your own site or GitHub Releases)
- [ ] Set up Sparkle for auto-updates

**If App Store:**
- [ ] Enroll in Apple Developer Program ($99/yr)
- [ ] App Store Connect listing: screenshots, description, App Privacy "nutrition label" (this will require you to accurately disclose the Classroom/Zoom data you touch)
- [ ] Review Apple's stance on background-running meeting-observer apps before investing further — this is the single biggest risk of rejection for this category of app, worth a sanity check early rather than after full submission
- [ ] Budget for review cycles on every future update, not just launch

## 9. QA pass before calling it v1

- [x] Automated coverage exists at all — an `AnchorTests` XCTest target, **156 passing tests** as of 2026-08-17 (the repo had none before that day). Grown in four passes, each pinning a layer where a mistake is silent rather than loud: score shaping and the three RiskLevel cut-offs; the academic escalation rules; the 16-feature vector and the cross-poll accumulators that build it (`FeatureCalculatorTests`); the Zoom redirect transports, driven over a real loopback socket (`ZoomRedirectTransportTests`); and the roster gate that decides who is scored at all (`MeetingRolesTests`). Those passes found five real defects between them — three in the feature vector, two in the redirect transports; the roster gate turned out to be already correct and is simply pinned now. See the commit messages for what and why. It still says nothing about the manual passes below, which all stay open.
- [ ] Full session, start to finish, with a real unfamiliar class size
- [ ] Network interruption recovery
- [ ] Classroom disconnect/reconnect flow
- [ ] Fresh-install onboarding walkthrough, done by someone who isn't you
- [ ] Verify no dev credentials, test account references, or debug logging ship in the release build
- [~] Run `scripts/verify-no-demo-data.sh` against the exact build you are shipping — **passes as of 2026-08-18** against the current Release build: no demo reference reachable from a Release compile, Release build confirmed (no debug dylib), no demo symbols in the symbol table, none of the 36 long fabricated literals present. Left at `[~]` rather than `[x]` on purpose: the guarantee is per-binary, so this has to be re-run against the actual signed artifact you ship, not against whatever is in DerivedData today.

## 10. Launch readiness

- [ ] Support channel live and monitored
- [ ] Versioning/release process decided (even something simple)
- [ ] A rollback plan if a release breaks something mid-semester for a teacher relying on it

## 11. Reach and accuracy, once real sessions have run

Both of these are gated on things that don't exist yet — a partner's LMS instance, and labelled rows from live classes — so neither can be started early by working harder. Written down now so the shape of each is settled before the day it becomes possible.

- [~] **Canvas dependency test — desk half done 2026-08-17, live half waiting on a partner.** Written up in `CANVAS_SPIKE.md`; runnable via `scripts/canvas-dependency-test.py`. On paper Canvas answers yes to everything: all five `ClassroomDataProviding` methods map to documented endpoints, the bulk submissions endpoint exists so a class is one paged call rather than N round trips, and all five academic features have a source. Two are *better* than the Google path — Canvas states `late` and `missing` as first-class booleans where `GoogleClassroomService` has to derive both. Still **no Canvas code in the repo**, deliberately: the connector decision waits on the live run.
  - **The pass/fail criterion is identity matching, not grades**, and it is the one thing the docs cannot settle. `login_id` is documented as always present; `email` and `sis_user_id` are both explicitly permission-gated and configured per institution. So the live run has to happen against the *partner's own* instance, with a token no more privileged than a real deployment's — a sandbox with permissive defaults would answer the wrong question.
  - **The finding worth acting on:** Anchor's Classroom path has no email at all any more (the `classroom.profile.emails` scope was dropped on 2026-08-17, so `AcademicSnapshot.email` is always nil on a normal install) and matches by normalised display name. If `login_id` survives a real install, Canvas identity matching would be **stronger than the Google integration already shipping**, not a compromise. Worth knowing before budgeting three weeks on the opposite assumption. Caveat: `login_id` is a stable key for joining Canvas to itself; whether it joins Canvas to *Zoom* needs one real roster beside one real participant list, which is a partner-call task the script cannot do.
- [ ] **Retrain the model on real labelled rows.** `retraining/` is set up and its README sets the honesty bar: under 200 rows you can claim *nothing* and the run is a smoke test; 200–1000 tells you whether the model beats the majority-class baseline; 1000+ supports a cautious accuracy comparison with a confidence interval. Everything shipped today was trained on synthetic data, so the first run against real labels is the first honest read this project has had. The scarce resource is labelled *struggling* students rather than rows — a class of 28 with two strugglers yields two useful positives, which is why three sessions is a floor and not a target. Labels have to be the teacher's judgement; deriving them from Anchor's own score just trains the next model to agree with this one.
  - **Know what a successful retrain switches off.** The moment a model declaring all 16 columns is loaded, `StruggleDetectionService.usesAcademicFeatures` turns true and `AcademicEscalation` — the hand-written, teacher-visible, +0.20-bounded academic rules — disables itself automatically with no Swift change. That is the intended design and it is why the 16-feature retrain is worth doing at all, but it means a retrain silently changes the path every academic signal takes to a score. Re-run the suite and read a few real students before trusting the result.
