#!/bin/bash
# Claude Code Status Line
# Reads JSON session data from stdin, outputs formatted status bar
#
# NOTE: No 'set -e' — must never crash Claude Code's render cycle.
# Errors in individual sections are silently ignored; partial output is
# preferable to no output at all.
#
# Line 1: model │ context bar │ cost │ duration │ git branch │ lines
# Line 2: per-model tokens │ speed │ proj cumulative │ all cumulative

input=$(cat)

# --- Session transcript (for per-model stats) ---
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty')
SESSION_ID=""
if [ -n "$TRANSCRIPT_PATH" ]; then
  SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
fi

# --- Dependency check ---
for _dep in jq bc; do
  if ! command -v "$_dep" &>/dev/null; then
    printf "statusline: %s required\n\n" "$_dep"
    exit 0
  fi
done

# --- Model ---
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"' | sed 's/^Claude //')

# --- Context bar (10 chars) ---
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
FILLED=$((PCT / 10))
[ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | sed 's/ /▓/g')
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | sed 's/ /░/g')"
WARN=""
if [ "$PCT" -ge 90 ]; then
  CLR="\033[31m"
  WARN=" ⚠"
elif [ "$PCT" -ge 70 ]; then
  CLR="\033[33m"
  WARN=" ⚠"
else
  CLR="\033[32m"
fi

# --- Cost (session) ---
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
# Compact: ≥1000→$12.0k, ≥100→$374, ≥10→$14, ≥1→$8.4, <1→$0.12
if [ "$(echo "$COST >= 1000" | bc 2>/dev/null)" = "1" ]; then
  COST_FMT="\$$(printf "%.1fk" "$(echo "$COST / 1000" | bc -l)")"
elif [ "$(echo "$COST >= 10" | bc 2>/dev/null)" = "1" ]; then
  COST_FMT="\$$(printf "%.0f" "$COST")"
elif [ "$(echo "$COST >= 1" | bc 2>/dev/null)" = "1" ]; then
  COST_FMT="\$$(printf "%.1f" "$COST")"
else
  COST_FMT="\$$(printf "%.2f" "$COST")"
fi

# --- Duration ---
DUR_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' | cut -d. -f1)
DUR_MIN=$((DUR_MS / 60000))
if [ "$DUR_MIN" -ge 60 ]; then
  DUR_FMT="$((DUR_MIN / 60))h$((DUR_MIN % 60))m"
else
  DUR_FMT="${DUR_MIN}m"
fi

