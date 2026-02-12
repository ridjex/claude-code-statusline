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

# Isolated cache
CACHE=$(mktemp -d)
mkdir -p "$CACHE/claude-code-statusline"
trap 'rm -rf "$CACHE"' EXIT

# Project hash for /tmp/statusline-test-project
_SLUG=$(echo "/tmp/statusline-test-project" | sed 's|^/||; s|/|-|g')
if command -v md5 &>/dev/null; then
  _HASH=$(echo "$_SLUG" | md5 -q | cut -c1-8)
else
  _HASH=$(echo "$_SLUG" | md5sum | cut -c1-8)
fi

render() {
  local fixture="$1" extra_setup="${2:-}"
  [ -n "$extra_setup" ] && eval "$extra_setup"
  XDG_CACHE_HOME="$CACHE" "$SL" < "$FIXTURES/$fixture" 2>/dev/null
}

# --- Render scenarios ---

# 1. Full session with model cache + cumulative
FAKE_SID="demo-session-001"
cp "$FIXTURES/models-cache.json" "$CACHE/claude-code-statusline/models-${FAKE_SID}.json"
cp "$FIXTURES/cumulative-proj.json" "$CACHE/claude-code-statusline/proj-${_HASH}.json"
cp "$FIXTURES/cumulative-all.json" "$CACHE/claude-code-statusline/all.json"

TMPFIX=$(mktemp)
jq --arg tp "/tmp/${FAKE_SID}.jsonl" '. + {transcript_path: $tp}' "$FIXTURES/basic-session.json" > "$TMPFIX"
SCENE1=$(XDG_CACHE_HOME="$CACHE" "$SL" < "$TMPFIX" 2>/dev/null)
rm -f "$TMPFIX"

# 2. High context warning (78%) — single model
rm -f "$CACHE/claude-code-statusline/models-"*.json
SCENE2=$(render high-context.json)

# 3. Critical context (92%) — different model
SCENE3=$(render critical-context.json)

# Clean up cumulative zero-value caches that background jobs may have created
rm -f "$CACHE/claude-code-statusline/proj-"*.json "$CACHE/claude-code-statusline/all.json"

# --- Write scenes to temp files (avoids shell→Python unicode issues) ---
SCENES_DIR=$(mktemp -d)
echo "$SCENE1" > "$SCENES_DIR/1.txt"
echo "$SCENE2" > "$SCENES_DIR/2.txt"
echo "$SCENE3" > "$SCENES_DIR/3.txt"

python3 "$SCRIPT_DIR/ansi2svg.py" \
  --scene "Full session" "$SCENES_DIR/1.txt" \
  --scene "Context warning (78%)" "$SCENES_DIR/2.txt" \
  --scene "Critical context (92%)" "$SCENES_DIR/3.txt" \
  --dark "$OUT_DARK" \
  --light "$OUT_LIGHT"

rm -rf "$SCENES_DIR"

echo "Generated:"
echo "  $OUT_DARK"
echo "  $OUT_LIGHT"
