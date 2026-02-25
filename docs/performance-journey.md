# The Performance Journey: Bash → Python → Go → Rust

How we evolved a CLI status bar from 27 subprocesses per render to zero.

## Chapter 1: Why Bash?

Claude Code Status Line started as a pure-bash project. The philosophy was simple: **zero dependencies beyond what's already on your machine**. Every macOS and Linux system has bash, jq is a single `brew install` away, and bc/git are pre-installed.

The appeal:
- No npm, no pip, no cargo — just copy a script
- Easy to read, easy to modify
- The entire renderer is one file
- Installation is `cp` and `chmod +x`

## Chapter 2: The Subprocess Problem

Bash is a process orchestrator, not a data processor. Our status bar does this on every render:

```
JSON input (stdin)
  ├── jq .model.display_name          # subprocess 1
  ├── jq .context_window.used_percentage  # subprocess 2
  ├── jq .cost.total_cost_usd         # subprocess 3
  ├── jq .cost.total_duration_ms      # subprocess 4
  ├── jq .context_window.total_input_tokens   # subprocess 5
  ├── jq .context_window.total_output_tokens  # subprocess 6
  ├── jq .cost.total_api_duration_ms   # subprocess 7
  ├── jq .workspace.project_dir        # subprocess 8
  ├── jq .cost.total_lines_added       # subprocess 9
  ├── jq .cost.total_lines_removed     # subprocess 10
  ├── jq .transcript_path              # subprocess 11
  │
  ├── echo "... >= 1000" | bc          # subprocess 12
  ├── echo "... >= 10" | bc            # subprocess 13
  ├── echo "... >= 1" | bc             # subprocess 14
  ├── echo "... / 1000" | bc -l        # subprocess 15
  │
  ├── git branch --show-current        # subprocess 16
  ├── git rev-parse --show-toplevel    # subprocess 17
  ├── git rev-parse --git-common-dir   # subprocess 18
  ├── git status --porcelain           # subprocess 19
  ├── git rev-list --count @{u}..HEAD  # subprocess 20
  ├── git rev-list --count HEAD..@{u}  # subprocess 21
  ├── git stash list                   # subprocess 22
  │
  ├── ... more bc for fmt_k()          # subprocesses 23-30
  ├── ... more bc for fmt_cost()       # subprocesses 31-35
  └── ... sed, cut, wc calls           # subprocesses 36+
```

**27-35 subprocesses per render.** Each one is a fork+exec. On macOS, that's ~2-4ms per process just for overhead. Total render: 30-100ms.

### Profiling

Run `make profile` to see where your machine spends time:

```
=== Subprocess profiling ===
  jq .model.display_name                           2.3 ms
  jq .context_window.used_percentage                2.1 ms
  jq .cost.total_cost_usd                           2.0 ms
  ...
  git branch --show-current                         3.5 ms
  git status --porcelain                            5.2 ms
  ...
  bc "8.4 >= 1000"                                  1.8 ms

  Subprocess total:                                42.1 ms
  TOTAL RENDER:                                    67.3 ms
```

Most of the time is subprocess startup overhead, not actual computation.

## Chapter 3: Python Port

The insight: Python's stdlib has everything we need. `json.load()` replaces 11 jq calls. `int`/`float` math replaces 4+ bc calls. Only git still needs subprocesses.

### Before (bash)
```bash
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
if [ "$(echo "$COST >= 1000" | bc)" = "1" ]; then
  COST_FMT="\$$(printf "%.1fk" "$(echo "$COST / 1000" | bc -l)")"
elif [ "$(echo "$COST >= 10" | bc)" = "1" ]; then
  COST_FMT="\$$(printf "%.0f" "$COST")"
...
```

### After (python)
```python
cost = float(data.get("cost", {}).get("total_cost_usd", 0))
if cost >= 1000:
    return f"${cost / 1000:.1f}k"
elif cost >= 10:
    return f"${cost:.0f}"
...
```

### Results

| Metric | Bash | Python | Improvement |
|--------|------|--------|-------------|
| Subprocesses | 27-35 | 5-8 | 75% fewer |
| Render time | 30-100ms | 5-15ms | 3-10x faster |
| JSON parsing | 11 jq calls | 1 json.load | 11x fewer |
| Math operations | 4+ bc calls | Native | ∞ faster |
| Lines of code | ~490 | ~250 | 49% smaller |

The Python engine produces **byte-identical output** to bash. Verified by the engine-agnostic test suite.

## Chapter 4: Go Port (Shipped)

Go eliminates the last remaining subprocesses (git calls) via go-git (pure Go):

