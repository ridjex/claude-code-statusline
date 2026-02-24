#!/bin/bash
# Claude Code Cumulative Stats — parses JSONL transcripts, caches result
# Called in background by statusline.sh; exits instantly if caches are fresh.
#
# Two cache files (to avoid one project overwriting another's stats):
#   $CACHE_DIR/proj-<hash>.json  — per-project, fast (~1-2s)
#   $CACHE_DIR/all.json          — shared across projects (~14s)
# CACHE_DIR defaults to ~/.cache/claude-code-statusline/
#
# statusline.sh reads both using the same CACHE_DIR convention.

set -uo pipefail
umask 077

# --- Dependency check ---
for _dep in jq bc; do
  if ! command -v "$_dep" &>/dev/null; then
    echo "cumulative-stats: required command '$_dep' not found" >&2
    exit 1
  fi
done

CACHE_TTL=300  # 5 minutes

# --- Determine project slug + hash ---
PROJECT_DIR="${1:-$(pwd)}"
SLUG=$(echo "$PROJECT_DIR" | sed 's|^/||; s|/|-|g')
SLUG_PREFIX="-${SLUG}"  # prefix for hierarchical matching
ALL_TRANSCRIPTS="$HOME/.claude/projects"

# Short hash for cache filename (macOS/Linux compatible)
if command -v md5 &>/dev/null; then
  PROJ_HASH=$(echo "$SLUG" | md5 -q | cut -c1-8)
else
  PROJ_HASH=$(echo "$SLUG" | md5sum | cut -c1-8)
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline"
mkdir -p "$CACHE_DIR" 2>/dev/null

PROJ_CACHE="$CACHE_DIR/proj-${PROJ_HASH}.json"
ALL_CACHE="$CACHE_DIR/all.json"
PROJ_LOCK="$CACHE_DIR/proj-${PROJ_HASH}.lock"
ALL_LOCK="$CACHE_DIR/all.lock"

# --- Helpers ---
file_mtime() {
  if [[ "$OSTYPE" == darwin* ]]; then
    stat -f %m "$1" 2>/dev/null || echo 0
  else
    stat -c %Y "$1" 2>/dev/null || echo 0
  fi
}

cache_age() {
  local f="$1"
  [ -f "$f" ] || { echo 999999; return; }
  local mod now
  mod=$(file_mtime "$f")
  now=$(date +%s)
  echo $(( now - mod ))
}

acquire_lock() {
  local lockdir="$1"
  # mkdir is atomic — if it succeeds, we own the lock
  if mkdir "$lockdir" 2>/dev/null; then
    echo $$ > "$lockdir/pid"
    return 0
  fi
  # Stale lock? (>120s old)
  local lock_age
  lock_age=$(( $(date +%s) - $(file_mtime "$lockdir") ))
  if [ "$lock_age" -ge 120 ]; then
    rm -rf "$lockdir"
    if mkdir "$lockdir" 2>/dev/null; then
      echo $$ > "$lockdir/pid"
      return 0
    fi
  fi
  return 1
}

# --- Cleanup on exit ---
CLEANUP_LOCKS=()
cleanup() {
  for item in "${CLEANUP_LOCKS[@]}"; do
    rm -rf "$item" 2>/dev/null
  done
}
trap cleanup EXIT

