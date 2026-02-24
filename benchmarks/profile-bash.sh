#!/usr/bin/env bash
# Profiles individual subprocess costs in the bash statusline engine
# Shows time spent in each jq, bc, and git call
# Usage: ./benchmarks/profile-bash.sh [fixture]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="${1:-$ROOT/tests/fixtures/basic-session.json}"

if [ ! -f "$FIXTURE" ]; then
  echo "Fixture not found: $FIXTURE"
  exit 1
fi

INPUT=$(cat "$FIXTURE")

# High-res timer (python3 for sub-ms precision)
_timer() { python3 -c 'import time; print(time.time())'; }
_elapsed_ms() { python3 -c "print(f'{($2 - $1) * 1000:.1f}')"; }

echo "=== Subprocess profiling ==="
echo "Fixture: $FIXTURE"
echo ""

TOTAL_SUB=0

# Profile jq calls (the biggest subprocess cost in bash engine)
echo "--- jq calls ---"
for field in \
  '.model.display_name' \
  '.context_window.used_percentage' \
  '.cost.total_cost_usd' \
  '.cost.total_duration_ms' \
  '.context_window.total_input_tokens' \
  '.context_window.total_output_tokens' \
  '.cost.total_api_duration_ms' \
  '.workspace.project_dir' \
  '.cost.total_lines_added' \
  '.cost.total_lines_removed' \
  '.transcript_path'; do
  T0=$(_timer)
  echo "$INPUT" | jq -r "$field // empty" >/dev/null
  T1=$(_timer)
  MS=$(_elapsed_ms "$T0" "$T1")
  printf "  jq %-45s %6s ms\n" "$field" "$MS"
  TOTAL_SUB=$(python3 -c "print($TOTAL_SUB + $MS)")
done

echo ""
echo "--- git calls ---"
for cmd in \
  "git branch --show-current" \
  "git status --porcelain" \
  "git rev-parse --show-toplevel" \
  "git rev-parse --git-common-dir" \
  "git rev-list --count @{u}..HEAD" \
  "git rev-list --count HEAD..@{u}" \
  "git stash list"; do
  T0=$(_timer)
  $cmd >/dev/null 2>&1 || true
  T1=$(_timer)
  MS=$(_elapsed_ms "$T0" "$T1")
  printf "  %-48s %6s ms\n" "$cmd" "$MS"
  TOTAL_SUB=$(python3 -c "print($TOTAL_SUB + $MS)")
done

echo ""
echo "--- bc calls ---"
for expr in "8.4 >= 1000" "8.4 >= 10" "8.4 >= 1" "41200 * 1000 / 600000"; do
  T0=$(_timer)
  echo "$expr" | bc -l >/dev/null 2>&1 || true
  T1=$(_timer)
  MS=$(_elapsed_ms "$T0" "$T1")
  printf "  bc %-45s %6s ms\n" "\"$expr\"" "$MS"
  TOTAL_SUB=$(python3 -c "print($TOTAL_SUB + $MS)")
done

echo ""
printf "  Subprocess total:                               %6s ms\n" "$(printf '%.1f' "$TOTAL_SUB")"

# Full render timing
echo ""
echo "--- Full render ---"
T0=$(_timer)
cat "$FIXTURE" | "$ROOT/engines/bash/statusline.sh" >/dev/null 2>&1
T1=$(_timer)
MS=$(_elapsed_ms "$T0" "$T1")
printf "  TOTAL RENDER:                                   %6s ms\n" "$MS"
