# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `--version` flag for all 4 engines

### Fixed
- Bash glob expansion bug in subagent file collection (statusline.sh)
- Rust `truncate()` panic on zero-length max (format.rs)

## [2.0.0] — 2026-02-25

First release with pre-built binaries and multi-engine architecture.

### Added
- **Rust engine (v4)**: ~6ms renders, pure Rust git via gix/gitoxide, ~3MB binary
- **Go engine (v3)**: ~10ms renders, pure Go git via go-git, single binary
- **Python engine (v2)**: ~480ms renders, stdlib only, no compiled dependencies
- **Bash engine (v1)**: original engine, ~100ms renders, jq + bc + git
- Auto-engine detection: installer picks the fastest available (rust > go > python > bash)
- Remote installer (`install-remote.sh`): one-line curl install with SHA-256 verification
- GitHub Releases: pre-built binaries for darwin-arm64, darwin-amd64, linux-amd64, linux-arm64
- Release workflow: automated cross-compilation on `v*` tags
- CLI section toggles: `--no-model`, `--no-git`, `--no-line2`, etc.
- Line 2: per-model token counts, throughput (tok/s), project + global cumulative costs
- Config via `~/.claude/statusline.env` with precedence: CLI > env > file > defaults
- Claude Code skill (`/statusline`) for in-session management
- Engine-agnostic test suite (76 assertions per engine, 80 for bash-specific)
- CI pipeline: tests, shellcheck, benchmarks with auto-generated RESULTS.md
- Hyperfine benchmarks comparing all engines (render-only and with-git modes)

### Architecture
- All engines produce byte-identical ANSI output for the same input
- Compiled engines (Go, Rust) use pure-library git — zero subprocess spawning
- Background jobs handle heavy work (model cache, cost scan); hot path reads caches only
- Panic recovery in Go and Rust — status line never crashes Claude Code's render cycle

## [1.0.0] — 2025-01-01

### Added
- Initial bash engine with 2-line status bar
- Model info, context window bar, session cost, duration
- Git branch and diff stats
- Configurable sections via environment variables
- SVG demo generation
- Installation script with settings.json auto-configuration
