#!/bin/bash
# Engine-agnostic test runner
# Runs the same assertions against any statusline engine to verify output parity.
# Usage: ./tests/test-engine.sh <engine-command>
# Example:
#   ./tests/test-engine.sh "python3 engines/python/statusline.py"
#   ./tests/test-engine.sh "engines/bash/statusline.sh"

set -euo pipefail

ENGINE="$1"
if [ -z "$ENGINE" ]; then
  echo "Usage: $0 <engine-command>"
  echo "Example: $0 'python3 engines/python/statusline.py'"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

VERBOSE=false
[ "${2:-}" = "-v" ] && VERBOSE=true

# Isolated test cache
TEST_CACHE=$(mktemp -d)
mkdir -p "$TEST_CACHE/claude-code-statusline"
TEST_PROJ="/tmp/statusline-test-project"
trap 'rm -rf "$TEST_CACHE"' EXIT

# Project hash (same logic as statusline.sh / statusline.py)
_SLUG=$(echo "$TEST_PROJ" | sed 's|^/||; s|/|-|g')
if command -v md5 &>/dev/null; then
  _HASH=$(echo "$_SLUG" | md5 -q | cut -c1-8)
else
  _HASH=$(echo "$_SLUG" | md5sum | cut -c1-8)
fi

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

PASS=0 FAIL=0

assert_contains() {
  local label="$1" output="$2" pattern="$3"
  local clean
  clean=$(echo "$output" | strip_ansi)
  if echo "$clean" | grep -qF -- "$pattern"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label"
    echo "    expected to contain: $pattern"
    echo "    got: $clean"
  fi
}

assert_not_contains() {
  local label="$1" output="$2" pattern="$3"
  local clean
  clean=$(echo "$output" | strip_ansi)
  if echo "$clean" | grep -qF -- "$pattern"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label"
    echo "    expected NOT to contain: $pattern"
    echo "    got: $clean"
  else
    PASS=$((PASS + 1))
  fi
}

