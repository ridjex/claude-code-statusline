#!/bin/bash
# Status Line Test Suite
# Usage: ./tests/run-tests.sh
#   -v  verbose (show rendered output)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SL="$ROOT_DIR/src/statusline.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

VERBOSE=false
[ "${1:-}" = "-v" ] && VERBOSE=true

# Isolated test cache
TEST_CACHE=$(mktemp -d)
mkdir -p "$TEST_CACHE/claude-code-statusline"
TEST_PROJ="/tmp/statusline-test-project"
trap 'rm -rf "$TEST_CACHE"' EXIT

# Project hash (same logic as statusline.sh)
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

assert_no_double_space() {
  local label="$1" output="$2"
  local clean
  clean=$(echo "$output" | strip_ansi)
  if echo "$clean" | grep -q -- '  '; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label"
    echo "    found double space in: $(echo "$clean" | grep -- '  ' | head -1 | sed 's/  />>  <</g')"
  else
    PASS=$((PASS + 1))
  fi
}

render() {
  local fixture="$1"
  XDG_CACHE_HOME="$TEST_CACHE" "$SL" < "$FIXTURES/$fixture" 2>/dev/null
}

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
assert_no_double_space "no double spaces L1" "$(echo "$OUT" | head -1)"

# ============================================================
echo "=== Context warnings ==="
# ============================================================

OUT_WARN=$(render high-context.json)
$VERBOSE && echo "$OUT_WARN" && echo ""

assert_contains "78% shows warning" "$OUT_WARN" "⚠"
assert_contains "78% value" "$OUT_WARN" "78%"

OUT_CRIT=$(render critical-context.json)
$VERBOSE && echo "$OUT_CRIT" && echo ""

assert_contains "92% shows warning" "$OUT_CRIT" "⚠"
assert_contains "92% value" "$OUT_CRIT" "92%"

OUT_OK=$(render basic-session.json)
assert_not_contains "38% no warning" "$OUT_OK" "⚠"

# ============================================================
echo "=== Cost formatting ==="
# ============================================================

OUT_CHEAP=$(render cheap-session.json)
$VERBOSE && echo "$OUT_CHEAP" && echo ""

assert_contains "cheap cost cents" "$OUT_CHEAP" '$0.03'

OUT_EXP=$(render expensive-session.json)
$VERBOSE && echo "$OUT_EXP" && echo ""

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
$VERBOSE && echo "$OUT_MIN" && echo ""

assert_line_count "minimal outputs 2 lines" "$OUT_MIN" 2
assert_contains "minimal model name" "$OUT_MIN" "Sonnet 4.5"
assert_contains "minimal context" "$OUT_MIN" "1%"
assert_not_contains "minimal no warning" "$OUT_MIN" "⚠"

# ============================================================
echo "=== Cumulative stats ==="
# ============================================================

# Install mock caches
cp "$FIXTURES/cumulative-proj.json" "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
cp "$FIXTURES/cumulative-all.json" "$TEST_CACHE/claude-code-statusline/all.json"

OUT_CUM=$(render basic-session.json)
$VERBOSE && echo "$OUT_CUM" && echo ""

assert_contains "proj symbol" "$OUT_CUM" "⌂"
assert_contains "all symbol" "$OUT_CUM" "Σ"
assert_contains "proj day cost" "$OUT_CUM" '$374'
assert_contains "proj week cost k" "$OUT_CUM" '$4.0k'
assert_contains "proj month cost k" "$OUT_CUM" '$7.1k'
assert_contains "all day cost" "$OUT_CUM" '$552'
assert_contains "all month cost k" "$OUT_CUM" '$12.0k'
assert_contains "slash separator proj" "$OUT_CUM" '/$4.0k/'
assert_contains "slash separator all" "$OUT_CUM" '/$4.7k/'
assert_no_double_space "no double spaces L2 cumulative" "$(echo "$OUT_CUM" | tail -1)"

