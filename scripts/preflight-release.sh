#!/bin/bash
#
# preflight-release.sh — everything that can be checked BEFORE spending a
# notarization round trip.
#
# Why this exists. RELEASE.md step 4 says "budget for it failing the first
# time", and the readiness artifact budgets a full day for the sign → notarize
# → staple pass, because "682 MB across 83 third-party frameworks will surface
# signing problems the local build never showed you". A notarization round trip
# is minutes of upload plus minutes of Apple's queue, and it reports one class
# of problem at a time. Every check below is a thing Apple would reject for,
# testable locally in seconds. The point is to arrive at `notarytool submit`
# having already failed everything that can fail cheaply.
#
# Written 2026-08-21, before the Developer ID certificate exists, and it is
# meant to be run now: with no certificate it fails at check 1 and tells you
# that is the only thing standing in the way. That is a useful answer, not a
# broken script.
#
# Usage:
#   scripts/preflight-release.sh                 # checks the repo + last Release build
#   scripts/preflight-release.sh /path/to/App    # checks a specific .app (use the EXPORTED one)
#
# Exit codes: 0 all clear, 1 something Apple would reject, 2 usage error.

set -uo pipefail

# Not `set -e`: this script's whole job is to run *every* check and report all
# failures at once. Stopping at the first one would reproduce exactly the
# one-problem-per-round-trip behaviour it exists to avoid.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAIL=0
WARN=0
pass() { printf "  \033[32mok\033[0m    %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }
warn() { printf "  \033[33mwarn\033[0m  %s\n" "$1"; WARN=$((WARN+1)); }
head2() { printf "\n\033[1m%s\033[0m\n" "$1"; }

# ---------------------------------------------------------------------------
# 1. The certificate
# ---------------------------------------------------------------------------
# Checked first and reported plainly, because until the Apple Developer Program
# enrollment completes this is the only failure and everything below it is
# noise. "Apple Development" is NOT a substitute: notarization rejects a
# development-signed binary, and it is the identity a default Release build
# picks, so the wrong one is the easy mistake rather than an unlikely one.
head2 "1. Signing identity"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)"
if echo "$IDENTITIES" | grep -q "Developer ID Application"; then
    pass "Developer ID Application certificate present"
    echo "$IDENTITIES" | grep "Developer ID Application" | sed 's/^/        /'
else
    fail "no 'Developer ID Application' certificate in the keychain"
    if echo "$IDENTITIES" | grep -q "Apple Development"; then
        echo "        An 'Apple Development' certificate exists. It is NOT usable here:"
        echo "        notarization rejects development-signed binaries, and a default"
        echo "        Release build will pick it silently. Enrollment is the blocker."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Build settings that notarization requires
# ---------------------------------------------------------------------------
# Read from `-showBuildSettings` rather than grepped out of project.pbxproj,
# because the pbxproj holds per-configuration values and the question is what
# the Release configuration actually resolves to. This project has already been
# bitten by reading intent instead of resolution: DEVELOPMENT_TEAM is set in
# the pbxproj while the built artifact is ad-hoc signed with no team at all.
head2 "2. Release build settings"
SETTINGS="$(cd "$REPO" && xcodebuild -project Anchor.xcodeproj -scheme Anchor \
    -configuration Release -showBuildSettings 2>/dev/null)"
setting() { echo "$SETTINGS" | grep -E "^ *$1 = " | head -1 | sed 's/.*= //'; }

if [ -z "$SETTINGS" ]; then
    fail "could not read build settings (xcodebuild -showBuildSettings returned nothing)"
