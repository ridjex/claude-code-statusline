# Go Engine: Insights, Lessons & Article Material

> Comprehensive notes from building the Go (v3) engine for claude-code-statusline.
> Written for future reference and as raw material for a technical article.

---

## 1. The Performance Story: Three Engines, One Output

### The progression

| Engine | Version | Avg render | Subprocesses | LOC |
|--------|---------|-----------|--------------|-----|
| Bash   | v1      | 168ms     | 27-35 (jq+bc+git) | ~490 |
| Python | v2      | 39ms      | 5-8 (git only)    | ~250 |
| Go     | v3      | 11ms      | 0 (hot path)       | ~350 |

**Key insight**: Each engine was a fundamentally different approach to the same problem. Bash shells out for everything (jq for JSON, bc for math, git for state). Python uses native JSON/math but still shells out for git. Go eliminates all subprocesses by using go-git (pure Go git implementation).

**The 15x improvement** from Bash to Go isn't about Go being "faster" in isolation — it's about eliminating 27-35 subprocess spawns per render. Each `jq` call in Bash costs ~3-5ms of fork+exec overhead. Multiply by 15+ calls and you get the bulk of the 168ms.

### The real bottleneck: subprocess overhead, not computation

The actual computation (parse JSON, format numbers, assemble ANSI strings) takes <1ms in any language. The performance difference is almost entirely fork+exec overhead:

- Bash: 27-35 subprocesses × ~4ms each ≈ ~110-140ms
- Python: 5-8 git calls × ~5ms each ≈ ~25-40ms
- Go: 0 subprocesses = pure computation time

**Article angle**: "The hidden cost of shelling out — why your CLI tool is 15x slower than it needs to be"

---

## 2. go-git: Pure Go Git — Tradeoffs

### What works great
- **Zero CGO, cross-compiles perfectly** — single binary for any OS/arch
- **Branch name, dirty status** — straightforward API
- **Config parsing** — reads .git/config for upstream tracking info

### What doesn't exist (and how we worked around it)
- **No reflog API** → Read `.git/logs/refs/stash` directly for stash count
- **No `rev-list --count`** → Walk commit graph manually with 1000-commit limit
- **No `status --porcelain`** → `Worktree().Status()` does a full working tree scan

### The stash hack

go-git has no reflog support, so stash counting requires direct filesystem reads:
```
.git/logs/refs/stash  →  count non-empty lines
```
For worktrees, the stash file is in the **common dir** (main .git), not the worktree's gitdir. This required writing a `findCommonDir()` that parses `.git` files (worktrees use a text file, not a directory, for `.git`).

### Ahead/behind: the commit walk problem

Without `rev-list`, counting ahead/behind requires:
1. Collect N commits from upstream into a set
2. Walk N commits from HEAD, count those NOT in the upstream set
3. Reverse for behind count

With a 1000-commit limit, this is O(2000) commit reads max. In practice, most repos are <50 commits ahead/behind, so it terminates fast. But on large monorepos with divergent histories, the walk could add 5-10ms.

**Article angle**: "When your library doesn't have the API you need — creative workarounds in go-git"

---

## 3. Output Parity: The Hardest Part

### The challenge

Three engines in three languages must produce **byte-identical ANSI output** for the same input. This means matching:
- Number formatting (rounding behavior)
- ANSI escape code sequences (exact same codes)
- Unicode characters (same codepoints)
- Separator format (space + dim + │ + reset + space)
- Whitespace and newlines (always exactly 2 lines)

### Rounding: the IEEE 754 trap

`fmt.Sprintf("%.0f", 287.5)` in Go uses **banker's rounding** (round half to even), producing `"288"`. This matches Python's `round()` and bash's `printf "%.0f"`. But `math.Round()` in Go uses **half-away-from-zero**, which would give `"288"` for 287.5 (same) but `"43"` for 42.5 where banker's gives `"42"`.

The speed display uses `math.RoundToEven()` (not `math.Round()`) to match Python/bash behavior exactly. The formatting functions (`FmtK`, `FmtCost`) use `fmt.Sprintf("%.Nf")` which already does banker's rounding internally.

**Lesson**: When multiple languages must produce identical output, test edge cases around .5 boundaries explicitly. IEEE 754 rounding is a cross-language consistency minefield.

### The MD5 newline gotcha

Project cache hashes are computed as: `md5(slug + "\n")` — note the **trailing newline**. This exists because bash's `echo "$slug" | md5` implicitly adds a newline. Python and Go must explicitly append `"\n"` to match. Missing this would cause cache lookups to fail silently (no cumulative stats shown).

**Lesson**: When porting hash computations from shell scripts, always check if the input tool adds trailing newlines. `echo` does, `printf "%s"` doesn't.

### The test-driven parity approach

The engine-agnostic test runner (`test-engine.sh`) was the key enabler. It runs the same 69 assertions against any engine:
```bash
./tests/test-engine.sh "engines/go/statusline"
./tests/test-engine.sh "python3 engines/python/statusline.py"
./tests/test-engine.sh "engines/bash/statusline.sh"
```

Plus a direct diff check:
```bash
diff <(bash_engine --no-git) <(go_engine --no-git)  # must be empty
```

This test design meant the Go engine was either 100% compatible or it wasn't — no ambiguity.

---

## 4. Architecture Decisions That Paid Off

### "Never crash the render cycle"

