#!/usr/bin/env bash
#
# Deploy the Zoom OAuth bounce page and wire the app up to it.
#
#   ./Web/deploy.sh
#
# Prerequisite, and the one step this script cannot do for you:
#
#   npx vercel login
#
# Logging in is interactive and is your credential, so it stays manual. Once
# you are logged in this script deploys, reads back the production URL, and
# rewrites ZoomOAuthConfig.bounceURL to match, so the two ends cannot drift.

set -euo pipefail

WEB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$WEB_DIR/.." && pwd)"
SWIFT_FILE="$REPO_ROOT/Anchor/Services/OAuth/ZoomOAuthHandler.swift"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# --- 1. Confirm we are logged in ------------------------------------------

if ! npx --yes vercel whoami >/dev/null 2>&1; then
  cat >&2 <<'EOF'

Not logged in to Vercel.

Run this first, then re-run this script:

    npx vercel login

It opens a browser or emails a code. It is interactive by design.
EOF
  exit 1
fi

say "Logged in as: $(npx --yes vercel whoami 2>/dev/null)"

# --- 2. Deploy -------------------------------------------------------------
#
# --prod, not a preview: preview deployments get a fresh URL every time, and
# Zoom matches the registered redirect character for character, so a preview
# URL would break on the next push.

say "Deploying $WEB_DIR to production..."
DEPLOY_LOG="$(mktemp)"
trap 'rm -f "$DEPLOY_LOG"' EXIT

cd "$WEB_DIR"
npx --yes vercel deploy --prod --yes 2>&1 | tee "$DEPLOY_LOG"

DEPLOY_URL="$(grep -oE 'https://[a-zA-Z0-9._-]+\.vercel\.app' "$DEPLOY_LOG" | tail -1)"

if [ -z "$DEPLOY_URL" ]; then
  echo "Could not find a deployment URL in the output above." >&2
  echo "Deploy may have failed; nothing was changed in the app." >&2
  exit 1
fi

REDIRECT_URL="$DEPLOY_URL/oauth/zoom"

# --- 3. Check the page actually serves -------------------------------------

say "Verifying $REDIRECT_URL"
STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
  "$REDIRECT_URL?code=probe&state=probe" || echo 000)"

if [ "$STATUS" != "200" ]; then
  echo "Expected HTTP 200, got $STATUS." >&2
  echo "Leaving ZoomOAuthConfig.bounceURL unchanged so the app keeps its old value." >&2
  exit 1
fi

if ! curl -s --max-time 20 "$REDIRECT_URL?code=probe&state=probe" \
     | grep -q '127\.0\.0\.1:51789'; then
  echo "Page served, but does not reference the loopback listener." >&2
  echo "Check that vercel.json routed /oauth/zoom to the bounce page." >&2
  exit 1
fi

echo "OK: 200, and the page forwards to the loopback listener."

# --- 4. Point the app at it ------------------------------------------------

CURRENT="$(grep -oE 'static let bounceURL = "[^"]*"' "$SWIFT_FILE" | sed 's/.*"\(.*\)"/\1/')"

if [ "$CURRENT" = "$REDIRECT_URL" ]; then
  say "ZoomOAuthConfig.bounceURL already matches. Nothing to change."
else
  python3 - "$SWIFT_FILE" "$REDIRECT_URL" <<'PY'
import re, sys
path, url = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
new, n = re.subn(r'(static let bounceURL = ")[^"]*(")', lambda m: m.group(1) + url + m.group(2), src, count=1)
if n != 1:
    sys.exit("Could not find `static let bounceURL` — update it by hand.")
open(path, "w", encoding="utf-8").write(new)
PY
  say "ZoomOAuthConfig.bounceURL: $CURRENT  ->  $REDIRECT_URL"
fi

# --- 5. The one thing left, which is on Zoom's side ------------------------

cat <<EOF

$(printf '\033[1m')Deployed. One manual step remains.$(printf '\033[0m')

Register this exact string on the Marketplace app, Development tab:

    $REDIRECT_URL

It goes in BOTH fields, and Zoom matches character for character:

  1. Basic Information -> OAuth Redirect URL
  2. Basic Information -> OAuth Allow Lists   (a separate field below it)

https://marketplace.zoom.us/develop/applications/UcNDw-l5QkWaeKEOvXfXhA/information?mode=dev

Then rebuild Anchor so it picks up the new bounceURL, and use
Settings -> Zoom -> Connect Zoom. A stale build keeps the old value in memory.

EOF