else
    [ "$(setting ENABLE_HARDENED_RUNTIME)" = "YES" ] \
        && pass "ENABLE_HARDENED_RUNTIME = YES" \
        || fail "ENABLE_HARDENED_RUNTIME is not YES — notarization rejects without it"

    ENT="$(setting CODE_SIGN_ENTITLEMENTS)"
    if [ -n "$ENT" ] && [ -f "$REPO/$ENT" ]; then
        pass "entitlements wired: $ENT"
        # The SDK loads Zoom-signed code lazily during sdkAuth. Without this
        # entitlement library validation refuses it and sdkAuth fails locally,
        # which is indistinguishable from a bad JWT. See Anchor.entitlements.
        grep -q "disable-library-validation" "$REPO/$ENT" \
            && pass "disable-library-validation present (the Zoom SDK needs it)" \
            || fail "disable-library-validation missing — the Meeting SDK will fail at sdkAuth"
    else
        fail "CODE_SIGN_ENTITLEMENTS not set or file missing"
    fi

    MV="$(setting MARKETING_VERSION)"; CV="$(setting CURRENT_PROJECT_VERSION)"
    [ -n "$MV" ] && [ -n "$CV" ] \
        && pass "version $MV ($CV)" \
        || fail "MARKETING_VERSION / CURRENT_PROJECT_VERSION not both set"
    echo "        Bump both before shipping; RELEASE.md step 2 wants that as its own commit."
fi

# ---------------------------------------------------------------------------
# 3. The artifact
# ---------------------------------------------------------------------------
head2 "3. The built artifact"
if [ $# -ge 1 ]; then
    APP="$1"
else
    APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "Anchor.app" \
        -path "*Release*" -not -path "*Index.noindex*" 2>/dev/null | head -1)"
fi

if [ -z "${APP:-}" ] || [ ! -d "$APP" ]; then
    warn "no Release Anchor.app found — build one, or pass its path"
    echo "        Checks 3 to 5 skipped."
else
    echo "        $APP"
    echo "        $(du -sh "$APP" 2>/dev/null | cut -f1)"

    OUTER="$(codesign -d --verbose=2 "$APP" 2>&1)"
    OUTER_FLAGS="$(echo "$OUTER" | grep -oE 'flags=0x[0-9a-f]+\([^)]*\)')"

    if echo "$OUTER_FLAGS" | grep -q "adhoc"; then
        fail "outer app is ad-hoc signed — $OUTER_FLAGS"
        echo "        This is what CODE_SIGNING_ALLOWED=NO produces (the test command"
        echo "        uses it). Ad-hoc is not notarizable. Build without that flag."
    elif echo "$OUTER_FLAGS" | grep -q "runtime"; then
        pass "outer app has hardened runtime — $OUTER_FLAGS"
    else
        fail "outer app lacks the hardened runtime flag — $OUTER_FLAGS"
    fi

    # get-task-allow is the single most common notarization rejection. It is
    # added by *development* signing and is invisible until Apple says no, so
    # it is exactly the class of thing this script exists to catch.
    if codesign -d --entitlements - --xml "$APP" 2>/dev/null \
        | plutil -convert xml1 -o - - 2>/dev/null | grep -q "get-task-allow"; then
        fail "get-task-allow is present in the entitlements"
        echo "        Apple rejects this. It means the app was signed with a development"
        echo "        certificate rather than Developer ID."
    else
        pass "no get-task-allow entitlement"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Every nested binary
