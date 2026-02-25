# Rust Engine (v4)

Status: **Stable**

The fastest engine — pure Rust with gix (gitoxide) for native git operations.

## Performance

| Metric | Value |
|--------|-------|
| Render (no git) | ~13ms |
| Render (with git) | ~22ms |
| Binary size | ~3MB (stripped, LTO) |
| Subprocesses | 0 (hot path) |

5x faster than Go engine on git operations thanks to gix's efficient index-worktree diff.

## Architecture

```
src/
  main.rs          # Entry point, panic handler, CLI dispatch
  config.rs        # Config loading (env file + CLI args, no clap)
  render.rs        # ANSI output assembly (Line 1 + Line 2)
  git.rs           # Git state via gix (branch, dirty, ahead/behind, stash, worktree)
  cache.rs         # JSON cache read (model stats, cumulative costs)
  format.rs        # Number formatting (costs, tokens, duration, bars)
  session.rs       # Stdin JSON parsing (serde)
  background.rs    # Background job spawning + JSONL transcript parsing
```

## Dependencies

- `serde` + `serde_json` — JSON parsing
- `gix` — pure Rust git (gitoxide), zero subprocess
- `md-5` — project hash for cache paths
- `libc` — `setpgid` for background job detachment

No `clap`, no `regex`, no `tokio`. Minimal dependency tree.

## Build

```bash
cd engines/rust
cargo build --release
# Binary: target/release/statusline (~3MB)
```

## Test

```bash
# Engine-agnostic test suite (76 assertions)
./tests/test-engine.sh "engines/rust/target/release/statusline"

# Or via Makefile
make test-rust
```
