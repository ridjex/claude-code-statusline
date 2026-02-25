# Contributing

## Prerequisites

- **Required**: git, make, bash 3.2+, jq, bc
- **Go engine**: Go 1.23+
- **Rust engine**: Rust 1.75+ (stable)
- **Python engine**: Python 3.8+

## Setup

```bash
git clone https://github.com/ridjex/claude-code-statusline.git
cd claude-code-statusline
make check       # verify dependencies
make test-all    # run all engine tests
```

## Development Workflow

1. Fork the repo and create a feature branch
2. Make changes
3. Run `make test-all` — all engines must pass
4. Submit a PR against `main`

## Engine Parity

All 4 engines (bash, python, go, rust) must produce **byte-identical ANSI output** for the same input. If you change the output format in one engine, update all four.

The engine-agnostic test suite (`tests/test-engine.sh`) enforces this — it runs the same 76 assertions against every engine.

## Adding a New Section

See the [checklist in CLAUDE.md](CLAUDE.md#adding-a-new-section).

## Testing

```bash
make test          # bash engine (80 assertions)
make test-python   # python engine (76 assertions)
make test-go       # go engine (76 assertions)
make test-rust     # rust engine (76 assertions)
make test-all      # all four
```

Tests use mock JSON fixtures in `tests/fixtures/`. No external services or Claude Code session needed.

When adding new features, add test assertions to both:
- `tests/run-tests.sh` (bash-specific tests)
- `tests/test-engine.sh` (engine-agnostic, runs against all)

## Code Style

- **Bash**: No `set -e`, POSIX-compatible beyond arrays, errors are silent
- **Python**: stdlib only, no external dependencies
- **Go**: `go fmt`, standard library style
- **Rust**: `cargo fmt`, `cargo clippy` clean

## Questions?

Open a [discussion](https://github.com/ridjex/claude-code-statusline/discussions) or file an issue.
