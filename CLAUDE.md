# Claude Code Status Line — Developer Guide

## Project overview

Multi-engine status bar for Claude Code. Ships with **bash** (v1), **python** (v2), **go** (v3), and **rust** (v4) engines.
The installer auto-detects the best available engine (rust > go > python > bash).

Zero external dependencies beyond jq, bc, git (bash engine), python3 (python engine), or a single compiled binary (go/rust engines).

## Architecture

```
stdin JSON → engine → 1-2 lines stdout
               ├── sources statusline.env (config)
               ├── reads JSON caches (model stats, cumulative costs)
               ├── reads git state
               └── spawns background jobs (model parse, cost scan)

engines/
  bash/     ← v1: 27-35 subprocesses (jq + bc + git)
  python/   ← v2: 5-8 subprocesses (git only, native JSON/math)
  go/       ← v3: single binary, go-git (pure Go)
  rust/     ← v4: single binary, gix/gitoxide (pure Rust), ~3MB stripped
  (see benchmarks/RESULTS.md for current timing data)
```

## Key files

| File | Purpose |
|------|---------|
| `engines/bash/statusline.sh` | Bash renderer (~490 LOC). 15+ jq calls per render. |
| `engines/bash/cumulative-stats.sh` | Background cost aggregator. Parses JSONL transcripts. |
| `engines/bash/statusline.env.default` | Default config template. |
| `engines/python/statusline.py` | Python renderer (~250 LOC). Single JSON parse. |
| `engines/python/pyproject.toml` | Python project metadata (stdlib only). |
| `engines/go/cmd/statusline/main.go` | Go entry point + CLI orchestration. |
| `engines/go/internal/render/render.go` | Go ANSI line assembly. |
| `engines/go/internal/gitstate/gitstate.go` | Pure Go git via go-git (zero subprocess). |
| `engines/rust/src/main.rs` | Rust entry point + panic handling. |
| `engines/rust/src/render.rs` | Rust ANSI line assembly. |
| `engines/rust/src/git.rs` | Pure Rust git via gix/gitoxide (zero subprocess). |
| `install.sh` | Stack-agnostic installer. Auto-detects best engine. |
| `skill/SKILL.md` | Claude Code skill for `/statusline` command. |
| `tests/run-tests.sh` | Bash-specific test runner (80 assertions). |
| `tests/test-engine.sh` | Engine-agnostic test runner (76 assertions). |
| `tests/fixtures/` | Shared mock JSON payloads for all engines. |
| `benchmarks/bench.sh` | Hyperfine-based engine comparison. |
| `benchmarks/generate-report.sh` | Generates RESULTS.md from hyperfine JSON. |
| `benchmarks/RESULTS.md` | Auto-generated benchmark report (committed by CI). |
| `benchmarks/profile-bash.sh` | Detailed bash subprocess profiling. |
| `install-remote.sh` | Remote installer. Downloads pre-built binaries from GitHub Releases. |
| `.github/workflows/release.yml` | Release workflow. Builds 4-platform binaries on `v*` tags. |
| `src/` | Symlinks → `engines/bash/` (backward compatibility). |

## Development

```bash
make test           # run bash engine tests (80 assertions)
make test-python    # run engine-agnostic tests against Python
make test-go        # build + run engine-agnostic tests against Go
make test-rust      # build + run engine-agnostic tests against Rust
make test-all       # run all four
make test-verbose   # show rendered output
make build-go       # build Go binary (engines/go/statusline)
make build-rust     # build Rust binary (engines/rust/target/release/statusline)
make bench          # benchmark all available engines
make bench-bash     # benchmark bash only
make bench-python   # benchmark python only
make bench-go       # benchmark Go only
make bench-rust     # benchmark Rust only
make bench-report   # run benchmarks + generate RESULTS.md
make profile        # detailed bash subprocess profiling
make verify         # smoke test installed version
make diagnose       # check installation health
make demo           # regenerate SVG demos
make check          # verify dependencies
```

## Conventions

- **No `set -e`** in statusline.sh — must never crash Claude Code's render cycle
- **POSIX-compatible bash** — no bashisms beyond arrays
- **Errors are silent** — partial output is better than no output
- **Sub-5ms render** — all heavy work in background jobs, hot path reads caches only
- **Backward compatible** — new config options default to enabled
- **Config via env vars** — sourced from `~/.claude/statusline.env`, all optional
- **Output parity** — all engines must produce byte-identical ANSI output for same input

## Config system

**Precedence**: CLI args > env vars > `~/.claude/statusline.env` > defaults (all on)

CLI flags (`--no-model`, `--no-git`, etc.) work identically in all engines.

`~/.claude/statusline.env` variables:

```bash
STATUSLINE_SHOW_MODEL=true|false
STATUSLINE_SHOW_MODEL_BARS=true|false
STATUSLINE_SHOW_CONTEXT=true|false
STATUSLINE_SHOW_COST=true|false
STATUSLINE_SHOW_DURATION=true|false
STATUSLINE_SHOW_GIT=true|false
STATUSLINE_SHOW_DIFF=true|false
STATUSLINE_LINE2=true|false
STATUSLINE_SHOW_TOKENS=true|false
STATUSLINE_SHOW_SPEED=true|false
STATUSLINE_SHOW_CUMULATIVE=true|false
```

## Adding a new section

1. Add the data extraction in `engines/bash/statusline.sh`, `engines/python/statusline.py`, `engines/go/internal/render/render.go`, and `engines/rust/src/render.rs`
2. Add the variable to assembly block (Line 1 parts array or Line 2 append)
3. Add default to `engines/bash/statusline.env.default`
4. Add test assertions in `tests/run-tests.sh` and `tests/test-engine.sh`
5. Update `skill/SKILL.md` config table
6. Verify output parity: `make test-all`

## Testing

- `tests/run-tests.sh` — bash-specific tests (includes spacing, git-specific assertions)
- `tests/test-engine.sh <cmd>` — engine-agnostic tests (works with any engine)
- Use `render <fixture>` to run an engine with test data
- `assert_contains "label" "$OUT" "pattern"` — check output contains text
- Fixtures in `tests/fixtures/` — shared across all engines
- Test config toggles: `STATUSLINE_SHOW_X=false render ...`

## settings.json format

The correct format in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

**Never** set it as a plain string — that's the old bug format.
`~/.claude/statusline.sh` is always the entry point regardless of engine. For Python/Go/Rust, it's a thin wrapper.
