# Claude Code Status Line — Developer Guide

## Project overview

Pure-bash status bar for Claude Code. Zero external dependencies beyond jq, bc, git.
Our differentiator vs competitors (ccstatusline, CCometixLine): no npm, no Rust, no Python — just bash.

## Architecture

```
stdin JSON → statusline.sh → 1-2 lines stdout
               ├── sources statusline.env (config)
               ├── reads JSON caches (model stats, cumulative costs)
               ├── reads git state
               └── spawns background jobs (model parse, cost scan)
```

## Key files

| File | Purpose |
|------|---------|
| `src/statusline.sh` | Main renderer (~400 lines). Reads JSON from stdin, outputs formatted lines. |
| `src/cumulative-stats.sh` | Background cost aggregator. Parses JSONL transcripts, caches per-project costs. |
| `src/statusline.env.default` | Default config template. Copied to `~/.claude/statusline.env` on install. |
| `install.sh` | Idempotent installer. Handles fresh/upgrade/repair scenarios. |
| `skill/SKILL.md` | Claude Code skill for `/statusline` command. |
| `tests/run-tests.sh` | Test runner. All assertions use `assert_contains` pattern. |
| `tests/fixtures/` | Mock JSON payloads for each test scenario. |

## Development

```bash
make test           # run all tests
make test-verbose   # show rendered output
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

## Config system

**Precedence**: CLI args > env vars > `~/.claude/statusline.env` > defaults (all on)

CLI flags (`--no-model`, `--no-git`, etc.) can be passed directly to statusline.sh and override all other config sources. See `statusline.sh --help`.

`~/.claude/statusline.env` is sourced at the top of statusline.sh. Variables:

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

Helper function: `_show() { [ "${1:-true}" != "false" ]; }`

## Adding a new section

1. Add the data extraction inside a `_show` guard
2. Add the variable to assembly block (Line 1 `_parts` array or Line 2 append)
3. Add default to `src/statusline.env.default`
4. Add test assertions in `tests/run-tests.sh`
5. Update `skill/SKILL.md` config table

## Testing

- Use `render <fixture>` to run statusline.sh with test data
- `assert_contains "label" "$OUT" "pattern"` — check output contains text
- `assert_not_contains` — check output does NOT contain text
- `strip_ansi` removes ANSI codes for comparison
- Fixtures in `tests/fixtures/` — add new ones for new scenarios
- Test config toggles by setting env vars: `STATUSLINE_SHOW_X=false render ...`

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