assert_line_count() {
  local label="$1" output="$2" expected="$3"
  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  if [ "$count" -eq "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label"
    echo "    expected $expected lines, got $count"
  fi
}

render() {
  local fixture="$1"
  XDG_CACHE_HOME="$TEST_CACHE" $ENGINE < "$FIXTURES/$fixture" 2>/dev/null
}

echo "Engine: $ENGINE"
echo ""

# ============================================================
echo "=== Basic rendering ==="
# ============================================================

OUT=$(render basic-session.json)
$VERBOSE && echo "$OUT" && echo ""

assert_line_count "outputs 2 lines" "$OUT" 2
assert_contains "model name" "$OUT" "Opus 4.6"
assert_contains "context bar" "$OUT" "38%"
assert_contains "cost formatted" "$OUT" '$8.4'
assert_contains "duration" "$OUT" "15m"
assert_contains "lines added" "$OUT" "+127"
assert_contains "lines removed" "$OUT" "-34"
assert_contains "tokens in" "$OUT" "288k"
assert_contains "tokens out" "$OUT" "41k"
assert_contains "tok/s present" "$OUT" "tok/s"

# ============================================================
echo "=== Context warnings ==="
# ============================================================

OUT_WARN=$(render high-context.json)
assert_contains "78% shows warning" "$OUT_WARN" "⚠"
assert_contains "78% value" "$OUT_WARN" "78%"

OUT_CRIT=$(render critical-context.json)
assert_contains "92% shows warning" "$OUT_CRIT" "⚠"
assert_contains "92% value" "$OUT_CRIT" "92%"

OUT_OK=$(render basic-session.json)
assert_not_contains "38% no warning" "$OUT_OK" "⚠"

# ============================================================
echo "=== Cost formatting ==="
# ============================================================

OUT_CHEAP=$(render cheap-session.json)
assert_contains "cheap cost cents" "$OUT_CHEAP" '$0.03'

OUT_EXP=$(render expensive-session.json)
assert_contains "expensive cost k suffix" "$OUT_EXP" '$1.8k'

# ============================================================
echo "=== Token formatting ==="
# ============================================================

assert_contains "large tokens no decimal" "$OUT" "288k"
assert_not_contains "large tokens no decimal dot" "$OUT" "287.5k"

OUT_CHEAP_TOK=$(render cheap-session.json)
assert_contains "small tokens raw" "$OUT_CHEAP_TOK" "1.2k"
assert_contains "tiny tokens raw" "$OUT_CHEAP_TOK" "340"

OUT_EXP_TOK=$(render expensive-session.json)
assert_contains "million tokens" "$OUT_EXP_TOK" "1.2M"

# ============================================================
echo "=== Duration formatting ==="
# ============================================================

assert_contains "minutes" "$OUT" "15m"

OUT_LONG=$(render expensive-session.json)
assert_contains "hours+minutes" "$OUT_LONG" "4h0m"

OUT_SHORT=$(render cheap-session.json)
assert_contains "short duration" "$OUT_SHORT" "0m"

# ============================================================
echo "=== Minimal input ==="
# ============================================================

OUT_MIN=$(render minimal.json)
assert_line_count "minimal outputs 2 lines" "$OUT_MIN" 2
assert_contains "minimal model name" "$OUT_MIN" "Sonnet 4.5"
assert_contains "minimal context" "$OUT_MIN" "1%"
assert_not_contains "minimal no warning" "$OUT_MIN" "⚠"

# ============================================================
echo "=== Cumulative stats ==="
# ============================================================

cp "$FIXTURES/cumulative-proj.json" "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
cp "$FIXTURES/cumulative-all.json" "$TEST_CACHE/claude-code-statusline/all.json"

OUT_CUM=$(render basic-session.json)
assert_contains "proj symbol" "$OUT_CUM" "⌂"
assert_contains "all symbol" "$OUT_CUM" "Σ"
assert_contains "proj day cost" "$OUT_CUM" '$374'
assert_contains "proj week cost k" "$OUT_CUM" '$4.0k'
assert_contains "proj month cost k" "$OUT_CUM" '$7.1k'
assert_contains "all day cost" "$OUT_CUM" '$552'
assert_contains "all month cost k" "$OUT_CUM" '$12.0k'
assert_contains "slash separator proj" "$OUT_CUM" '/$4.0k/'
assert_contains "slash separator all" "$OUT_CUM" '/$4.7k/'

# Without caches
rm -f "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
rm -f "$TEST_CACHE/claude-code-statusline/all.json"
OUT_NO_CUM=$(render basic-session.json)
assert_not_contains "no proj without cache" "$OUT_NO_CUM" "⌂"
assert_not_contains "no all without cache" "$OUT_NO_CUM" "Σ"

# Zero-value caches
echo '{"d1":{"cost":0},"d7":{"cost":0},"d30":{"cost":0}}' > "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
echo '{"d1":{"cost":0},"d7":{"cost":0},"d30":{"cost":0}}' > "$TEST_CACHE/claude-code-statusline/all.json"
OUT_ZERO_CUM=$(render basic-session.json)
assert_not_contains "no proj when zero" "$OUT_ZERO_CUM" "⌂"
assert_not_contains "no all when zero" "$OUT_ZERO_CUM" "Σ"
rm -f "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
rm -f "$TEST_CACHE/claude-code-statusline/all.json"

# ============================================================
echo "=== Per-model stats ==="
# ============================================================

FAKE_SID="test-session-abc123"
cp "$FIXTURES/models-cache.json" "$TEST_CACHE/claude-code-statusline/models-${FAKE_SID}.json"

TMPFIX=$(mktemp)
jq --arg tp "/tmp/${FAKE_SID}.jsonl" '. + {transcript_path: $tp}' "$FIXTURES/basic-session.json" > "$TMPFIX"

OUT_MODELS=$(XDG_CACHE_HOME="$TEST_CACHE" $ENGINE < "$TMPFIX" 2>/dev/null)
rm -f "$TMPFIX"

assert_contains "opus token label" "$OUT_MODELS" "O:"
assert_contains "sonnet token label" "$OUT_MODELS" "S:"
assert_contains "haiku token label" "$OUT_MODELS" "H:"
assert_contains "opus in tokens" "$OUT_MODELS" "549k"
assert_contains "opus out tokens" "$OUT_MODELS" "41k"
assert_contains "sonnet in tokens" "$OUT_MODELS" "180k"
assert_contains "sonnet out tokens" "$OUT_MODELS" "25k"
assert_contains "haiku in tokens" "$OUT_MODELS" "45k"
assert_contains "haiku out tokens" "$OUT_MODELS" "15k"

# ============================================================
echo "=== Section toggles ==="
# ============================================================

OUT_L1=$(STATUSLINE_LINE2=false render basic-session.json)
assert_contains "L2 off still has model" "$OUT_L1" "Opus 4.6"
assert_not_contains "L2 off no tok/s" "$OUT_L1" "tok/s"

OUT_NOCOST=$(STATUSLINE_SHOW_COST=false render basic-session.json)
assert_not_contains "no cost" "$OUT_NOCOST" '$8.4'

OUT_NODUR=$(STATUSLINE_SHOW_DURATION=false render basic-session.json)
assert_not_contains "no duration" "$OUT_NODUR" "15m"

OUT_NOCTX=$(STATUSLINE_SHOW_CONTEXT=false render basic-session.json)
assert_not_contains "no context bar" "$OUT_NOCTX" "38%"

OUT_NODIFF=$(STATUSLINE_SHOW_DIFF=false render basic-session.json)
assert_not_contains "no diff added" "$OUT_NODIFF" "+127"

OUT_NOSPD=$(STATUSLINE_SHOW_SPEED=false render basic-session.json)
assert_not_contains "no speed" "$OUT_NOSPD" "tok/s"

# ============================================================
echo "=== CLI arguments ==="
# ============================================================

OUT_ARG=$(XDG_CACHE_HOME="$TEST_CACHE" $ENGINE --no-cost < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "arg --no-cost" "$OUT_ARG" '$8.4'
assert_contains "arg --no-cost still has model" "$OUT_ARG" "Opus 4.6"

OUT_ARG3=$(XDG_CACHE_HOME="$TEST_CACHE" $ENGINE --no-line2 < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "arg --no-line2" "$OUT_ARG3" "tok/s"

OUT_MULTI=$(XDG_CACHE_HOME="$TEST_CACHE" $ENGINE --no-cost --no-diff < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "multi --no-cost" "$OUT_MULTI" '$8.4'
assert_not_contains "multi --no-diff" "$OUT_MULTI" "+127"
assert_contains "multi still has model" "$OUT_MULTI" "Opus 4.6"

# ============================================================
echo "=== NO_COLOR mode ==="
# ============================================================

OUT_NC=$(NO_COLOR=1 render basic-session.json)
if echo "$OUT_NC" | grep -q $'\x1b\['; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: NO_COLOR still contains ANSI codes"
else
  PASS=$((PASS + 1))
fi
assert_contains "NO_COLOR model name" "$OUT_NC" "Opus 4.6"
assert_contains "NO_COLOR context" "$OUT_NC" "38%"
assert_contains "NO_COLOR cost" "$OUT_NC" '$8.4'
assert_line_count "NO_COLOR outputs 2 lines" "$OUT_NC" 2

# ============================================================
# Summary
# ============================================================
echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "ALL $TOTAL TESTS PASSED ($ENGINE)"
else
  echo "$FAIL/$TOTAL TESTS FAILED ($ENGINE)"
  exit 1
fi
