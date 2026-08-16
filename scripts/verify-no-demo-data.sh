#!/bin/bash
#
# verify-no-demo-data.sh — ship gate for the fabricated classroom.
#
# DemoData.swift manufactures students, grades and struggle scores out of
# nothing. That is exactly the shape of data Anchor exists to report truthfully,
# so no build a teacher runs may be able to produce it.
#
# The guarantee comes from `#if DEBUG`: DemoData.swift is wholly inside one, so
# the type does not exist in a Release compile and any reference from
# non-DEBUG code fails the Release build outright. This script checks that the
# guarantee still holds, in the two places it can actually be broken:
#
#   SOURCE  a reference to the demo classroom that is not inside `#if DEBUG`.
#           This is the regression that matters — it is what would un-gate the
#           fabricated data — and it is checked by preprocessing every Swift
#           file the way a Release compile sees it.
#
#   BINARY  demo symbols surviving in a built artifact, plus the bundle being a
#           Release build at all (a Debug build compiles the demo classroom in
#           and must never reach a teacher).
#
# A note on why there is no exhaustive string scan of the binary. An earlier
# version of this script searched the Release binary for the invented names.
# That check cannot be trusted: Swift stores string literals of 15 UTF-8 bytes
# or fewer inline in the String struct rather than as data in the binary, so
# "Maya Whitfield" (14 bytes) and "Jordan Alvarez" (14) are invisible to
# `strings` in an optimised build. A scan like that reports clean whether or not
# the data is there, which is worse than no check at all. The long literals are
# still scanned below as a supplementary signal, clearly labelled as partial —
# the source and symbol checks are the ones that carry the guarantee.
#
# Usage:
#   scripts/verify-no-demo-data.sh [path/to/Anchor.app]
#
# Exits non-zero on any finding. Safe to wire into a release script or CI.
#

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="$REPO/Anchor"
DEMO_SOURCE="$SOURCE_ROOT/Data/DemoData.swift"

fail=0

# ---------------------------------------------------------------------------
# 1. SOURCE — no demo reference escapes `#if DEBUG`
# ---------------------------------------------------------------------------

echo "SOURCE  $SOURCE_ROOT"

if [ ! -f "$DEMO_SOURCE" ]; then
    echo "  FAIL  DemoData.swift not found at $DEMO_SOURCE"
    exit 1
fi

python3 - "$SOURCE_ROOT" <<'PY'
import os, re, sys

root = sys.argv[1]

# Identifiers that only ever exist to serve the fabricated classroom.
PATTERN = re.compile(r'\b(DemoData|loadDemoData|loadDemo|applyDemoClassroom'
                     r'|applyDemoName|applyDemoConnection|applyDemoTopic'
                     r'|isDemoArchive|isDemoClassroom|isDemoName|ANCHOR_DEMO\w*)\b')

def release_visible_lines(text):
    """Lines a Release compile would see: everything outside `#if DEBUG`
    bodies, including their `#else` branches. Other `#if` conditions are
    treated as compiled-in, which is the conservative choice for a gate."""
    out, stack = [], []          # stack entries: True while emitting
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if s.startswith('#if'):
            stack.append(not re.match(r'#if\s+DEBUG\b', s))
            continue
        if s.startswith('#elseif') or s.startswith('#elif'):
            continue
        if s.startswith('#else'):
            if stack:
                stack[-1] = not stack[-1]
            continue
        if s.startswith('#endif'):
            if stack:
                stack.pop()
            continue
        if all(stack):
            out.append((n, line))
    return out

findings = []
for dirpath, _, files in os.walk(root):
    for name in files:
        if not name.endswith('.swift'):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding='utf-8', errors='replace') as fh:
            text = fh.read()
        for n, line in release_visible_lines(text):
            code = line.split('//', 1)[0]        # ignore commentary
            m = PATTERN.search(code)
            if m:
                rel = os.path.relpath(path, root)
                findings.append(f"  FAIL  {rel}:{n} references {m.group(1)} outside #if DEBUG")

if findings:
    print("\n".join(findings))
    sys.exit(1)

print("  ok    No demo reference is reachable from a Release compile")
PY
[ $? -ne 0 ] && fail=1

# ---------------------------------------------------------------------------
# 2. BINARY — Release bundle, and no demo symbols
# ---------------------------------------------------------------------------

APP="${1:-}"
if [ -z "$APP" ]; then
    APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 \
        -path "*Anchor-*/Build/Products/Release/Anchor.app" -print -quit 2>/dev/null)
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo
    echo "BINARY  skipped — no Release Anchor.app found."
    echo "        Build one, then re-run to check the artifact you will ship:"
    echo "        xcodebuild -project Anchor.xcodeproj -scheme Anchor -configuration Release build"
    echo
    [ "$fail" -eq 0 ] && echo "INCOMPLETE — source is clean, but no build was checked." \
                      || echo "FAILED — do not ship."
    exit $([ "$fail" -eq 0 ] && echo 2 || echo 1)
fi

echo
echo "BINARY  $APP"

BIN="$APP/Contents/MacOS/Anchor"
if [ ! -f "$BIN" ]; then
    echo "  FAIL  no executable at $BIN"
    exit 1
fi

# A Debug bundle keeps the real code — and the demo classroom — in
# Anchor.debug.dylib, leaving a ~60 KB stub as the main executable. Scanning the
# stub reports clean no matter what, so refuse the bundle outright.
if ls "$APP/Contents/MacOS/"*.debug.dylib >/dev/null 2>&1; then
    echo "  FAIL  This is a Debug build (Anchor.debug.dylib present)."
    echo "        Debug builds compile the fabricated classroom in and must not ship."
    exit 1
fi
echo "  ok    Release build (no debug dylib)"

# Type metadata and symbol names are not subject to the small-string
# optimisation, so unlike a literal scan this is dependable.
sym=$(nm -a "$BIN" 2>/dev/null | grep -ci 'demodata\|loadDemo\|applyDemo' || true)
if [ "${sym:-0}" -ne 0 ]; then
    echo "  FAIL  $sym demo symbol(s) in the symbol table"
    nm -a "$BIN" 2>/dev/null | grep -i 'demodata\|loadDemo\|applyDemo' | head -5
    fail=1
else
    echo "  ok    No demo symbols in the symbol table"
fi

# Supplementary only — see the note at the top about short literals.
STRINGS_DUMP=$(mktemp -t anchor-strings)
trap 'rm -f "$STRINGS_DUMP"' EXIT
strings -a "$BIN" > "$STRINGS_DUMP"

if ! grep -qF "Engagement timeline" "$STRINGS_DUMP"; then
    echo "  FAIL  Anchor's own strings are absent — scanning the wrong file."
    exit 1
fi

terms=$(grep -o '"[^"]\{16,\}"' "$DEMO_SOURCE" | tr -d '"' | sort -u)
term_count=$(printf '%s\n' "$terms" | grep -c . || true)
hits=0
while IFS= read -r term; do
    [ -z "$term" ] && continue
    if [ "$(grep -cF -- "$term" "$STRINGS_DUMP" 2>/dev/null || true)" -gt 0 ]; then
        echo "  FAIL  fabricated content in binary: \"$term\""
        fail=1
        hits=$((hits + 1))
    fi
done <<< "$terms"
[ "$hits" -eq 0 ] && echo "  ok    None of the $term_count long fabricated literals present (partial check)"

echo
if [ "$fail" -eq 0 ]; then
    echo "PASS  The fabricated classroom cannot appear in this build."
else
    echo "FAILED — do not ship this build."
fi
exit $fail
