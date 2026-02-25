#!/usr/bin/env bash
# Benchmark runner — compares statusline engines via hyperfine
# Usage: ./benchmarks/bench.sh [engine...]
# Examples:
#   ./benchmarks/bench.sh bash              # benchmark bash only
#   ./benchmarks/bench.sh bash python       # compare bash vs python
#   ./benchmarks/bench.sh                   # all available engines
#   ./benchmarks/bench.sh --ci              # generate RESULTS.md (for CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/basic-session.json"
RESULTS="$SCRIPT_DIR/results"
mkdir -p "$RESULTS"

CI_MODE=false
if [ "${1:-}" = "--ci" ]; then
  CI_MODE=true
  shift
fi

if ! command -v hyperfine >/dev/null 2>&1; then
  echo "hyperfine not found. Install with:"
  echo "  macOS:  brew install hyperfine"
  echo "  Ubuntu: apt-get install hyperfine"
  exit 1
fi

# Engine paths (bash 3 compatible — no associative arrays)
ENGINE_NAMES=(bash python go rust)
ENGINE_CMDS=(
  "$ROOT/engines/bash/statusline.sh"
  "python3 $ROOT/engines/python/statusline.py"
  "$ROOT/engines/go/statusline"
  "$ROOT/engines/rust/target/release/statusline"
)

# Helper: get command for engine name
engine_cmd() {
  local name="$1"
  local i
  for i in "${!ENGINE_NAMES[@]}"; do
    if [ "${ENGINE_NAMES[$i]}" = "$name" ]; then
      echo "${ENGINE_CMDS[$i]}"
      return
    fi
  done
}

# Helper: check if engine is available
engine_available() {
  local name="$1"
  case "$name" in
    bash)   [ -x "$ROOT/engines/bash/statusline.sh" ] ;;
    python) [ -f "$ROOT/engines/python/statusline.py" ] && command -v python3 >/dev/null 2>&1 ;;
    go)     [ -x "$ROOT/engines/go/statusline" ] ;;
    rust)   [ -x "$ROOT/engines/rust/target/release/statusline" ] ;;
    *)      return 1 ;;
  esac
}

# Determine which engines to benchmark
if [ $# -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=()
  for name in "${ENGINE_NAMES[@]}"; do
    if engine_available "$name"; then
      TARGETS+=("$name")
    fi
  done
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No engines found to benchmark"
  exit 1
fi

echo "Benchmarking engines: ${TARGETS[*]}"
echo "Fixture: $FIXTURE"
echo ""

# Build hyperfine commands
CMDS=()
for eng in "${TARGETS[@]}"; do
  cmd=$(engine_cmd "$eng")
  if [ -z "$cmd" ]; then
    echo "Unknown engine: $eng (skipping)"
    continue
  fi
  CMDS+=("-n" "$eng" "cat $FIXTURE | $cmd --no-git --no-cumulative")
done

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Run: without git (pure render) ---
echo "=== Benchmark: render only (no git) ==="
echo ""

hyperfine \
  --warmup 5 \
  --min-runs 50 \
  --export-json "$RESULTS/render-${TIMESTAMP}.json" \
  --export-markdown "$RESULTS/render-${TIMESTAMP}.md" \
  "${CMDS[@]}"

# --- Run: with git ---
echo ""
echo "=== Benchmark: with git ==="
echo ""

CMDS_GIT=()
for eng in "${TARGETS[@]}"; do
  cmd=$(engine_cmd "$eng")
  [ -z "$cmd" ] && continue
  CMDS_GIT+=("-n" "$eng" "cat $FIXTURE | $cmd --no-cumulative")
done

hyperfine \
  --warmup 5 \
  --min-runs 50 \
  --export-json "$RESULTS/git-${TIMESTAMP}.json" \
  --export-markdown "$RESULTS/git-${TIMESTAMP}.md" \
  "${CMDS_GIT[@]}"

# Save as latest
for prefix in render git; do
  cp "$RESULTS/${prefix}-${TIMESTAMP}.json" "$RESULTS/${prefix}-latest.json"
  cp "$RESULTS/${prefix}-${TIMESTAMP}.md" "$RESULTS/${prefix}-latest.md"
done

echo ""
echo "Results: $RESULTS/{render,git}-${TIMESTAMP}.{json,md}"

# --- Generate RESULTS.md (CI mode or if jq available) ---
if [ "$CI_MODE" = true ] || [ "${GENERATE_REPORT:-}" = true ]; then
  "$SCRIPT_DIR/generate-report.sh" \
    "$RESULTS/render-latest.json" \
    "$RESULTS/git-latest.json" \
    > "$SCRIPT_DIR/RESULTS.md"
  echo "Report: $SCRIPT_DIR/RESULTS.md"
fi
