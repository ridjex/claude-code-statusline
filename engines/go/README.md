# Go Engine (v3) — Stable

Single compiled binary with zero runtime dependencies. Uses [go-git](https://github.com/go-git/go-git) for pure-Go git operations (no subprocess spawning).

## Performance

~10ms renders (vs ~100ms bash, ~480ms python). See [benchmarks/RESULTS.md](../../benchmarks/RESULTS.md) for current numbers.

## Architecture

```
cmd/statusline/main.go       # Entry point, CLI args, panic recovery
internal/
  config/config.go            # Config loading (env file + CLI args)
  render/render.go            # ANSI output assembly (Line 1 + Line 2)
  gitstate/gitstate.go        # Git state via go-git (branch, diff, stash)
  background/background.go    # Background jobs (model cache, cost scan)
  session/session.go          # Session/transcript path resolution
  format/format.go            # Number formatting (cost, tokens, duration)
```

## Build

```bash
cd engines/go
go build -o statusline ./cmd/statusline
```

Binary size: ~12MB (includes go-git).

## Test

```bash
# Unit tests
cd engines/go && go test ./...

# Integration tests (89 assertions)
make test-go
```