# Without caches — cumulative sections omitted
rm -f "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
rm -f "$TEST_CACHE/claude-code-statusline/all.json"
OUT_NO_CUM=$(render basic-session.json)
assert_not_contains "no proj without cache" "$OUT_NO_CUM" "⌂"
assert_not_contains "no all without cache" "$OUT_NO_CUM" "Σ"

# Zero-value caches — cumulative sections hidden
echo '{"d1":{"cost":0},"d7":{"cost":0},"d30":{"cost":0}}' > "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
echo '{"d1":{"cost":0},"d7":{"cost":0},"d30":{"cost":0}}' > "$TEST_CACHE/claude-code-statusline/all.json"
OUT_ZERO_CUM=$(render basic-session.json)
$VERBOSE && echo "$OUT_ZERO_CUM" && echo ""
assert_not_contains "no proj when zero" "$OUT_ZERO_CUM" "⌂"
assert_not_contains "no all when zero" "$OUT_ZERO_CUM" "Σ"
rm -f "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
rm -f "$TEST_CACHE/claude-code-statusline/all.json"

# ============================================================
echo "=== Per-model stats ==="
# ============================================================

# Install mock model cache with a fake session ID
mkdir -p "$TEST_CACHE/claude-code-statusline"
FAKE_SID="test-session-abc123"
cp "$FIXTURES/models-cache.json" "$TEST_CACHE/claude-code-statusline/models-${FAKE_SID}.json"

# Create fixture with transcript_path pointing to fake session
TMPFIX=$(mktemp)
jq --arg tp "/tmp/${FAKE_SID}.jsonl" '. + {transcript_path: $tp}' "$FIXTURES/basic-session.json" > "$TMPFIX"

OUT_MODELS=$(XDG_CACHE_HOME="$TEST_CACHE" "$SL" < "$TMPFIX" 2>/dev/null)
rm -f "$TMPFIX"
$VERBOSE && echo "$OUT_MODELS" && echo ""

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
echo "=== Spacing consistency ==="
# ============================================================

# Re-render with full data
cp "$FIXTURES/cumulative-proj.json" "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
cp "$FIXTURES/cumulative-all.json" "$TEST_CACHE/claude-code-statusline/all.json"
OUT_FULL=$(render basic-session.json)

# Check all separator spacing is " │ " (space-pipe-space)
L1_CLEAN=$(echo "$OUT_FULL" | head -1 | strip_ansi)
L2_CLEAN=$(echo "$OUT_FULL" | tail -1 | strip_ansi)

