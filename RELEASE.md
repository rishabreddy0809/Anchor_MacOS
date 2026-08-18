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