# --- Core parser ---
parse_cost() {
  local dir="$1"
  local cutoff="$2"

  if [ ! -d "$dir" ]; then
    echo '{"cost":0,"calls":0}'
    return
  fi

  local files=()
  for f in "$dir"/*.jsonl; do
    [ -f "$f" ] || continue
    local mtime
    mtime=$(file_mtime "$f")
    if [ "$mtime" -ge "$cutoff" ]; then
      files+=("$f")
    fi
  done

  if [ "${#files[@]}" -eq 0 ]; then
    echo '{"cost":0,"calls":0}'
    return
  fi

  { grep -h '"type":"assistant"' "${files[@]}" 2>/dev/null || true; } | \
  jq -r '
    (.message.model // empty) as $model |
    (.message.usage // empty) as $u |
    select($model != null and $model != "<synthetic>" and $u != null) |
    (if ($model | test("opus")) then
       { "in": 15e-6, "out": 75e-6, "cr": 1.875e-6, "cw": 18.75e-6 }
     elif ($model | test("sonnet")) then
       { "in": 3e-6, "out": 15e-6, "cr": 0.3e-6, "cw": 3.75e-6 }
     elif ($model | test("haiku")) then
       { "in": 0.8e-6, "out": 4e-6, "cr": 0.08e-6, "cw": 1e-6 }
     else
       { "in": 3e-6, "out": 15e-6, "cr": 0.3e-6, "cw": 3.75e-6 }
     end) as $p |
    (($u.input_tokens // 0) * $p.in) +
    (($u.output_tokens // 0) * $p.out) +
    (($u.cache_read_input_tokens // 0) * $p.cr) +
    (($u.cache_creation_input_tokens // 0) * $p.cw)
  ' 2>/dev/null | \
  awk '{ total += $1; calls++ } END { printf "{\"cost\":%.2f,\"calls\":%d}\n", total+0, calls+0 }'
}

# --- Date boundaries ---
NOW_EPOCH=$(date +%s)
D1_EPOCH=$(( NOW_EPOCH - 1 * 86400 ))
D7_EPOCH=$(( NOW_EPOCH - 7 * 86400 ))
D30_EPOCH=$(( NOW_EPOCH - 30 * 86400 ))

# =============================================
# PART 1: Project stats (per-project cache)
# Hierarchical: matches current dir + all sub-project transcript dirs
# e.g. slug "healthforce-humanitas" matches:
#   -Users-...-healthforce-humanitas
#   -Users-...-healthforce-humanitas-healthforce-automation-code
#   -Users-...-healthforce-humanitas-PMAI-Automation
# =============================================
PROJ_AGE=$(cache_age "$PROJ_CACHE")
if [ "$PROJ_AGE" -ge "$CACHE_TTL" ]; then
  if acquire_lock "$PROJ_LOCK"; then
    CLEANUP_LOCKS+=("$PROJ_LOCK")

    PROJ_1D_COST=0; PROJ_1D_CALLS=0
    PROJ_7D_COST=0; PROJ_7D_CALLS=0
    PROJ_30D_COST=0; PROJ_30D_CALLS=0
    PROJ_MATCHED=0

    for pdir in "$ALL_TRANSCRIPTS"/*/; do
      [ -d "$pdir" ] || continue
      dname=$(basename "$pdir")
      case "$dname" in
        ${SLUG_PREFIX}|${SLUG_PREFIX}-*) ;;
        *) continue ;;
      esac

      PROJ_MATCHED=$(( PROJ_MATCHED + 1 ))

      result1=$(parse_cost "$pdir" "$D1_EPOCH")
      c=$(echo "$result1" | jq -r '.cost')
      n=$(echo "$result1" | jq -r '.calls')
      PROJ_1D_COST=$(echo "$PROJ_1D_COST + $c" | bc)
      PROJ_1D_CALLS=$(echo "$PROJ_1D_CALLS + $n" | bc)

      result7=$(parse_cost "$pdir" "$D7_EPOCH")
      c=$(echo "$result7" | jq -r '.cost')
      n=$(echo "$result7" | jq -r '.calls')
      PROJ_7D_COST=$(echo "$PROJ_7D_COST + $c" | bc)
      PROJ_7D_CALLS=$(echo "$PROJ_7D_CALLS + $n" | bc)

      result30=$(parse_cost "$pdir" "$D30_EPOCH")
      c=$(echo "$result30" | jq -r '.cost')
      n=$(echo "$result30" | jq -r '.calls')
      PROJ_30D_COST=$(echo "$PROJ_30D_COST + $c" | bc)
      PROJ_30D_CALLS=$(echo "$PROJ_30D_CALLS + $n" | bc)
    done

    UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%S")
    TMPFILE=$(mktemp "$CACHE_DIR/tmp-proj.XXXXXX")
    jq -n \
      --arg updated "$UPDATED" \
      --arg project_dir "$PROJECT_DIR" \
      --argjson matched_dirs "${PROJ_MATCHED:-0}" \
      --argjson d1_cost "${PROJ_1D_COST:-0}" \
      --argjson d1_calls "${PROJ_1D_CALLS:-0}" \
      --argjson d7_cost "${PROJ_7D_COST:-0}" \
      --argjson d7_calls "${PROJ_7D_CALLS:-0}" \
      --argjson d30_cost "${PROJ_30D_COST:-0}" \
      --argjson d30_calls "${PROJ_30D_CALLS:-0}" \
      '{
        updated: $updated,
        project_dir: $project_dir,
        matched_dirs: $matched_dirs,
        d1: { cost: $d1_cost, calls: $d1_calls },
        d7: { cost: $d7_cost, calls: $d7_calls },
        d30: { cost: $d30_cost, calls: $d30_calls }
      }' > "$TMPFILE"
    mv "$TMPFILE" "$PROJ_CACHE"
    rm -rf "$PROJ_LOCK"
  fi
