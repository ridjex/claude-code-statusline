# Contributing

## Setup

```bash
git clone https://github.com/ridjex/claude-statusline.git
cd claude-statusline
```

## Testing

```bash
./tests/run-tests.sh      # run all tests
./tests/run-tests.sh -v   # verbose — shows rendered output
```

Tests use mock JSON fixtures in `tests/fixtures/`. No external services or Claude Code session needed.

## Adding a test

1. Create a fixture in `tests/fixtures/` (JSON matching Claude Code's statusline payload)
2. Add assertions in `tests/run-tests.sh` using `assert_contains` / `assert_not_contains`
3. Run tests to verify

## Code style

- Shell scripts follow POSIX-compatible bash
- No external dependencies beyond `jq`, `bc`, `git`
- Keep render path fast (< 10ms) — expensive work goes in background jobs
