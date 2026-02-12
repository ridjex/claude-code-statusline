#!/bin/bash
# Generate demo SVG from actual statusline.sh output
# Runs statusline.sh with mock fixtures, captures ANSI, converts to SVG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SL="$ROOT/src/statusline.sh"
FIXTURES="$ROOT/tests/fixtures"
OUT_DARK="$ROOT/assets/demo-dark.svg"
OUT_LIGHT="$ROOT/assets/demo-light.svg"

# Isolated cache + scene output dir
TMPDIR_ALL=$(mktemp -d)
CACHE="$TMPDIR_ALL/cache"
SCENES="$TMPDIR_ALL/scenes"
mkdir -p "$CACHE/claude-code-statusline" "$SCENES"
trap 'rm -rf "$TMPDIR_ALL"' EXIT

# Project hash for /tmp/statusline-test-project
# NOTE: must use `echo` (not printf) to match statusline.sh hash calculation
_SLUG=$(echo "/tmp/statusline-test-project" | sed 's|^/||; s|/|-|g')
if command -v md5 &>/dev/null; then
  _HASH=$(echo "$_SLUG" | md5 -q | cut -c1-8)
else
  _HASH=$(echo "$_SLUG" | md5sum | cut -c1-8)
fi

# Deterministic git context: temp repo with a fixed branch name
MOCK_REPO="$TMPDIR_ALL/repo"
git init -q "$MOCK_REPO"
git -C "$MOCK_REPO" checkout -q -b fix/auth-session
# Stage a file so "dirty" indicator shows
printf 'x' > "$MOCK_REPO/wip.txt"

# Shared cache: cumulative costs available for all scenes
cp "$FIXTURES/cumulative-proj.json" "$CACHE/claude-code-statusline/proj-${_HASH}.json"
cp "$FIXTURES/cumulative-all.json" "$CACHE/claude-code-statusline/all.json"

# --- Scene 1: Full session (Opus-primary, 38%) ---
FAKE_SID1="demo-session-001"
cp "$FIXTURES/models-cache.json" "$CACHE/claude-code-statusline/models-${FAKE_SID1}.json"

jq --arg tp "/tmp/${FAKE_SID1}.jsonl" '. + {transcript_path: $tp}' \
  "$FIXTURES/basic-session.json" | (cd "$MOCK_REPO" && XDG_CACHE_HOME="$CACHE" "$SL") > "$SCENES/1.txt" 2>/dev/null

# --- Scene 2: High context warning (78%) ---
FAKE_SID2="demo-session-002"
cp "$FIXTURES/models-cache.json" "$CACHE/claude-code-statusline/models-${FAKE_SID2}.json"

jq --arg tp "/tmp/${FAKE_SID2}.jsonl" '. + {transcript_path: $tp}' \
  "$FIXTURES/high-context.json" | (cd "$MOCK_REPO" && XDG_CACHE_HOME="$CACHE" "$SL") > "$SCENES/2.txt" 2>/dev/null

# --- Scene 3: Critical context (92%) ---
FAKE_SID3="demo-session-003"
cp "$FIXTURES/models-cache.json" "$CACHE/claude-code-statusline/models-${FAKE_SID3}.json"

jq --arg tp "/tmp/${FAKE_SID3}.jsonl" '. + {transcript_path: $tp}' \
  "$FIXTURES/critical-context.json" | (cd "$MOCK_REPO" && XDG_CACHE_HOME="$CACHE" "$SL") > "$SCENES/3.txt" 2>/dev/null

# --- Generate SVGs ---
python3 "$SCRIPT_DIR/ansi2svg.py" \
  --scene "Full session" "$SCENES/1.txt" \
  --scene "Context warning (78%)" "$SCENES/2.txt" \
  --scene "Critical context (92%)" "$SCENES/3.txt" \
  --dark "$OUT_DARK" \
  --light "$OUT_LIGHT"

echo "Generated:"
echo "  $OUT_DARK"
echo "  $OUT_LIGHT"