- Single compiled binary (~15MB, due to go-git's dependency tree)
- Native JSON parsing (`encoding/json` — single `Unmarshal`)
- Native git operations (go-git — zero subprocess, zero CGO)
- Cross-compilation for all platforms
- Measured: **~11ms average render** (8ms min)

### Results

| Metric | Python | Go | Improvement |
|--------|--------|------|-------------|
| Subprocesses | 5-8 | 0 | 100% fewer |
| Render time | 5-15ms | ~11ms | Comparable (startup-bound) |
| Git operations | subprocess | pure Go | Zero fork overhead |
| Binary size | — | ~15MB | Single file, no deps |
| Dependencies | python3 | none | Fully self-contained |

The Go engine produces **byte-identical output** to bash and Python. Verified by the engine-agnostic test suite (76 assertions).

### Key tradeoffs

- **Binary size**: 15MB due to go-git pulling in crypto/ssh/transport. Could reduce to ~12MB with `-ldflags="-s -w"` or ~4MB with UPX.
- **go-git limitations**: No reflog API (stash counted via direct file read), no rev-list equivalent (ahead/behind uses 1000-commit walk cap).
- **Cumulative stats**: Still delegates to `cumulative-stats.sh` — the bash aggregator has complex file locking not worth reimplementing.

## Chapter 5: Rust Port (Shipped)

The Rust engine uses gix (gitoxide) for pure Rust git operations — significantly faster than go-git:

- Single compiled binary (~3MB, stripped with LTO)
- serde for JSON parsing (single `from_slice`)
- gix for native git (zero subprocess, index-worktree diff for dirty check)
- No clap, no regex, no tokio — minimal dependency tree
- Measured (hyperfine, 100+ runs): **~6.5ms with git**, **12x faster than Go**

### Results

| Metric | Go | Rust | Improvement |
|--------|------|------|-------------|
| Render (no git) | ~6ms | ~6.5ms | Comparable (startup-bound) |
| Render (with git) | ~80ms | ~6.5ms | 12x faster |
| Binary size | ~15MB | ~3MB | 5x smaller |
| Git library | go-git (pure Go) | gix (pure Rust) | Nearly zero git overhead |
| Dependencies | go-git pulls crypto/ssh | gix minimal features | Smaller tree |

The Rust engine produces **byte-identical output** to all other engines. Verified by the engine-agnostic test suite (76 assertions).

### Key tradeoffs

- **gix API**: No high-level ahead/behind — uses manual revwalk (same cap as Go: 1000 commits).
- **gix stash**: No stash API — reads `logs/refs/stash` directly (same approach as Go).
- **Cumulative stats**: Still delegates to `cumulative-stats.sh` for background aggregation.
- **unsafe**: Uses `libc::setpgid` for background job detachment (same pattern as Go's `syscall.SysProcAttr`).

## Chapter 6: Performance Summary

Measured with [hyperfine](https://github.com/sharkdp/hyperfine) (100+ runs, 10 warmup):

| Engine | Subprocesses | Render (no git) | Render (with git) | Binary size |
|--------|:----------:|:---------:|:---------:|:--------:|
| Bash | 27-35 | ~97ms | ~155ms | — |
| Python | 5-8 | ~400ms | — | — |
| Go | 0 | ~6ms | ~80ms | ~15MB |
| **Rust** | **0** | **~6.5ms** | **~6.5ms** | **~3MB** |

Key insight: gix adds near-zero overhead for git operations. go-git adds ~74ms per render.

## Chapter 7: Benchmark Methodology

We use [hyperfine](https://github.com/sharkdp/hyperfine) for fair comparison:

```bash
make bench              # compare all engines
make bench-bash         # bash only
make bench-python       # python only
make profile            # detailed subprocess timing
```

- **Warmup**: 5 runs (prime filesystem caches)
- **Min runs**: 50 (statistical significance)
- **Fixture**: Same JSON input for all engines
- **Git**: Real repo (actual git subprocess costs)
- **Output**: JSON + Markdown results

## Chapter 8: Lessons Learned

1. **Bash is great for orchestration, terrible for data processing.** If you're calling jq more than 3 times, consider a different language.

2. **Python's stdlib is remarkably complete.** json, subprocess, os, hashlib — that's all we needed. Zero pip dependencies.

3. **Output parity is non-negotiable.** Every engine must produce identical output. The engine-agnostic test suite ensures this.

4. **The installer should be invisible.** Users run `make install` and get the best available engine. They never need to know which one is running.

5. **Profile before optimizing.** `make profile` revealed that subprocess overhead dominates — not the actual jq/bc/git computation.
