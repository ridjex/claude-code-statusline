#!/bin/bash
# Git integration test — verifies engines read real git state correctly.
# Creates a temp repo with branches, commits, stashes, and dirty files,
# then runs the engine FROM INSIDE the repo and checks output.
#
# Engines use os.Getwd() / std::env::current_dir() for git discovery,
# so we must cd into the repo before running the engine.
#
# Usage: ./tests/test-git-integration.sh <engine-command>
# Example: ./tests/test-git-integration.sh "engines/go/statusline"

set -euo pipefail

ENGINE="$1"
if [ -z "$ENGINE" ]; then
  echo "Usage: $0 <engine-command>"
  exit 1
fi

# Resolve engine path(s) to absolute — handles "python3 engines/python/statusline.py"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ABS=""
for word in $ENGINE; do
  if [ -z "$ENGINE_ABS" ]; then
    # First word: resolve if relative path to a file, else keep as-is (e.g. python3)
    case "$word" in
      /*) ENGINE_ABS="$word" ;;
      *)
        if [ -f "$ROOT_DIR/$word" ]; then
          ENGINE_ABS="$ROOT_DIR/$word"
        else
          ENGINE_ABS="$word"
        fi
        ;;
    esac
  else
    # Subsequent words: resolve relative paths
    case "$word" in
      /*) ENGINE_ABS="$ENGINE_ABS $word" ;;
      *)
        if [ -f "$ROOT_DIR/$word" ]; then
          ENGINE_ABS="$ENGINE_ABS $ROOT_DIR/$word"
        else
          ENGINE_ABS="$ENGINE_ABS $word"
        fi
        ;;
    esac
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0 FAIL=0

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

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

# Create a temp git repo
REPO=$(mktemp -d)
TEST_CACHE=$(mktemp -d)
mkdir -p "$TEST_CACHE/claude-code-statusline"
trap 'rm -rf "$REPO" "$TEST_CACHE"' EXIT

echo "Engine: $ENGINE"
echo "Temp repo: $REPO"
echo ""

# Initialize repo with a commit
git -C "$REPO" init -b main >/dev/null 2>&1
git -C "$REPO" config user.email "test@test.com"
git -C "$REPO" config user.name "Test"
echo "initial" > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -m "initial" >/dev/null 2>&1

# Render runs the engine from inside the repo
render() {
  (cd "$REPO" && XDG_CACHE_HOME="$TEST_CACHE" $ENGINE_ABS < "$FIXTURES/basic-session.json" 2>/dev/null)
}

# ============================================================
echo "=== Branch detection ==="
# ============================================================

OUT=$(render)
assert_contains "detects main branch" "$OUT" "main"

# Create and switch to feature branch
git -C "$REPO" checkout -b feature/login >/dev/null 2>&1
OUT=$(render)
assert_contains "detects feature branch" "$OUT" "login"

# ============================================================
echo "=== Dirty state ==="
# ============================================================

# Add uncommitted changes
echo "modified" >> "$REPO/file.txt"
OUT=$(render)
assert_contains "shows dirty indicator" "$OUT" "●"

# Stage and commit to clean
git -C "$REPO" add file.txt
git -C "$REPO" commit -m "modify" >/dev/null 2>&1

# ============================================================
echo "=== Diff stats ==="
# ============================================================

# Create tracked changes (staged + unstaged)
echo "line1" >> "$REPO/file.txt"
echo "line2" >> "$REPO/file.txt"
echo "new content" > "$REPO/new-file.txt"
git -C "$REPO" add new-file.txt

OUT=$(render)
# Should show diff stats (added lines)
assert_contains "shows additions" "$OUT" "+"

# Clean up
git -C "$REPO" checkout -- file.txt
git -C "$REPO" reset HEAD new-file.txt >/dev/null 2>&1
rm -f "$REPO/new-file.txt"

# ============================================================
echo "=== Stash detection ==="
# ============================================================

# Create a stash
echo "stash me" >> "$REPO/file.txt"
git -C "$REPO" stash >/dev/null 2>&1

OUT=$(render)
# Stash indicator should be visible (engines show stash count)
assert_contains "shows stash indicator" "$OUT" "stash:1"

# Pop stash to clean up
git -C "$REPO" stash pop >/dev/null 2>&1

# ============================================================
echo "=== No git ==="
# ============================================================

# Test with a non-git directory
NOGIT=$(mktemp -d)
OUT=$(cd "$NOGIT" && XDG_CACHE_HOME="$TEST_CACHE" $ENGINE_ABS < "$FIXTURES/basic-session.json" 2>/dev/null)
# Should not crash, just no git info
assert_not_contains "no git: no branch" "$OUT" "main"
assert_not_contains "no git: no feature" "$OUT" "feature"
rm -rf "$NOGIT"

# ============================================================
# Summary
# ============================================================
echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "ALL $TOTAL GIT INTEGRATION TESTS PASSED ($ENGINE)"
else
  echo "$FAIL/$TOTAL GIT INTEGRATION TESTS FAILED ($ENGINE)"
  exit 1
fi