# --- Git branch + worktree ---
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
GIT_DISPLAY=""
if [ -n "$BRANCH" ]; then
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
  COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
  IN_WT=false
  WT_NAME=""
  if [ -n "$TOPLEVEL" ] && [ -n "$COMMON" ]; then
    RESOLVED_COMMON=$(cd "$TOPLEVEL" && cd "$COMMON" 2>/dev/null && pwd)
    if [ "$RESOLVED_COMMON" != "$TOPLEVEL/.git" ]; then
      IN_WT=true
      MAIN_TOPLEVEL=$(cd "$RESOLVED_COMMON/.." 2>/dev/null && pwd)
      WT_NAME="${TOPLEVEL#$MAIN_TOPLEVEL/.worktrees/}"
    fi
  fi

  # Shorten branch prefix to icon
  shorten() {
    case "$1" in
      feature/*)  echo "★${1#feature/}" ;;
      feat/*)     echo "★${1#feat/}" ;;
      fix/*)      echo "✦${1#fix/}" ;;
      chore/*)    echo "⚙${1#chore/}" ;;
      refactor/*) echo "↻${1#refactor/}" ;;
      docs/*)     echo "§${1#docs/}" ;;
      *)          echo "$1" ;;
    esac
  }

  # Truncate to max length
  trunc() {
    local n="$1" max="${2:-20}"
    if [ "${#n}" -gt "$max" ]; then
      echo "${n:0:$((max-1))}…"
    else
      echo "$n"
    fi
  }

  SB=$(trunc "$(shorten "$BRANCH")")
  if $IN_WT; then
    SW=$(trunc "$(shorten "$WT_NAME")")
    if [ "$SW" = "$SB" ]; then
      GIT_DISPLAY="⊕ $SB"
    else
      GIT_DISPLAY="⊕${SW} $SB"
    fi
  else
    GIT_DISPLAY="$SB"
  fi
fi

# --- Dirty indicator ---
DIRTY=""
if [ -n "$BRANCH" ]; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    DIRTY="●"
  fi
fi

# --- Git ahead/behind/stash ---
GIT_EXTRA=""
if [ -n "$BRANCH" ]; then
  AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  STASH=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  [ "$AHEAD" -gt 0 ] && GIT_EXTRA="↑${AHEAD}"
  [ "$BEHIND" -gt 0 ] && GIT_EXTRA="${GIT_EXTRA}↓${BEHIND}"
  [ "$STASH" -gt 0 ] && GIT_EXTRA="${GIT_EXTRA} stash:${STASH}"
  GIT_EXTRA=$(echo "$GIT_EXTRA" | sed 's/^ //')
fi

# --- Lines added/removed ---
ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
LINES=""
if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
  LINES="\033[32m+${ADDED}\033[0m \033[31m-${REMOVED}\033[0m"
fi

# ============================================================
# LINE 2 DATA: tokens, speed, cumulative
# ============================================================

# --- Tokens ---
IN_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOK=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Format number with K suffix: 45231 → 45k, 1234 → 1.2k, 523 → 523
fmt_k() {
  local n="$1"
  if [ "$n" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "$n / 1000000" | bc -l)"
  elif [ "$n" -ge 10000 ]; then
    printf "%.0fk" "$(echo "$n / 1000" | bc -l)"
  elif [ "$n" -ge 1000 ]; then
    printf "%.1fk" "$(echo "$n / 1000" | bc -l)"
  else
    echo "$n"
  fi
}

IN_FMT=$(fmt_k "$IN_TOK")
OUT_FMT=$(fmt_k "$OUT_TOK")

# --- Speed (output tok/s) ---
API_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0' | cut -d. -f1)
SPEED_FMT=""
if [ "$API_MS" -gt 0 ] && [ "$OUT_TOK" -gt 0 ]; then
  SPEED=$(echo "$OUT_TOK * 1000 / $API_MS" | bc -l 2>/dev/null)
  SPEED_INT=$(printf "%.0f" "$SPEED")
  if [ "$SPEED_INT" -gt 30 ]; then
    SPEED_CLR="\033[32m"  # green
  elif [ "$SPEED_INT" -ge 15 ]; then
    SPEED_CLR="\033[33m"  # yellow
  else
    SPEED_CLR="\033[31m"  # red
  fi
  SPEED_FMT="${SPEED_CLR}$(printf "%.0f" "$SPEED") tok/s\033[0m"
fi

# --- Cumulative stats (from per-project + shared cache) ---
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // empty')
_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline"
CUM_PROJ="" CUM_ALL=""

# Format cost: ≥1000→$12.0k, ≥100→$374, ≥10→$14, ≥1→$8.4, <1→$0.12
fmt_cost() {
  local c="$1"
  if [ "$(echo "$c >= 1000" | bc 2>/dev/null)" = "1" ]; then
    printf "\$%.1fk" "$(echo "$c / 1000" | bc -l)"
  elif [ "$(echo "$c >= 100" | bc 2>/dev/null)" = "1" ]; then
    printf "\$%.0f" "$c"
  elif [ "$(echo "$c >= 10" | bc 2>/dev/null)" = "1" ]; then
    printf "\$%.0f" "$c"
  elif [ "$(echo "$c >= 1" | bc 2>/dev/null)" = "1" ]; then
    printf "\$%.1f" "$c"
  else
    printf "\$%.2f" "$c"
  fi
}

# Compute project hash (same logic as cumulative-stats.sh)
if [ -n "$PROJECT_DIR" ]; then
  _SLUG=$(echo "$PROJECT_DIR" | sed 's|^/||; s|/|-|g')
  if command -v md5 &>/dev/null; then
    _PROJ_HASH=$(echo "$_SLUG" | md5 -q | cut -c1-8)
  else
    _PROJ_HASH=$(echo "$_SLUG" | md5sum | cut -c1-8)
  fi
  PROJ_CACHE="$_CACHE_DIR/proj-${_PROJ_HASH}.json"

  if [ -f "$PROJ_CACHE" ]; then
    P1=$(jq -r '.d1.cost // 0' "$PROJ_CACHE")
    P7=$(jq -r '.d7.cost // 0' "$PROJ_CACHE")
    P30=$(jq -r '.d30.cost // 0' "$PROJ_CACHE")
    if [ "$(echo "$P1 > 0 || $P7 > 0 || $P30 > 0" | bc 2>/dev/null)" = "1" ]; then
      CUM_PROJ="⌂ $(fmt_cost "$P1")/$(fmt_cost "$P7")/$(fmt_cost "$P30")"
    fi
  fi
fi

ALL_CACHE="$_CACHE_DIR/all.json"
if [ -f "$ALL_CACHE" ]; then
  A1=$(jq -r '.d1.cost // 0' "$ALL_CACHE")
  A7=$(jq -r '.d7.cost // 0' "$ALL_CACHE")
  A30=$(jq -r '.d30.cost // 0' "$ALL_CACHE")
  if [ "$(echo "$A1 > 0 || $A7 > 0 || $A30 > 0" | bc 2>/dev/null)" = "1" ]; then
    CUM_ALL="Σ $(fmt_cost "$A1")/$(fmt_cost "$A7")/$(fmt_cost "$A30")"
  fi
fi

# --- Kick off cumulative stats refresh in background ---
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "$PROJECT_DIR" ] && [ -x "$_SELF_DIR/cumulative-stats.sh" ]; then
  "$_SELF_DIR/cumulative-stats.sh" "$PROJECT_DIR" &>/dev/null &
  disown 2>/dev/null
fi

# ============================================================
# PER-MODEL STATS (from transcript cache)
# ============================================================
OPUS_IN=0 OPUS_OUT=0
SONNET_IN=0 SONNET_OUT=0
HAIKU_IN=0 HAIKU_OUT=0
MODEL_MIX=""

if [ -n "$SESSION_ID" ]; then
  MODEL_CACHE="$_CACHE_DIR/models-${SESSION_ID}.json"

  # Read cached per-model stats
  if [ -f "$MODEL_CACHE" ]; then
    read -r OPUS_IN OPUS_OUT SONNET_IN SONNET_OUT HAIKU_IN HAIKU_OUT < <(
      jq -r '
        def get(pat): [.models[] | select(.model | contains(pat))] | if length > 0 then (map(.in) | add) else 0 end;
        def geto(pat): [.models[] | select(.model | contains(pat))] | if length > 0 then (map(.out) | add) else 0 end;
        "\(get("opus")) \(geto("opus")) \(get("sonnet")) \(geto("sonnet")) \(get("haiku")) \(geto("haiku"))"
      ' "$MODEL_CACHE" 2>/dev/null
    )
    OPUS_IN=${OPUS_IN:-0}; OPUS_OUT=${OPUS_OUT:-0}
    SONNET_IN=${SONNET_IN:-0}; SONNET_OUT=${SONNET_OUT:-0}
    HAIKU_IN=${HAIKU_IN:-0}; HAIKU_OUT=${HAIKU_OUT:-0}
  fi

  # Mini bar chart: height = relative output tokens per model
  _bar_char() {
    local val="$1" max="$2"
    if [ "$val" -le 0 ] 2>/dev/null || [ "$max" -le 0 ] 2>/dev/null; then return; fi
    local level=$(( (val * 8 + max / 2) / max ))
    [ "$level" -lt 1 ] && level=1
    [ "$level" -gt 8 ] && level=8
    local bars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
    printf "%s" "${bars[$((level-1))]}"
  }

  MAX_OUT=$OPUS_OUT
  [ "$SONNET_OUT" -gt "$MAX_OUT" ] 2>/dev/null && MAX_OUT=$SONNET_OUT
  [ "$HAIKU_OUT" -gt "$MAX_OUT" ] 2>/dev/null && MAX_OUT=$HAIKU_OUT

  if [ "$MAX_OUT" -gt 0 ] 2>/dev/null; then
    O_BAR=$(_bar_char "$OPUS_OUT" "$MAX_OUT")
    S_BAR=$(_bar_char "$SONNET_OUT" "$MAX_OUT")
    H_BAR=$(_bar_char "$HAIKU_OUT" "$MAX_OUT")
    # Color: Opus=magenta, Sonnet=cyan, Haiku=green; dim if unused
    O_C=$( [ -n "$O_BAR" ] && echo "\033[35m${O_BAR}" || echo "\033[2m·" )
    S_C=$( [ -n "$S_BAR" ] && echo "\033[36m${S_BAR}" || echo "\033[2m·" )
    H_C=$( [ -n "$H_BAR" ] && echo "\033[32m${H_BAR}" || echo "\033[2m·" )
    MODEL_MIX="${O_C}${S_C}${H_C}\033[0m"
  fi

  # Background: refresh model stats cache
  {
    _SDIR=$(dirname "$TRANSCRIPT_PATH")
    _MCF="$_CACHE_DIR/models-${SESSION_ID}.json"
    _FILES="$TRANSCRIPT_PATH"
    [ -d "$_SDIR/$SESSION_ID/subagents" ] && _FILES="$_FILES $_SDIR/$SESSION_ID/subagents/*.jsonl"
    cat $_FILES 2>/dev/null | jq -rs '
      [.[] | select(.type == "assistant" and .message.model and .message.usage
             and (.message.model | startswith("claude-"))) | .message] |
      group_by(.model) |
      map({
        model: .[0].model,
        in: (map((.usage.input_tokens // 0) + (.usage.cache_read_input_tokens // 0)
                + (.usage.cache_creation_input_tokens // 0)) | add),
        out: (map(.usage.output_tokens // 0) | add)
      }) | {models: .}
    ' > "$_MCF.tmp" 2>/dev/null && mv "$_MCF.tmp" "$_MCF"
  } &>/dev/null &
  disown 2>/dev/null
fi

# ============================================================
# ASSEMBLE OUTPUT
# ============================================================
DIM="\033[2m"
RST="\033[0m"
S="${DIM}│${RST}"

# --- Line 1 ---
L1="\033[36m${MODEL}${RST}"
[ -n "$MODEL_MIX" ] && L1="${L1} ${MODEL_MIX}"
L1="${L1} ${S} ${CLR}${BAR} ${PCT}%${WARN}${RST}"
L1="${L1} ${S} ${COST_FMT}"
L1="${L1} ${S} ${DUR_FMT}"
if [ -n "$GIT_DISPLAY" ]; then
  GIT_PART="\033[35m${GIT_DISPLAY}\033[0m"
  if [ -n "$DIRTY" ]; then
    GIT_PART="${GIT_PART} \033[33m${DIRTY}\033[0m"
  fi
  if [ -n "$GIT_EXTRA" ]; then
    GIT_PART="${GIT_PART} \033[36m${GIT_EXTRA}\033[0m"
  fi
  L1="${L1} ${S} ${GIT_PART}"
fi
if [ -n "$LINES" ]; then
  L1="${L1} ${S} ${LINES}"
fi

# --- Line 2 ---
# Per-model token breakdown (O:in/out S:in/out H:in/out) or fallback to totals
L2=""
if [ "$OPUS_OUT" -gt 0 ] 2>/dev/null || [ "$OPUS_IN" -gt 0 ] 2>/dev/null; then
  L2="\033[35mO\033[0m:$(fmt_k "$OPUS_IN")/$(fmt_k "$OPUS_OUT")"
fi
if [ "$SONNET_OUT" -gt 0 ] 2>/dev/null || [ "$SONNET_IN" -gt 0 ] 2>/dev/null; then
  [ -n "$L2" ] && L2="$L2 "
  L2="${L2}\033[36mS\033[0m:$(fmt_k "$SONNET_IN")/$(fmt_k "$SONNET_OUT")"
fi
if [ "$HAIKU_OUT" -gt 0 ] 2>/dev/null || [ "$HAIKU_IN" -gt 0 ] 2>/dev/null; then
  [ -n "$L2" ] && L2="$L2 "
  L2="${L2}\033[32mH\033[0m:$(fmt_k "$HAIKU_IN")/$(fmt_k "$HAIKU_OUT")"
fi
# Fallback if no model cache yet
if [ -z "$L2" ]; then
  L2="\033[2min:\033[0m${IN_FMT} \033[2mout:\033[0m${OUT_FMT}"
fi
if [ -n "$SPEED_FMT" ]; then
  L2="${L2} ${S} ${SPEED_FMT}"
fi
if [ -n "$CUM_PROJ" ]; then
  L2="${L2} ${S} ${CUM_PROJ}"
fi
if [ -n "$CUM_ALL" ]; then
  L2="${L2} ${S} ${CUM_ALL}"
fi

printf "%b\n%b\n" "$L1" "$L2"