The top-level `defer recover()` catches any panic and outputs `"\n\n"` (empty 2-line output). This is critical because Claude Code calls the statusline on every render tick. A crash would break the entire UI.

Every function returns zero values on error. Every file read returns nil on failure. Every cache miss is silent. This "errors are invisible" convention means partial output is always better than no output.

### Config precedence: 4 layers

```
defaults (all true)
  ← statusline.env file
    ← environment variables
      ← CLI --no-X flags
```

The tricky part: env vars must override the config file, but both are loaded via `os.Getenv()`. Solution: save env overrides before loading the file, source the file, then restore overrides. All three engines implement this identically.

### Self-exec for background jobs

The Go binary re-executes itself with `--internal-refresh-models` to refresh model caches in the background. This avoids goroutines (which die with the main process) while keeping everything in a single binary. The pattern:
1. Main process renders output in ~11ms
2. Spawns detached child with `Setpgid: true`
3. Main exits
4. Child reads JSONL transcripts, writes cache, exits

Cumulative stats still delegate to the bash script (complex file locking logic not worth reimplementing).

---

## 5. Engineering Insights

### The "all float64" JSON strategy

Go's `encoding/json` fails if you try to unmarshal `8.42` into an `int` field. Rather than using `json.Number` or custom unmarshalers, all numeric JSON fields are `float64`. Conversion to `int` happens at use site: `int(sess.Cost.TotalLinesAdded)`. Simple, robust, zero edge cases.

### golangci-lint: know your conventions

The linter flagged 4 `errcheck` issues:
- `fmt.Fprint(os.Stdout, ...)` — can't do anything if stdout write fails
- `defer f.Close()` on read-only files — error is meaningless

Both are correct conventions for a statusline. Fixed with `_, _ = fmt.Fprint(...)` and `defer func() { _ = f.Close() }()` rather than suppressing via config.

### Binary size: the go-git tax

The compiled binary is ~15MB due to go-git's dependency tree (crypto, ssh, transport). For a statusline that runs on every render tick, this is acceptable (binary is loaded once and cached by OS). Could be reduced with `-ldflags="-s -w"` (~12MB) or UPX (~4MB).

### Test coverage architecture

```
Unit tests (Go):     60+ assertions  — format, config, cache, session, render
Integration tests:   69 assertions   — engine-agnostic (test-engine.sh)
Bash-specific tests: 80 assertions   — spacing, git-specific
                     ──────────────
Total:              209+ assertions
```

The Go unit tests complement (not duplicate) the integration tests. Unit tests cover edge cases and internal behavior (IEEE 754 rounding, zero-value caches, empty sessions). Integration tests verify the full pipeline and output parity.

---

## 6. What Would Be Different Next Time

### Consider skipping go-git for v1

For a statusline, git operations are the minority case (5 out of 15+ data sections). Using `os/exec` to call `git` (like Python does) would have:
- Eliminated the go-git dependency (15MB → ~3MB binary)
- Avoided the stash/ahead-behind workarounds
- Reduced development time by ~30%

The performance difference would be ~5ms per render (still 10x faster than bash).

**Counterpoint**: go-git enables cross-compilation without git installed, and the workarounds were educational.

### Start with the test runner

The engine-agnostic test runner existed before the Go engine. This was the single most valuable development asset. Writing a new engine against an existing test suite is dramatically faster than writing code and tests simultaneously.

### Profile first, optimize later

We could have profiled the bash engine to identify which jq calls to optimize. Instead, we rewrote everything. Both approaches work, but profiling would have identified that 3-4 jq calls account for 60% of the bash render time — targeting just those with caching could have gotten to ~50ms without a rewrite.

---

## 7. Potential Article Angles

1. **"From 168ms to 11ms: Eliminating subprocess overhead in CLI tools"**
   - Main story: the performance journey across three languages
   - Technical depth: fork+exec costs, go-git tradeoffs, process lifecycle

2. **"Building the same tool in Bash, Python, and Go: what each language teaches"**
   - Comparative architecture: how the same logic looks in each language
   - LOC comparison, error handling philosophies, testing approaches

3. **"Output parity across languages: the rounding, hashing, and ANSI traps"**
   - Deep dive on IEEE 754 banker's rounding
   - The md5 newline gotcha
   - Testing strategies for cross-language consistency

4. **"go-git in production: when the library doesn't have your API"**
   - Stash via direct file reads, ahead/behind via commit walks
   - When to use a library vs subprocess

5. **"Designing for never-crash: error handling in render-cycle tools"**
   - defer recover(), silent errors, partial output philosophy
   - Config precedence with 4 layers
   - Background job lifecycle with self-exec

---

## 8. Raw Numbers for Reference

### Benchmark data (basic-session.json --no-git, 10 runs)

```
Go:     avg=11.2ms  min=8.4ms   max=15.1ms
Python: avg=39.2ms  min=37.7ms  max=42.8ms
Bash:   avg=167.5ms min=156.4ms max=185.2ms
```

### Code metrics

```
engines/go/ source:   ~350 LOC (excluding tests)
engines/go/ tests:    ~450 LOC
engines/go/ total:    ~800 LOC
go.sum dependencies:  108 lines (go-git + transitive)
Binary size:          ~15MB (darwin/arm64, unstripped)
```

### Test matrix

```
make test:        80/80   bash assertions
make test-python: 69/69   python assertions
make test-go:     69/69   go assertions (integration)
go test ./...:    60+     go unit assertions
golangci-lint:    0       issues
```
