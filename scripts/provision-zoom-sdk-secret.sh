#!/usr/bin/env bash
#
# Provision the Meeting SDK Secret into the Keychain, from the clipboard.
#
#   1. marketplace.zoom.us -> Develop -> "Anchor Meeting SDK"
#      -> Basic Information -> Client Secret -> Copy
#   2. ./scripts/provision-zoom-sdk-secret.sh
#
# The secret is read from the clipboard and handed straight to the app, which
# writes it to the Keychain. It is never echoed, never written to a file, and
# never enters shell history — which is the whole reason this is a script and
# not a command you paste with the value inline.
#
# This is the *Meeting SDK* Client Secret, from the app with Embed -> Meeting
# SDK switched on. It is NOT the Server-to-Server secret and NOT the browser
# sign-in secret. All three are "a client secret"; using the wrong one makes
# sdkAuth fail locally, before any network request, which looks exactly like a
# malformed token. See ZOOM_INTEGRATION.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/Anchor-"*/Build/Products/Debug/Anchor.app 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
  echo "No built Anchor.app found. Build it in Xcode first." >&2
  exit 1
fi
BIN="$APP/Contents/MacOS/Anchor"

# --- Validate the clipboard before launching anything ----------------------

SECRET="$(pbpaste)"
LEN=${#SECRET}

if [ "$LEN" -lt 20 ] || [ "$LEN" -gt 80 ] || ! [[ "$SECRET" =~ ^[A-Za-z0-9_-]+$ ]]; then
  cat >&2 <<EOF
The clipboard does not look like a Zoom client secret (length $LEN).

Copy it first: marketplace.zoom.us -> Develop -> "Anchor Meeting SDK"
-> Basic Information -> Client Secret -> Copy
EOF
  exit 1
fi

echo "Clipboard holds a $LEN-character secret. Provisioning..."

# --- Seed it -------------------------------------------------------------
#
# A second, inert instance does the write. ANCHOR_NO_AUTOCONNECT keeps it from
# connecting or touching the menu bar; seeding runs before that guard. This
# avoids having to quit an Anchor that Xcode is currently debugging.

ANCHOR_NO_AUTOCONNECT=1 \
ANCHOR_ZOOM_SDK_SECRET="$SECRET" \
  "$BIN" >/dev/null 2>&1 &
SEED_PID=$!

sleep 6
kill "$SEED_PID" 2>/dev/null || true
unset SECRET

# --- Confirm it landed -----------------------------------------------------

if security find-generic-password -s com.anchor.zoom.meetingsdk -a sdk-secret >/dev/null 2>&1; then
  MDAT="$(security find-generic-password -s com.anchor.zoom.meetingsdk -a sdk-secret 2>&1 \
          | sed -n 's/.*"mdat".*"\(.*\)\\000".*/\1/p')"
  echo "Stored in the Keychain (com.anchor.zoom.meetingsdk / sdk-secret, updated $MDAT)."
  echo
  echo "Now restart Anchor from Xcode so it re-reads the Keychain, then start a"
  echo "Zoom meeting and click Yes on the monitoring prompt."
else
  echo "The Keychain entry was not created. Check Console.app for Anchor's launch log." >&2
  exit 1
fi
