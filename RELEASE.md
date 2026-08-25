# Releasing Anchor

Written 2026-08-18, while packaging was fresh. The point of this file is that
the steps below are recoverable in October, when they will not be.

Anchor ships as a **notarized `.dmg`, downloaded directly**. Not the Mac App
Store — that is an architectural exclusion rather than a scheduling one, and the
reason is recorded in `ship-checklist.md` §8: the vendored Zoom Meeting SDK
nests six `.app` bundles carrying `us.zoom.*` identifiers, and App Store
validation requires every nested identifier to be prefixed by the parent's.
Nothing about that is fixable from this side.

---

## Version numbers

Two numbers, and they answer different questions.

| | Answers | Rule |
| --- | --- | --- |
| `MARKETING_VERSION` | What a teacher sees in Settings and in the About panel | Semantic. Currently **0.9.0**. |
| `CURRENT_PROJECT_VERSION` | Which build is newer | **Monotonic integer. Never reused, never decreased.** Currently **2**. |

Both live in `Anchor.xcodeproj/project.pbxproj` and appear in **four** build
configurations each. Change all four, or Debug and Release disagree about what
they are and the mismatch only shows up in a shipped artifact.

**Why 0.9.0 and not 1.0.** Nobody has installed this yet, and the accuracy
figure behind its core claim has never been established on real labelled data —
the site says so explicitly. `1.0` is a claim about maturity that the product
cannot yet support, and it costs nothing to keep it in reserve for the release
where a real teacher has confirmed Anchor surfaced a student they would have
missed. Going 1.0 → 0.9 was safe only because no build exists in anyone's
hands; do not do it again once one does.

**`CURRENT_PROJECT_VERSION` is the one that matters mechanically.** Sparkle
compares it to decide whether an update exists. A repeated build number means a
teacher mid-term is silently never offered the fix you shipped for them.

---

## Run the preflight first

```sh
scripts/preflight-release.sh          # or pass the path to an exported .app
```

**Added 2026-08-21, and it exists because the first notarization attempt would
have failed three times over.** Every check in it is something Apple rejects
for and that is testable locally in seconds. Step 4 below says "budget for it
failing the first time"; the point of the preflight is to have already had
those failures, cheaply, before the upload.

Run it now, before enrollment finishes. With no Developer ID certificate it
fails at check 1 and tells you that is the only thing in the way, which is a
useful answer rather than a broken script. **Two checks are expected to fail
until enrollment completes** and both clear by themselves once you sign with a
Developer ID rather than an Apple Development certificate:

- no `Developer ID Application` certificate in the keychain
- `get-task-allow` present in the entitlements

**What it already caught and what is now fixed in the build** (see `82e5bcf`):
the Copy ZoomSDK build phase was ad-hoc re-signing 22 Zoom binaries and
stripping their hardened-runtime flag; 38 vendored frameworks carried stray
`.bak` files that count as unsealed contents; and `aomhost.app` shipped a 58 MB
copy of itself in its own bundle root. All three are invisible when you run the
app and fatal at Apple's end. The app now passes
`codesign --verify --deep --strict`.

**One of those three is verified statically and not at runtime.** Removing the
duplicate `aomhost.app` leaves Zoom's signature and runtime flag intact, so the
signature never sealed it, but nothing proves the SDK does not launch the inner
copy. **Confirm the bot still joins in QA Pass B.**

## The release itself

Run from a clean tree on the release branch.

```sh
# 1. The suite must be green before anything else. It is fast; there is no
#    excuse for skipping it, and it is the only thing standing between a
#    student's name and a log file (see ReleaseHygieneTests).
xcodebuild test -project Anchor.xcodeproj -scheme Anchor \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# 2. Bump both numbers in all four configurations. Commit that on its own,
#    so the version bump is findable in the log rather than buried.

# 3. Archive with the Developer ID identity and the hardened runtime on.
#    Hardened runtime is not optional — notarization rejects without it.
xcodebuild archive -project Anchor.xcodeproj -scheme Anchor \
  -archivePath build/Anchor.xcarchive \
  -configuration Release

# 4. Export, notarize, staple. Notarization is a round trip to Apple and is
#    where 682 MB across 83 third-party frameworks surfaces signing problems
#    the local build never showed you. Budget for it failing the first time.
xcrun notarytool submit build/Anchor.dmg \
  --keychain-profile "AnchorNotary" --wait
xcrun stapler staple build/Anchor.dmg

# 5. Verify the artifact you are actually shipping — not DerivedData.
#    This guarantee is per-binary and does not carry across builds.
./scripts/verify-no-demo-data.sh /path/to/mounted/Anchor.app
```

