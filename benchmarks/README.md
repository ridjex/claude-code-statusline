# Benchmarks

Performance benchmarks for claude-code-statusline engines.

## Prerequisites

```bash
brew install hyperfine   # macOS
# apt-get install hyperfine   # Ubuntu
```

## Quick start

```bash
make bench           # benchmark all available engines
make bench-bash      # benchmark bash only
make bench-python    # benchmark python only
make bench-go        # benchmark Go only
make bench-rust      # benchmark Rust only
make profile         # detailed bash subprocess profiling
```

## What we measure

### `bench.sh` — Engine comparison

Uses [hyperfine](https://github.com/sharkdp/hyperfine) to measure end-to-end render time for each engine against the same fixture (`tests/fixtures/basic-session.json`).

- **Warmup**: 5 runs (prime filesystem caches)
- **Min runs**: 50 (statistical significance)
- **Output**: JSON + Markdown in `results/`

### `profile-bash.sh` — Subprocess profiling

Measures individual subprocess costs in the bash engine:

- Each `jq` call (~11 invocations per render)
- Each `git` call (~7 invocations per render)
- Each `bc` call (~4 invocations per render)
- Total subprocess overhead vs full render time

This reveals where bash spends time and why alternatives (Python with native JSON parsing, Go/Rust with no subprocesses) are faster.

## Methodology

1. All benchmarks use the same fixture file for fair comparison
2. Git operations run in the actual repo (so git calls are realistic)
3. Cumulative caches are NOT populated (tests worst-case for cache miss)
4. Background jobs (model parse, cost scan) are spawned but not awaited
5. Results include process startup time (important for Python vs compiled)

## Expected results

| Engine | Render time | Subprocesses | Notes |
|--------|-------------|--------------|-------|
| **Rust** | **~22ms** | **0** | 3MB binary, gix (pure Rust) |
| Go | ~113ms | 0 | 15MB binary, go-git (pure Go) |
| Python | ~470ms | 5-8 | Native JSON/math, only git forks |
| Bash | 30-100ms | 27-35 | jq + bc + git forks |

## Results directory

Benchmark results are saved in `results/` with timestamps. The `latest.json` and `latest.md` symlinks always point to the most recent run.

Results are gitignored (machine-specific). CI captures them as artifacts.
