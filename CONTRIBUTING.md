# Contributing

## Setup

```bash
git clone https://github.com/ridjex/claude-code-statusline.git
cd claude-code-statusline
make check            # verify dependencies
```

## Development

```bash
make                  # show all targets
make test             # run all tests
make test-verbose     # verbose — shows rendered output
make demo             # regenerate demo SVGs after output changes
```

Tests use mock JSON fixtures in `tests/fixtures/`. No external services or Claude Code session needed.

## Adding a test

1. Create a fixture in `tests/fixtures/` (JSON matching Claude Code's statusline payload)
2. Add assertions in `tests/run-tests.sh` using `assert_contains` / `assert_not_contains`
3. Run `make test` to verify

## Changing output format

1. Edit `src/statusline.sh`
2. Run `make test` — update assertions if needed
3. Run `make demo` — regenerate demo SVGs
4. CI verifies SVGs are up to date (`demo-freshness` job)

## Code style

- Shell scripts follow POSIX-compatible bash
- No external dependencies beyond `jq`, `bc`, `git`
- Keep render path fast (< 10ms) — expensive work goes in background jobs