Then check the stapled `.dmg` opens on a Mac that has never had Anchor or Xcode
on it. Gatekeeper behaves differently on a machine with a developer profile, so
your own Mac cannot answer this question.

---

## Rollback

**Keep every shipped `.dmg`, permanently.** They are small next to what they
protect, and this is the entire rollback mechanism: point the teacher at the
previous file. There is no server-side switch to flip and no staged rollout.

A teacher mid-semester relying on Anchor cannot wait for a fix, so the recovery
path is *downgrade*, not *hotfix*.

Two things make a rollback ugly, and both are worth knowing before one is
needed:

- **Sparkle will offer to "update" them straight back onto the broken build**,
  because its build number is higher. Until Sparkle is wired up this is
  hypothetical; once it is, a rollback means also pulling the appcast entry, not
  just handing over an older file.
- **`SessionArchive` is read by whatever version is running.** A downgrade is
  only safe while the archive format is unchanged. If a release ever changes
  that format, it must either stay backwards-readable or the release notes must
  say plainly that rolling back loses history.

---

## Before the first external build

Not steps, but the things that make the steps possible. Each is tracked
separately.

- Apple Developer Program enrollment — gates the Developer ID certificate,
  which gates everything above.
- A `notarytool` keychain profile stored locally (`AnchorNotary` above).
- The fresh-install click: both Connect buttons pressed on a machine with no
  developer Keychain, watching what happens *after* browser consent.
- **`Config/Secrets.xcconfig` with `GOOGLE_OAUTH_CLIENT_SECRET` filled in.**
  Without it Google Classroom cannot be connected by anyone: Google requires
  `client_secret` for a Desktop OAuth client (probed 2026-08-24 — the endpoint
  answers `client_secret is missing.`), and PKCE does not substitute for it.
  The build still succeeds and the app still runs; the Connect button simply
  refuses up front, saying setup is unfinished. **That is a silent ship, not a
  failed build**, so check the file the way you check the plist below:

  ```bash
  # Should print your secret, not an empty line.
  plutil -extract ANGoogleOAuthClientSecret raw -o - \
    "<path to built Anchor.app>/Contents/Info.plist"
  ```

  Never move this value into `OAuthClientDefaults.swift`. The repository is
  public; the secret is fine inside the shipped binary and not fine in git
  history. See `Config/Secrets.example.xcconfig`.
- **`GoogleService-Info.plist` in `Anchor/`.** Without it the app still builds,
  launches and runs — accounts simply switch off and the onboarding gate lifts
  (see `FirebaseAuthService.configureIfNeeded`). So a build missing it does not
  fail; it ships with the sign-up screen inert. Check for the file, do not wait
  to be told.

## Firebase, and what it did *not* cost the signing pipeline

Added 2026-08-24 with Anchor accounts — the project's first Swift Package
Manager dependency (the Zoom SDK is vendored, so this is genuinely new ground).

**The thing to know: it added nothing to `Contents/Frameworks`.** Firebase's
SPM distribution links statically, so `FirebaseAuth` and its dependencies end
up inside the app binary rather than as nested bundles. The framework count is
unchanged at 83, all of them still Zoom's, and `codesign --verify --deep
--strict` passes exactly as it did after commit 82e5bcf. The worry that this
would multiply the 682 MB of third-party frameworks notarization has to chew
through did not materialise — there is no new binary to sign.

What *is* worth knowing before someone greps the binary and panics:

- **Only `FirebaseAuth` is linked.** Do not add Firestore, Analytics,
  Crashlytics or Messaging without re-reading this section — Firestore alone
  drags in gRPC, leveldb and abseil as *binary* targets, which is precisely the
  nested-bundle problem this avoided. Verified absent: `grpc`, `leveldb`,
  `FIRFirestore`, `GoogleAppMeasurement`, `APMAnalytics` all return zero
  symbols.
- **`FIRAnalyticsConfiguration` *does* appear in the binary, and is not
  analytics.** It is a notification shim inside FirebaseCore that the Analytics
  SDK would observe if it were present. It is not, and no measurement code is
  linked. The privacy policy's "no analytics SDK" line is still true — this
  paragraph exists so that a future grep for `FIRAnalytics` resolves in one
  minute instead of an afternoon.
- **`Package.resolved` lists far more than is linked.** SPM resolves the whole
  `firebase-ios-sdk` manifest, so `google-ads-on-device-conversion-ios-sdk`,
  `googleappmeasurement`, `grpc-binary` and `leveldb` all appear there. Resolved
  is not linked; none of them are in the binary. Expect to be asked about it
  anyway if anyone reads that file.
- Pinned `upToNextMajorVersion` from 11.0.0; resolved to 11.15.0.
