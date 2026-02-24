---
name: statusline
description: Manage Claude Code status line — install, configure sections, diagnose issues, and customize display. Use when asked to "install statusline", "configure status line", "fix statusline", "hide sections", "show only cost", "statusline not working", "diagnose statusline", or any status line management task.
metadata:
  user-invocable: true
---

# Claude Code Status Line Manager

Lightweight, zero-dep status bar for Claude Code (pure bash, jq/bc/git only).

## Quick Reference

| File | Purpose |
|------|---------|
| `~/.claude/statusline.sh` | Main renderer |
| `~/.claude/cumulative-stats.sh` | Background cost aggregator |
| `~/.claude/statusline.env` | Section config (all defaults to enabled) |
| `~/.claude/settings.json` | Claude Code config (statusLine key) |
| `~/.cache/claude-code-statusline/` | Token & cost caches |

## Install / Update

If the tool is already cloned:

```bash
cd <path-to-clone>/claude-code-statusline
git pull
make install
```

If not cloned yet:

```bash
brew install jq   # bc and git are pre-installed on macOS
git clone https://github.com/ridjex/claude-code-statusline.git
cd claude-code-statusline
make install
```

The installer is idempotent — safe to run repeatedly. It:
- Copies scripts to `~/.claude/`
- Creates `~/.claude/statusline.env` with defaults (preserves existing)
- Writes proper JSON object to `~/.claude/settings.json`
- Auto-fixes old string-based config from `claude config set`

## Uninstall

```bash
make uninstall
```

Removes scripts, caches, statusline.env, and the `statusLine` key from settings.json.

## Configure Sections

Edit `~/.claude/statusline.env`. Set any value to `false` to hide that section:

```bash
# Line 1
STATUSLINE_SHOW_MODEL=true        # Model name (Opus 4.6)
STATUSLINE_SHOW_MODEL_BARS=true   # Mini bars (█▅▃)
STATUSLINE_SHOW_CONTEXT=true      # Context window bar
STATUSLINE_SHOW_COST=true         # Session cost ($8.4)
STATUSLINE_SHOW_DURATION=true     # Wall clock (15m)
STATUSLINE_SHOW_GIT=true          # Branch + dirty/ahead/behind
STATUSLINE_SHOW_DIFF=true         # Lines added/removed

# Line 2
STATUSLINE_LINE2=true             # Show Line 2 at all
STATUSLINE_SHOW_TOKENS=true       # Per-model token counts
STATUSLINE_SHOW_SPEED=true        # Output throughput (tok/s)
STATUSLINE_SHOW_CUMULATIVE=true   # Project + all cost (⌂ Σ)
```

Changes take effect on the next Claude Code render cycle (no restart needed).

### Common presets

**Minimal (cost-only):**
```bash
STATUSLINE_SHOW_MODEL=false
STATUSLINE_SHOW_MODEL_BARS=false
STATUSLINE_SHOW_CONTEXT=false
STATUSLINE_SHOW_DURATION=false
STATUSLINE_SHOW_GIT=false
STATUSLINE_SHOW_DIFF=false
STATUSLINE_LINE2=false
```

**No cumulative (reduce clutter):**
```bash
STATUSLINE_SHOW_CUMULATIVE=false
```

**Single line:**
```bash
STATUSLINE_LINE2=false
```

## Diagnose Issues

Run diagnostic check:

```bash
make diagnose
```

This checks:
- Dependencies (jq, bc, git)
- Script files exist and are executable
- `settings.json` has proper JSON object format (not string)
- `statusline.env` presence and disabled sections count
- Live render test with sample JSON

### Common problems

| Problem | Cause | Fix |
|---------|-------|-----|
| Statusline blank | ANSI rendering bug in Claude Code | `export NO_COLOR=1` in shell profile |
| Renders vertically | Narrow terminal + Claude Code bug | Widen to >120 columns |
| Not showing after install | settings.json has string instead of object | `make install` (auto-fixes) |
| Not showing at all | Missing statusLine in settings.json | `make install` |
| Old data / wrong costs | Stale caches | `rm -rf ~/.cache/claude-code-statusline/` |

### Manual fix for settings.json

If `make diagnose` shows `statusLine is a STRING`:

```bash
# The installer fixes this automatically:
make install

# Or manual fix via jq:
jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh","padding":0}' \
  ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

## Add Skill to a Project

To make this skill available in a specific project, create `.claude/skills/statusline/SKILL.md` in that project and copy this file's content. Or symlink:

```bash
mkdir -p .claude/skills/statusline
ln -s ~/.claude/skills/statusline/SKILL.md .claude/skills/statusline/SKILL.md
```

## Architecture

```
stdin JSON ──> statusline.sh ──> 1-2 formatted lines (stdout)
                  │
                  ├── sources ~/.claude/statusline.env (if exists)
                  ├── reads cached model stats (models-{session}.json)
                  ├── reads cached cumulative costs (proj-*.json, all.json)
                  ├── reads git state (branch, dirty, ahead/behind)
                  │
                  └── spawns 2 background jobs (non-blocking):
                        ├── parse transcript → update model cache
                        └── cumulative-stats.sh → update cost caches
```

Performance: ~5ms render (reads JSON caches, no parsing in hot path).
