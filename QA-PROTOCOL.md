# Anchor — the manual QA pass (§9)

Four lines in `ship-checklist.md` §9 stay open no matter how many tests get
written, because **all 229 automated tests run against code and none of them
touch Zoom, Google, or a real class**. This file is the script for closing
them. It exists so the pass is *run*, not improvised: a borrowed Mac and a
real class are both scarce, and the failure mode is getting one and realising
afterwards that the interesting half was never exercised.

It is a protocol, not a checklist — every step says what to watch for and what
counts as a failure, because "it worked" is not a result anyone can act on
later.

**Scope.** Passes A–D below close exactly these four lines:

| §9 line | Pass |
|---|---|
| Fresh-install onboarding walkthrough, done by someone who isn't you | **A** |
| Full session, start to finish, with a real unfamiliar class size | **B** |
| Network interruption recovery | **C** |
| Classroom disconnect/reconnect flow | **D** |

Nothing else in §9 is closed by this file, and none of these may be ticked
from a partial run — see the recording rules at the end.

---

## 0. Before the day

**Build the artifact you will actually ship, and test that one.** Not
DerivedData. `scripts/verify-no-demo-data.sh` guarantees *per binary*, so it
has to run against the signed `.dmg` that goes to a teacher — that is exactly
why its §9 line is `[~]` and not `[x]`.

```bash
xcodebuild build -project Anchor.xcodeproj -scheme Anchor \
  -configuration Release -destination 'platform=macOS'
scripts/verify-no-demo-data.sh <path to the built Anchor.app>
```

