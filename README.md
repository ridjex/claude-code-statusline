# Claude Code Status Line

2-line terminal status bar for Claude Code sessions.

```
Opus 4.6 █▅· │ ▓▓▓░░░░░░░ 38% │ $8.4 │ 15m │ ✦edit-link │ +127 -34
O:549k/41k S:1.6k/184 H:116k/22 │ 223 tok/s │ ⌂ $374/$4.0k/$7.1k │ Σ $552/$4.7k/$12.0k
```

## Install

```bash
./install.sh
claude config set --global statusline "~/.claude/statusline.sh"
```

Requires: `jq`, `bc`, `git`

## Test

```bash
./tests/run-tests.sh      # 50 assertions
./tests/run-tests.sh -v   # verbose — shows rendered output
```

## Line 1

```
Opus 4.6 █▅· │ ▓▓▓░░░░░░░ 38% │ $8.4 │ 15m │ ✦edit-link ● │ +127 -34
\_model_/ ^^^   \__context__/     cost   dur   \___git___/     \_diff_/
          │││
          │││  Mini bars — model mix by output tokens
          ││└─ Haiku  (green)
          │└── Sonnet (cyan)
          └─── Opus   (magenta)
```

| Segment | Example | Description |
|---------|---------|-------------|
| Model | `Opus 4.6` | Active model, `Claude ` prefix stripped |
| Mini bars | `█▅·` | Bar height = relative output tokens. `·` = not used |
| Context | `▓▓▓░░░░░░░ 38%` | 10-char bar. Yellow `⚠` at 70%, red `⚠` at 90% |
| Cost | `$8.4` | Session cost. `$12.0k` for >= $1000 |
| Duration | `15m` | Wall clock. `4h0m` for >= 60min |
| Git | `✦edit-link ●` | Branch with icon, `●` dirty, `↑↓` ahead/behind, `⊕` worktree |
| Diff | `+127 -34` | Lines added/removed |

Branch icons: `★` feature, `✦` fix, `⚙` chore, `↻` refactor, `§` docs

## Line 2

```
O:549k/41k S:1.6k/184 │ 223 tok/s │ ⌂ $374/$4.0k/$7.1k │ Σ $552/$4.7k/$12.0k
\___per-model tokens__/   speed       \__this project__/     \___all projects__/
                                       day / week / month     day / week / month
```

| Segment | Example | Description |
|---------|---------|-------------|
| Tokens | `O:549k/41k S:1.6k/184` | Per-model in/out. Only used models shown |
| Speed | `223 tok/s` | Output throughput. Green >30, yellow 15-30, red <15 |
| `⌂` | `$374/$4.0k/$7.1k` | This project: day/week/month cost |
| `Σ` | `$552/$4.7k/$12.0k` | All projects: day/week/month cost |

## How it works

Claude Code pipes JSON to `statusline.sh` via stdin on every render cycle.

```
stdin JSON ──> statusline.sh ──> 2 formatted lines (stdout)
                  │
                  ├── reads cached model stats (models-{session}.json)
                  ├── reads cached cumulative costs (proj-*.json, all.json)
                  ├── reads git state (branch, dirty, ahead/behind)
                  │
                  └── spawns 2 background jobs (non-blocking):
                        ├── parse transcript → update model cache
                        └── cumulative-stats.sh → update cost caches
```

- Render: ~5ms (reads JSON caches, no parsing)
- Background model parse: ~50-100ms
- Background cost scan: ~2-14s (depends on transcript volume, cached 5min)

## Files

```
~/.claude/
  statusline.sh          # main renderer
  cumulative-stats.sh    # background cost aggregator

~/.cache/claude-code-statusline/
  models-{session}.json  # per-session model tokens (auto-created)
  proj-{hash}.json       # per-project cost cache (auto-created)
  all.json               # all-projects cost cache (auto-created)
```

## Formatting rules

| Type | Range | Format | Example |
|------|-------|--------|---------|
| Cost | >= $1000 | `$X.Xk` | `$12.0k` |
| Cost | >= $10 | `$X` | `$374` |
| Cost | >= $1 | `$X.X` | `$8.4` |
| Cost | < $1 | `$X.XX` | `$0.12` |
| Tokens | >= 1M | `X.XM` | `1.2M` |
| Tokens | >= 10k | `Xk` | `45k` |
| Tokens | >= 1k | `X.Xk` | `1.6k` |
| Tokens | < 1k | raw | `184` |

## Edge cases

- **First render** — no mini bars, no per-model breakdown. Shows `in:288k out:41k` fallback. Background job populates cache for next render.
- **Single model** — one letter in Line 2 (`O:549k/41k`). Mini bars: one bar + two dim dots.
- **No git repo** — git section omitted.
- **No cumulative cache** — `⌂` and `Σ` sections omitted until first background run.
- **macOS vs Linux** — uses `md5`/`stat -f` on macOS, `md5sum`/`stat -c` on Linux.
- **Branch truncation** — names > 20 chars truncated with `…`.
- **Worktree** — `⊕` prefix when working inside a git worktree.

## Project structure

```
claude-statusline/
  install.sh               # installer with dependency check + backup
  README.md
  src/
    statusline.sh           # main renderer (373 lines)
    cumulative-stats.sh     # background cost aggregator (274 lines)
  tests/
    run-tests.sh            # test runner (50 assertions)
    fixtures/
      basic-session.json    # standard session
      high-context.json     # 78% context (yellow warning)
      critical-context.json # 92% context (red warning)
      cheap-session.json    # $0.03 session
      expensive-session.json# $1.8k session
      minimal.json          # zero tokens, zero cost
      cumulative-proj.json  # project cost cache mock
      cumulative-all.json   # all-projects cost cache mock
      models-cache.json     # per-model token cache mock
```