fi

# =============================================
# PART 2: All-projects stats (shared cache)
# =============================================
ALL_AGE=$(cache_age "$ALL_CACHE")
if [ "$ALL_AGE" -ge "$CACHE_TTL" ]; then
  if acquire_lock "$ALL_LOCK"; then
    CLEANUP_LOCKS+=("$ALL_LOCK")

    ALL_1D_COST=0; ALL_1D_CALLS=0
    ALL_7D_COST=0; ALL_7D_CALLS=0
    ALL_30D_COST=0; ALL_30D_CALLS=0

    for pdir in "$ALL_TRANSCRIPTS"/*/; do
      [ -d "$pdir" ] || continue
      dname=$(basename "$pdir")
      case "$dname" in *+*) continue ;; esac

      result1=$(parse_cost "$pdir" "$D1_EPOCH")
      c=$(echo "$result1" | jq -r '.cost')
      n=$(echo "$result1" | jq -r '.calls')
      ALL_1D_COST=$(echo "$ALL_1D_COST + $c" | bc)
      ALL_1D_CALLS=$(echo "$ALL_1D_CALLS + $n" | bc)

      result7=$(parse_cost "$pdir" "$D7_EPOCH")
      c=$(echo "$result7" | jq -r '.cost')
      n=$(echo "$result7" | jq -r '.calls')
      ALL_7D_COST=$(echo "$ALL_7D_COST + $c" | bc)
      ALL_7D_CALLS=$(echo "$ALL_7D_CALLS + $n" | bc)

      result30=$(parse_cost "$pdir" "$D30_EPOCH")
      c=$(echo "$result30" | jq -r '.cost')
      n=$(echo "$result30" | jq -r '.calls')
      ALL_30D_COST=$(echo "$ALL_30D_COST + $c" | bc)
      ALL_30D_CALLS=$(echo "$ALL_30D_CALLS + $n" | bc)
    done

    UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%S")
    TMPFILE=$(mktemp "$CACHE_DIR/tmp-all.XXXXXX")
    jq -n \
      --arg updated "$UPDATED" \
      --argjson d1_cost "${ALL_1D_COST:-0}" \
      --argjson d1_calls "${ALL_1D_CALLS:-0}" \
      --argjson d7_cost "${ALL_7D_COST:-0}" \
      --argjson d7_calls "${ALL_7D_CALLS:-0}" \
      --argjson d30_cost "${ALL_30D_COST:-0}" \
      --argjson d30_calls "${ALL_30D_CALLS:-0}" \
      '{
        updated: $updated,
        d1: { cost: $d1_cost, calls: $d1_calls },
        d7: { cost: $d7_cost, calls: $d7_calls },
        d30: { cost: $d30_cost, calls: $d30_calls }
      }' > "$TMPFILE"
    mv "$TMPFILE" "$ALL_CACHE"
    rm -rf "$ALL_LOCK"
  fi
fi
