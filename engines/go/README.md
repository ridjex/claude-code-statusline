# Go Engine (Planned)

Status: **Not yet implemented**

## Design Notes

The Go engine will be a single compiled binary with zero runtime dependencies.

### Advantages over bash/python
- Single binary, no interpreter startup
- Native JSON parsing (encoding/json)
- Native math (no bc subprocesses)
- go-git or libgit2 bindings (no git subprocesses)
- Cross-compilation for linux/darwin/arm64

### Target architecture
```
cmd/statusline/main.go    # Entry point, CLI args
internal/
  config/config.go        # Config loading (env file + args)
  render/render.go        # ANSI output assembly
  git/git.go              # Git state (go-git)
  cache/cache.go          # JSON cache read/write
  format/format.go        # Number formatting (cost, tokens, duration)
```

### Expected performance
- Render: ~1-3ms (vs 30-100ms bash, 5-15ms python)
- Zero subprocesses
- ~5MB binary size

### Build
```bash
cd engines/go
go build -o statusline ./cmd/statusline
```
