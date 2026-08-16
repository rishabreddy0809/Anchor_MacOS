# Anchor — Ship Checklist (v1)

Decisions to lock in first, since they change what "done" means for everything below.

- [ ] **Zoom account model**: per-school (school's Zoom admin installs the S2S app under their Business/Education account — email matching + Dashboard data just works) vs. per-teacher on any plan (broader reach, but verified-email matching will never work for teachers on Basic/Pro — name-matching + manual override becomes the primary mechanism, not a fallback)
- [ ] **Distribution channel**: direct download (Developer ID + notarization) vs. Mac App Store — see reasoning below, but pick one before building the packaging pipeline
- [ ] **Pricing model**: free, per-teacher subscription, per-school license — affects whether you need StoreKit (App Store) or your own payment integration (direct)

---

## 1. Legal & compliance — do this early, it gates everything else

- [ ] Privacy policy, hosted at a real public URL
- [ ] Terms of service, hosted at a real public URL
- [ ] Written data-retention policy — you already have real substance here (grades held in memory only, never written to disk); get it into plain language a school's IT/legal reviewer can read in two minutes
- [ ] FERPA posture documented — Anchor's user is the teacher, not the student directly, but you're touching grades and assignment data, so be deliberate and explicit about this rather than silent
- [ ] Review Zoom's Marketplace developer terms for apps that process meeting audio/video/chat content
- [ ] A real homepage (needed for Google verification anyway, and for App Store / notarized-app credibility either way)

## 2. Google OAuth verification — start this immediately, it's the longest external clock

- [ ] Move OAuth consent screen off Testing mode
- [ ] Submit for Google verification (Classroom scopes are sensitive — expect to need a screen recording showing each scope's actual use)
- [ ] Have privacy policy + ToS URLs ready before submitting (Google requires them)
- [ ] Expect 2–6 weeks — kick this off in parallel with everything else, don't sequence it last

## 3. Zoom Marketplace readiness

- [ ] Confirm the Meeting SDK app and Server-to-Server app are both properly activated for production use (not just dev/test mode)
- [ ] If going per-teacher model: build a real "Connect your Zoom account" OAuth flow (Zoom's OAuth app type, not Server-to-Server) — mirror the pattern already built for Google
- [ ] If going per-school model: document the admin install process clearly, since a school's Zoom admin is doing this, not the end-user teacher

## 4. Credential distribution — get this out of Settings entirely

- [ ] Ship your own Zoom Meeting SDK key + Google OAuth client ID/secret baked into the app binary (both are already designed to be non-confidential per your own code's PKCE reasoning — don't make users paste keys)
- [ ] Cut Settings down to a single "Connect" button per service; remove the manual client ID/secret entry fields from the shipped build
- [ ] Confirm `BotCredentials.swift`'s dev-only hardcoded secrets are excluded from the shipped build (or replaced with the production app's own credentials) and never committed to a public repo

## 5. Known bugs to fix

- [ ] Bot appears as a scored "student" in its own roster — filter using the SDK's `isMySelf` flag (currently unused in `ZoomMeetingSDKBridge.swift`)
- [ ] Reconnection handling: verify behavior when a meeting drops, laptop sleeps, or Wi-Fi blips mid-session — currently untested
- [ ] Multi-participant scale: validate UI, polling cadence, and Classroom sync cost with a real class size (20–30 students), not just 2–3 known test accounts

## 6. Product polish for real (non-you) users

- [ ] First-run onboarding flow — currently assumes a technical user who understands OAuth client IDs and meeting passcodes
- [ ] Simplify meeting join to accept a pasted Zoom link (auto-parse meeting number/passcode) rather than requiring both fields separately
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

- [ ] Full session, start to finish, with a real unfamiliar class size
- [ ] Network interruption recovery
- [ ] Classroom disconnect/reconnect flow
- [ ] Fresh-install onboarding walkthrough, done by someone who isn't you
- [ ] Verify no dev credentials, test account references, or debug logging ship in the release build
- [ ] Run `scripts/verify-no-demo-data.sh` against the exact build you are shipping — proves the fabricated classroom in `DemoData.swift` is absent from the binary, and fails a Debug build outright

## 10. Launch readiness

- [ ] Support channel live and monitored
- [ ] Versioning/release process decided (even something simple)
- [ ] A rollback plan if a release breaks something mid-semester for a teacher relying on it
