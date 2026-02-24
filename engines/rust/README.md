# Rust Engine (Planned)

Status: **Not yet implemented**

## Design Notes

The Rust engine targets maximum performance with zero-cost abstractions.

### Advantages over other engines
- Zero-cost abstractions, no GC
- serde_json for zero-copy JSON parsing
- git2-rs (libgit2 bindings) for native git
- Sub-millisecond render times
- Single static binary

### Target architecture
```
src/
  main.rs          # Entry point, CLI args (clap)
  config.rs        # Config loading (env file + args)
  render.rs        # ANSI output assembly
  git.rs           # Git state (git2-rs)
  cache.rs         # JSON cache read/write
  format.rs        # Number formatting
Cargo.toml
```

### Dependencies (minimal)
- `serde` + `serde_json` — JSON parsing
- `git2` — native git operations
- `clap` — CLI argument parsing

### Expected performance
- Render: <1ms (vs 30-100ms bash, 5-15ms python, 1-3ms go)
- Zero subprocesses
- ~2MB binary size (static)

### Build
```bash
cd engines/rust
cargo build --release
```