# Separators should have exactly 1 space on each side
BAD_SEP=$(echo "$L1_CLEAN$L2_CLEAN" | grep -oE '.│.' | grep -v ' │ ' || true)
if [ -z "$BAD_SEP" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: separator spacing"
  echo "    bad separators: $BAD_SEP"
fi

# ============================================================
echo "=== Section toggles ==="
# ============================================================

# LINE2=false → only 1 line output
OUT_L1=$(STATUSLINE_LINE2=false render basic-session.json)
$VERBOSE && echo "$OUT_L1" && echo ""
assert_contains "L2 off still has model" "$OUT_L1" "Opus 4.6"
assert_not_contains "L2 off no tok/s" "$OUT_L1" "tok/s"

# Hide git
OUT_NOGIT=$(STATUSLINE_SHOW_GIT=false render basic-session.json)
assert_not_contains "no git branch" "$OUT_NOGIT" "main"

# Hide cost
OUT_NOCOST=$(STATUSLINE_SHOW_COST=false render basic-session.json)
assert_not_contains "no cost" "$OUT_NOCOST" '$8.4'

# Hide duration
OUT_NODUR=$(STATUSLINE_SHOW_DURATION=false render basic-session.json)
assert_not_contains "no duration" "$OUT_NODUR" "15m"

# Hide context
OUT_NOCTX=$(STATUSLINE_SHOW_CONTEXT=false render basic-session.json)
assert_not_contains "no context bar" "$OUT_NOCTX" "38%"

# Hide diff
OUT_NODIFF=$(STATUSLINE_SHOW_DIFF=false render basic-session.json)
assert_not_contains "no diff added" "$OUT_NODIFF" "+127"

# Hide speed
OUT_NOSPD=$(STATUSLINE_SHOW_SPEED=false render basic-session.json)
assert_not_contains "no speed" "$OUT_NOSPD" "tok/s"

# Hide cumulative
cp "$FIXTURES/cumulative-proj.json" "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
cp "$FIXTURES/cumulative-all.json" "$TEST_CACHE/claude-code-statusline/all.json"
OUT_NOCUM=$(STATUSLINE_SHOW_CUMULATIVE=false render basic-session.json)
assert_not_contains "no cumulative proj" "$OUT_NOCUM" "⌂"
assert_not_contains "no cumulative all" "$OUT_NOCUM" "Σ"
rm -f "$TEST_CACHE/claude-code-statusline/proj-${_HASH}.json"
rm -f "$TEST_CACHE/claude-code-statusline/all.json"

# ============================================================
echo "=== CLI arguments ==="
# ============================================================

# Test --no-cost
OUT_ARG=$(XDG_CACHE_HOME="$TEST_CACHE" "$SL" --no-cost < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "arg --no-cost" "$OUT_ARG" '$8.4'
assert_contains "arg --no-cost still has model" "$OUT_ARG" "Opus 4.6"

# Test --no-git
OUT_ARG2=$(XDG_CACHE_HOME="$TEST_CACHE" "$SL" --no-git < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "arg --no-git" "$OUT_ARG2" "main"

# Test --no-line2
OUT_ARG3=$(XDG_CACHE_HOME="$TEST_CACHE" "$SL" --no-line2 < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "arg --no-line2" "$OUT_ARG3" "tok/s"

# Test multiple args
OUT_MULTI=$(XDG_CACHE_HOME="$TEST_CACHE" "$SL" --no-cost --no-git --no-diff < "$FIXTURES/basic-session.json" 2>/dev/null)
assert_not_contains "multi --no-cost" "$OUT_MULTI" '$8.4'
assert_not_contains "multi --no-git" "$OUT_MULTI" "main"
assert_not_contains "multi --no-diff" "$OUT_MULTI" "+127"
assert_contains "multi still has model" "$OUT_MULTI" "Opus 4.6"

# Test --no-color
OUT_ARGNC=$(XDG_CACHE_HOME="$TEST_CACHE" "$SL" --no-color < "$FIXTURES/basic-session.json" 2>/dev/null)
if echo "$OUT_ARGNC" | grep -q $'\x1b\['; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: --no-color still has ANSI"
else
  PASS=$((PASS + 1))
fi

# Test --help (should print to stderr and exit 0)
HELP_OUT=$("$SL" --help 2>&1 >/dev/null </dev/null)
HELP_RC=$?
if [ "$HELP_RC" -eq 0 ] && echo "$HELP_OUT" | grep -q "Usage:"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: --help did not print usage to stderr or exited non-zero"
fi

# ============================================================
echo "=== NO_COLOR mode ==="
# ============================================================

OUT_NC=$(NO_COLOR=1 render basic-session.json)
$VERBOSE && echo "$OUT_NC" && echo ""

# Should contain no ANSI escape codes
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

# STATUSLINE_NO_COLOR should also work
OUT_SNC=$(STATUSLINE_NO_COLOR=1 render basic-session.json)
if echo "$OUT_SNC" | grep -q $'\x1b\['; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: STATUSLINE_NO_COLOR still contains ANSI codes"
else
  PASS=$((PASS + 1))
fi

# ============================================================
# Summary
# ============================================================
echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "ALL $TOTAL TESTS PASSED"
else
  echo "$FAIL/$TOTAL TESTS FAILED"
  exit 1
fi
