#!/usr/bin/env bash
# Benchmark runner — compares statusline engines via hyperfine
# Usage: ./benchmarks/bench.sh [engine...]
# Examples:
#   ./benchmarks/bench.sh bash              # benchmark bash only
#   ./benchmarks/bench.sh bash python       # compare bash vs python
#   ./benchmarks/bench.sh                   # all available engines

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/basic-session.json"
RESULTS="$SCRIPT_DIR/results"
mkdir -p "$RESULTS"

if ! command -v hyperfine &>/dev/null; then
  echo "hyperfine not found. Install with:"
  echo "  macOS:  brew install hyperfine"
  echo "  Ubuntu: apt-get install hyperfine"
  exit 1
fi

# Engine detection
declare -A ENGINES
ENGINES[bash]="$ROOT/engines/bash/statusline.sh"
ENGINES[python]="python3 $ROOT/engines/python/statusline.py"
ENGINES[go]="$ROOT/engines/go/statusline"
# ENGINES[rust]="$ROOT/engines/rust/target/release/statusline"

# Determine which engines to benchmark
if [ $# -gt 0 ]; then
  TARGETS=("$@")
else
  # Auto-detect available engines
  TARGETS=()
  [ -f "$ROOT/engines/bash/statusline.sh" ] && TARGETS+=(bash)
  [ -f "$ROOT/engines/python/statusline.py" ] && command -v python3 &>/dev/null && TARGETS+=(python)
  [ -f "$ROOT/engines/go/statusline" ] && TARGETS+=(go)
  # [ -f "$ROOT/engines/rust/target/release/statusline" ] && TARGETS+=(rust)
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No engines found to benchmark"
  exit 1
fi

echo "Benchmarking engines: ${TARGETS[*]}"
echo "Fixture: $FIXTURE"
echo ""

CMDS=()
for eng in "${TARGETS[@]}"; do
  cmd="${ENGINES[$eng]:-}"
  if [ -z "$cmd" ]; then
    echo "Unknown engine: $eng (skipping)"
    continue
  fi
  CMDS+=("-n" "$eng" "cat $FIXTURE | $cmd 2>/dev/null")
done

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

hyperfine \
  --warmup 5 \
  --min-runs 50 \
  --export-json "$RESULTS/bench-${TIMESTAMP}.json" \
  --export-markdown "$RESULTS/bench-${TIMESTAMP}.md" \
  "${CMDS[@]}"

# Also save as latest
cp "$RESULTS/bench-${TIMESTAMP}.json" "$RESULTS/latest.json"
cp "$RESULTS/bench-${TIMESTAMP}.md" "$RESULTS/latest.md"

echo ""
echo "Results saved to:"
echo "  $RESULTS/bench-${TIMESTAMP}.json"
echo "  $RESULTS/bench-${TIMESTAMP}.md"