# ---------------------------------------------------------------------------
# The expensive one, and the reason a day was budgeted. One unsigned or
# non-runtime binary anywhere in 685 MB fails the whole submission, and Apple
# names them a few at a time.
#
# Measured 2026-08-21 on the vendored SDK: Zoom ships its frameworks and dylibs
# already carrying flags=0x10000(runtime), so a correct build has nothing to
# fix here. A build made with CODE_SIGNING_ALLOWED=NO re-signs 23 of them
# ad-hoc and strips the runtime flag. **So a failure here is far more likely to
# mean "you scanned the wrong build" than "Zoom shipped something broken".**
head2 "4. Nested binaries (this is the one that costs a day when it goes wrong)"
if [ -n "${APP:-}" ] && [ -d "$APP" ]; then
    total=0; unsigned=0; noruntime=0; adhoc=0
    BAD="$(mktemp)"
    while IFS= read -r b; do
        [ "$b" = "$APP" ] && continue
        total=$((total+1))
        out="$(codesign -d --verbose=2 "$b" 2>&1)"
        if echo "$out" | grep -q "not signed at all"; then
            unsigned=$((unsigned+1)); echo "unsigned:   ${b#$APP/}" >>"$BAD"; continue
        fi
        flags="$(echo "$out" | grep -oE 'flags=0x[0-9a-f]+\([^)]*\)')"
        echo "$flags" | grep -q "adhoc"   && { adhoc=$((adhoc+1));   echo "adhoc:      ${b#$APP/}" >>"$BAD"; }
        echo "$flags" | grep -q "runtime" || { noruntime=$((noruntime+1)); echo "no-runtime: ${b#$APP/}" >>"$BAD"; }
    done < <(find "$APP" \( -name "*.framework" -o -name "*.dylib" -o -name "*.app" \))

    echo "        scanned $total nested binaries"
    if [ "$unsigned" -eq 0 ] && [ "$noruntime" -eq 0 ] && [ "$adhoc" -eq 0 ]; then
        pass "all $total signed, none ad-hoc, all hardened-runtime"
    else
        fail "$unsigned unsigned, $adhoc ad-hoc, $noruntime without hardened runtime"
        sort -u "$BAD" | head -30 | sed 's/^/        /'
        [ "$(sort -u "$BAD" | wc -l)" -gt 30 ] && echo "        ... $(( $(sort -u "$BAD" | wc -l) - 30 )) more"
        echo "        If this is a CODE_SIGNING_ALLOWED=NO build, rebuild before believing it."
    fi
    rm -f "$BAD"

    # --deep --strict is what Gatekeeper effectively does on first launch.
    # Worth running even though `codesign` calls it deprecated for signing:
    # for *verification* it is still the closest local proxy for the check the
    # pilot teacher's Mac will make.
    # Captured to a variable rather than piped straight into grep -q.
    # `set -o pipefail` is on, and `grep -q` exits the instant it matches,
    # which SIGPIPEs codesign and makes the *pipeline* status non-zero even
    # though the verification succeeded. The first version of this check
    # reported FAIL while printing "valid on disk" directly underneath.
    VERIFY_OUT="$(codesign --verify --deep --strict --verbose=1 "$APP" 2>&1)"
    if printf '%s\n' "$VERIFY_OUT" | grep -q "valid on disk"; then
        pass "codesign --verify --deep --strict passes"
    else
        fail "codesign --verify --deep --strict does not pass"
        printf '%s\n' "$VERIFY_OUT" | head -5 | sed 's/^/        /'
    fi
fi

# ---------------------------------------------------------------------------
# 5. The guarantees that are per-binary
# ---------------------------------------------------------------------------
# verify-no-demo-data.sh is explicitly per-binary — ship-checklist.md keeps its
# line at [~] for exactly this reason. Running it here means it runs against
# the artifact being shipped rather than against whatever is in DerivedData.
head2 "5. Per-binary guarantees"
if [ -x "$REPO/scripts/verify-no-demo-data.sh" ]; then
    if (cd "$REPO" && ./scripts/verify-no-demo-data.sh >/tmp/nodemo.$$ 2>&1); then
        pass "verify-no-demo-data.sh passes"
    else
        fail "verify-no-demo-data.sh FAILED"
        tail -15 /tmp/nodemo.$$ | sed 's/^/        /'
    fi
    rm -f /tmp/nodemo.$$
else
    fail "scripts/verify-no-demo-data.sh missing or not executable"
fi

# ---------------------------------------------------------------------------
# 6. Notarization credentials
# ---------------------------------------------------------------------------
# Checked last because it is the only one that is purely about your machine.
# A stored keychain profile turns notarytool into one flag; without it the
# submit line needs an app-specific password inline, which then lands in shell
# history.
head2 "6. notarytool credentials"
if xcrun notarytool history --keychain-profile "anchor-notary" >/dev/null 2>&1; then
    pass "keychain profile 'anchor-notary' works"
else
    warn "no working keychain profile named 'anchor-notary'"
    echo "        Create it once, after enrollment, with:"
    echo "          xcrun notarytool store-credentials anchor-notary \\"
    echo "            --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>"
    echo "        The app-specific password comes from appleid.apple.com, not your Apple ID password."
fi

# ---------------------------------------------------------------------------
head2 "Result"
if [ "$FAIL" -eq 0 ]; then
    printf "  \033[32mReady to notarize.\033[0m %s warning(s).\n\n" "$WARN"
    exit 0
else
    printf "  \033[31m%s check(s) would cost you a notarization round trip.\033[0m %s warning(s).\n\n" "$FAIL" "$WARN"
    exit 1
fi