Bring: the `.dmg`, a phone with a hotspot (Pass C needs a network you can kill
without killing the class's), and the Zoom and Google accounts the pilot
teacher will really use — **not** yours. Half the point of Pass A is that the
consent screens are seen by an account that has never granted anything.

### Making a Mac genuinely fresh — the step that is easy to skip

Dragging Anchor to the Trash does **not** produce a fresh install. Four
Keychain services and a defaults domain survive it, and any one of them makes
Pass A test a path no pilot user will ever walk:

```bash
# Credentials — four separate services, all of them persist.
security delete-generic-password -s com.anchor.zoom.credentials
security delete-generic-password -s com.anchor.zoom.oauth
security delete-generic-password -s com.anchor.zoom.meetingsdk
security delete-generic-password -s com.anchor.google.classroom

# Onboarding state, settings, and the archive pointer.
defaults delete Rishab-Reddy.Anchor
```

Each `security` call deletes **one** item and exits non-zero when there is
nothing left, so run each until it reports `could not be found`. Then confirm:

```bash
security dump-keychain 2>/dev/null | grep -c 'com\.anchor\.'   # expect 0
defaults read Rishab-Reddy.Anchor 2>&1 | head -1               # expect "does not exist"
```

A borrowed Mac that has never had Anchor needs none of this, which is why a
borrowed Mac is worth more than a cleaned one — it cannot lie to you.

---

## Pass A — fresh-install onboarding, driven by someone who isn't you

**Run by a person who has not seen Anchor.** You may watch; you may not touch
the trackpad, and you may not explain. Every sentence you find yourself
wanting to say is a defect in the copy — write it down instead of saying it.
That is the deliverable of this pass.

Onboarding is six steps: **welcome → name → zoom → classroom → preferences →
done**. Walk all six.

1. **Open the `.dmg` and launch.** Gatekeeper is the first real test. On a Mac
   that has never seen this developer, an unnotarised build is refused with
   *"Anchor is damaged and can't be opened"* — which is a lie about the
   binary and reads as one. Record the exact wording seen, and whether the
   tester found their way past it unaided. *If Apple Developer enrollment is
   still pending, this step fails by construction — record it as blocked
   rather than working around it with right-click-Open, because no teacher
   will do that.*
2. **Welcome, name.** Nothing to verify beyond the tester not stalling.
3. **Zoom step — press Connect and follow it all the way through.** This is
   the step nobody has watched end to end. The browser opens Zoom's consent
   screen; approving bounces through
   `https://anchor-oauth-bounce.vercel.app/oauth/zoom`, which forwards `code`
   and `state` to `http://127.0.0.1:51789/oauth/zoom` inside the app.
   - Watch **what happens after consent** — the handoff back from the browser
     to the app is the unobserved part. Does the app come forward on its own?
     Does the browser tab say something sensible if it does not?
   - Failure looks like: a browser tab left sitting on the bounce page, or an
     `Invalid redirect URL` from Zoom, or the app still saying "not connected"
     after the browser says it worked.
4. **Classroom step — press Connect and follow it through.** Same shape,
   Google's consent screen.
   - **Watch the tick boxes, and deliberately leave one unticked on a second
     run.** Google presents the four Classroom scopes individually and grants
     only what the teacher ticks — Anchor checks afterwards rather than
     assuming (`GoogleTokens.missingClassroomScopes`). A teacher skimming this
     screen and ticking three of four is *likely*, not hypothetical, and the
     app has to say which permission is missing and what it costs. Run it once
     accepting everything, then once withholding
     `classroom.student-submissions.students.readonly`, and record what the
     app told the tester.
   - **Whether an *unverified app* interstitial appears depends on the OAuth
     consent screen's publishing status, so record which you saw rather than
     assuming.** Anchor requests no sensitive or restricted scopes any more
     (`classroom.profile.emails` was dropped on 2026-08-17), so there is no
     verification gate — but if the consent screen is still in *Testing*, the
     tester's account must be on the test-users list or they cannot get in at
     all. Check that before the tester arrives; it is a five-minute fix
     beforehand and a dead pass on the day.
5. **Preferences, done.** Then confirm the app opens onto its real empty
   state, not a populated one. **Any student data visible here is a
   release-blocking failure** — demo data is gated behind `ANCHOR_DEMO_DATA=1`
   and must be unreachable in a Release build.

**Record:** every sentence you wanted to say out loud, every pause longer than
about ten seconds, and the exact text of any error. Those three lists are what
this pass produces.

---

## Pass B — a full session, with a real unfamiliar class

Not your own test meeting with two laptops. The line says *unfamiliar class
size* because the things that break at 28 students do not break at 3:
name-matching collisions, poll pacing, and whether the dashboard is readable
at all when the list does not fit.

1. Start the real class in Zoom. Connect Anchor to it and leave it running
   **for the whole lesson** — a five-minute spot check does not close this
   line, because scores are built from accumulated history.
2. **Check roster matching early**, while there is still time to react.
   Classroom matching runs on **normalised display names**, since Anchor has
   no email for a student any more. So a student whose Zoom display name is
   "Sam" and whose Classroom name is "Samuel Okafor" **will not match**, and
   is scored by the 11-feature engagement model instead of the 16-feature one.
   - **A class with two students whose names normalise alike shows both as
     unmatched**, deliberately — `AcademicMatchTable.byName` refuses an
     ambiguous name rather than guessing. They have to be linked by hand
     (`ManualRosterLinks`). Do that for at least one student and confirm the
     academic data appears for them afterwards; this is the recovery path for
     every collision a real roster produces, and it has never been used on a
     real name.
   - Count how many of the class matched. That number is the single most
     useful thing this pass produces — it is the real-world measurement behind
     the Canvas `login_id` question in §11, and nothing in the repo can
     estimate it.
3. **Read two or three students against your own judgement of the lesson.**
   Not "is the number high" — *do you agree*. Write down where you disagree
   and why. This is the first honest read the model has ever had; everything
   shipped was trained on synthetic data.
4. **Open a student's detail view and read the academic factors.** Each is a
   named rule with a weight. Confirm they say something a teacher would
   recognise, and that the reassuring ones ("no missing work") are visually
   distinct from the concerns — a teacher scanning a list of worries must not
   read good news as one.
5. After the lesson, confirm the session is in history and the retention copy
   says **120 days**.

---

## Pass C — network interruption recovery

Do this **outside** a real class. It deliberately breaks things, and the
recovery path takes up to 15 minutes to observe fully.

Run Anchor against a live meeting on the **phone hotspot**, then turn the
hotspot off. What should happen:

- The dashboard says the connection is struggling **in a teacher's words**.
  Any error text naming a status code, an endpoint, or a Swift type is a
  failure — `SupportContactTests` pins this for known strings, but the live
  path can compose new ones.
- Anchor backs off rather than hammering: intervals grow with consecutive
  failures, capped at **900 s**, and honour Zoom's `Retry-After` when sent.
- **The last known roster stays on screen.** Blanking the class because the
  network dropped is the failure worth catching here — the teacher loses the
  lesson's context for a transient Wi-Fi blip.

Turn the hotspot back on. Anchor should recover **without being restarted and
without being reconnected by hand**. Time how long that takes; up to ~15
minutes is the designed ceiling, but if it is that long the teacher will have
quit and restarted first — record it, because that is a real finding about the
ceiling being too high for a 50-minute lesson.

Also worth doing once: close the lid for ten minutes and reopen it mid-meeting.
The loop measures elapsed wall-clock time, so it should sync **immediately** on
wake rather than finishing a wait that began before the interruption.

---

## Pass D — classroom disconnect / reconnect

1. With Classroom connected and a class loaded, go to Settings and
   **disconnect** Google Classroom.
   - The academic columns must disappear from the students, and the app must
     keep scoring on engagement alone rather than showing an error state.
   - **Watch what happens to the scores.** Disconnecting flips every student
     from the 16-feature model to the 11-feature one *and* switches
     `AcademicEscalation` back on. Scores should move; a student whose score
     does not change at all across that switch is worth a second look.
2. **Reconnect.** Confirm it does not demand a full re-consent if the grant is
   still valid, and that academic data returns without a restart.
3. **Revoke Anchor's access from the Google account page** (not from inside
   Anchor) and let the app discover it on its next poll. This is the case a
   real teacher hits months later, and the only one that exercises the 401
   refresh path against a grant that is genuinely gone.
   - Expect a plain-language prompt to reconnect. A silent stop, or academic
     data quietly frozen at its last values, is the failure here — the second
     is worse, because the dashboard keeps looking correct.

---

## Recording the result

For each pass write, in `ship-checklist.md` §9: the **date**, **who ran it**,
the **build version** (`0.9.0`, build 2 at time of writing), and what broke.
"Passed" on its own is not a result — six months from now nobody can tell
whether the interesting half was exercised.

**Tick rules**, which exist because several lines were found stale:

- `[x]` only when the pass ran **start to finish** on the shipping artifact.
- `[~]` when it ran partly, **with the untested half named explicitly**. A
  Pass C where the hotspot came back but nobody waited for recovery is `[~]`,
  and the note says so.
- A pass run on a Mac that was cleaned rather than borrowed is `[~]`, not
  `[x]`, unless the Keychain and defaults checks in §0 both came back empty.

Then sync all three places or they drift: this file's §9 lines, the Notion
**Tasks** database, and the Ship Readiness artifact — **bumping its
`anchor-readiness-ticks-vN` key**, or a returning browser shows the old state
forever.
