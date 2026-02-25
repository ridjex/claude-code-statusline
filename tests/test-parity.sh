#!/usr/bin/env bash
# Output parity test — verifies all engines produce identical output.
# Compares ANSI output byte-for-byte across all available engines.
# Git and cumulative sections are disabled (environment-dependent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

# Isolated cache (no cumulative data)
TEST_CACHE=$(mktemp -d)
mkdir -p "$TEST_CACHE/claude-code-statusline"
trap 'rm -rf "$TEST_CACHE"' EXIT

# Detect available engines
ENGINE_NAMES=()
ENGINE_CMDS=()

if [ -f "$ROOT_DIR/engines/bash/statusline.sh" ]; then
  ENGINE_NAMES+=(bash)
  ENGINE_CMDS+=("$ROOT_DIR/engines/bash/statusline.sh")
fi
if [ -f "$ROOT_DIR/engines/python/statusline.py" ] && command -v python3 &>/dev/null; then
  ENGINE_NAMES+=(python)
  ENGINE_CMDS+=("python3 $ROOT_DIR/engines/python/statusline.py")
fi
if [ -f "$ROOT_DIR/engines/go/statusline" ]; then
  ENGINE_NAMES+=(go)
  ENGINE_CMDS+=("$ROOT_DIR/engines/go/statusline")
fi
if [ -f "$ROOT_DIR/engines/rust/target/release/statusline" ]; then
  ENGINE_NAMES+=(rust)
  ENGINE_CMDS+=("$ROOT_DIR/engines/rust/target/release/statusline")
fi

if [ ${#ENGINE_NAMES[@]} -lt 2 ]; then
  echo "Need at least 2 engines to compare parity. Found: ${ENGINE_NAMES[*]}"
  exit 1
fi

echo "Testing output parity across: ${ENGINE_NAMES[*]}"
echo ""

PASS=0 FAIL=0

FIXTURES_LIST=(
  basic-session.json
  cheap-session.json
  critical-context.json
  expensive-session.json
  high-context.json
  minimal.json
)

for fixture in "${FIXTURES_LIST[@]}"; do
  # Generate reference output from first engine
  REF_OUT=$(STATUSLINE_SHOW_GIT=false STATUSLINE_SHOW_CUMULATIVE=false \
    XDG_CACHE_HOME="$TEST_CACHE" \
    ${ENGINE_CMDS[0]} --no-git --no-cumulative < "$FIXTURES/$fixture" 2>/dev/null || true)

  for i in $(seq 1 $((${#ENGINE_NAMES[@]} - 1))); do
    ENG_OUT=$(STATUSLINE_SHOW_GIT=false STATUSLINE_SHOW_CUMULATIVE=false \
      XDG_CACHE_HOME="$TEST_CACHE" \
      ${ENGINE_CMDS[$i]} --no-git --no-cumulative < "$FIXTURES/$fixture" 2>/dev/null || true)

    if [ "$REF_OUT" = "$ENG_OUT" ]; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "FAIL: $fixture — ${ENGINE_NAMES[0]} vs ${ENGINE_NAMES[$i]}"
      diff <(echo "$REF_OUT") <(echo "$ENG_OUT") || true
      echo ""
    fi
  done
done

echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "ALL $TOTAL PARITY CHECKS PASSED (${ENGINE_NAMES[*]})"
else
  echo "$FAIL/$TOTAL PARITY CHECKS FAILED"
  exit 1
fi
