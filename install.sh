#!/bin/bash
# Claude Code Status Line — Installer
# Idempotent: safe to run on fresh install, upgrade, or to fix broken config.
# Auto-detects the best available engine (go > python > bash).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${HOME}/.claude"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline"
SETTINGS="$DEST_DIR/settings.json"
SL_CONFIG='{"type":"command","command":"~/.claude/statusline.sh","padding":0}'

echo "Claude Code Status Line — Installer"
echo ""

# Check dependencies
missing=()
for dep in jq bc git; do
  command -v "$dep" &>/dev/null || missing+=("$dep")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing dependencies: ${missing[*]}"
  echo "  macOS:  brew install ${missing[*]}"
  echo "  Ubuntu: sudo apt install ${missing[*]}"
  exit 1
fi
echo "[ok] Dependencies: jq, bc, git"

# Create directories
mkdir -p "$DEST_DIR" "$CACHE_DIR"
echo "[ok] Directories ready"

# --- Engine detection ---
detect_engine() {
  # Future: check for compiled binaries first
  # if [ -f "$SCRIPT_DIR/engines/rust/target/release/statusline" ]; then
  #   echo "rust"; return
  # fi
  if [ -f "$SCRIPT_DIR/engines/go/statusline" ]; then
    echo "go"; return
  fi
  if [ -f "$SCRIPT_DIR/engines/python/statusline.py" ] && command -v python3 &>/dev/null; then
    echo "python"; return
  fi
  echo "bash"
}

ENGINE=$(detect_engine)
echo "[ok] Selected engine: $ENGINE"

# Backup existing scripts (upgrade-safe)
for f in statusline.sh statusline.py cumulative-stats.sh; do
  if [ -f "$DEST_DIR/$f" ]; then
    cp "$DEST_DIR/$f" "$DEST_DIR/$f.bak"
  fi
done

# --- Install engine ---
case "$ENGINE" in
  go)
    cp "$SCRIPT_DIR/engines/go/statusline" "$DEST_DIR/statusline-go"
    chmod +x "$DEST_DIR/statusline-go"
    # Wrapper so settings.json command stays the same (~/.claude/statusline.sh)
    cat > "$DEST_DIR/statusline.sh" <<'WRAPPER'
#!/bin/bash
exec ~/.claude/statusline-go "$@"
WRAPPER
    chmod +x "$DEST_DIR/statusline.sh"
    # cumulative-stats.sh still needed (called by go engine for background jobs)
    cp "$SCRIPT_DIR/engines/bash/cumulative-stats.sh" "$DEST_DIR/cumulative-stats.sh"
    chmod +x "$DEST_DIR/cumulative-stats.sh"
    echo "[ok] Go engine installed (with bash wrapper)"
    ;;
  python)
    cp "$SCRIPT_DIR/engines/python/statusline.py" "$DEST_DIR/statusline.py"
    chmod +x "$DEST_DIR/statusline.py"
    # Wrapper so settings.json command stays the same (~/.claude/statusline.sh)
    cat > "$DEST_DIR/statusline.sh" <<'WRAPPER'
#!/bin/bash
exec python3 ~/.claude/statusline.py "$@"
WRAPPER
    chmod +x "$DEST_DIR/statusline.sh"
    # cumulative-stats.sh still needed (called by python engine for background jobs)
    cp "$SCRIPT_DIR/engines/bash/cumulative-stats.sh" "$DEST_DIR/cumulative-stats.sh"
    chmod +x "$DEST_DIR/cumulative-stats.sh"
    echo "[ok] Python engine installed (with bash wrapper)"
    ;;
  bash)
    cp "$SCRIPT_DIR/engines/bash/statusline.sh" "$DEST_DIR/statusline.sh"
    cp "$SCRIPT_DIR/engines/bash/cumulative-stats.sh" "$DEST_DIR/cumulative-stats.sh"
    chmod +x "$DEST_DIR/statusline.sh" "$DEST_DIR/cumulative-stats.sh"
    echo "[ok] Bash engine installed"
    ;;
esac

# Copy default config (only if user doesn't have one)
SL_ENV="$DEST_DIR/statusline.env"
if [ ! -f "$SL_ENV" ]; then
  cp "$SCRIPT_DIR/engines/bash/statusline.env.default" "$SL_ENV"
  echo "[ok] Created $SL_ENV (edit to customize sections)"
else
  echo "[ok] Existing $SL_ENV preserved"
fi

# Configure settings.json (handles all scenarios)
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"

  # Detect old string-based config from previous versions
  # e.g. "statusLine": "~/.claude/statusline.sh" instead of proper object
  OLD_TYPE=$(jq -r '.statusLine | type' "$SETTINGS" 2>/dev/null || echo "null")

  if [ "$OLD_TYPE" = "string" ]; then
    jq --argjson sl "$SL_CONFIG" '.statusLine = $sl' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "[ok] Fixed statusLine config (was string, now proper object)"
  elif [ "$OLD_TYPE" = "object" ]; then
    # Already an object — update to latest config
    CURRENT=$(jq -c '.statusLine' "$SETTINGS" 2>/dev/null)
    if [ "$CURRENT" = "$SL_CONFIG" ]; then
      echo "[ok] settings.json already up to date"
    else
      jq --argjson sl "$SL_CONFIG" '.statusLine = $sl' \
        "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
      echo "[ok] Updated statusLine config"
    fi
  else
    # No statusLine key yet — add it
    jq --argjson sl "$SL_CONFIG" '.statusLine = $sl' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "[ok] Added statusLine to settings.json"
  fi
else
  printf '{\"statusLine\":%s}\n' "$SL_CONFIG" | jq . > "$SETTINGS"
  echo "[ok] Created $SETTINGS"
fi

# Install Claude Code skill (for /statusline command)
SKILL_DIR="$DEST_DIR/skills/statusline"
if [ -f "$SCRIPT_DIR/skill/SKILL.md" ]; then
  mkdir -p "$SKILL_DIR"
  cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
  echo "[ok] Skill installed (/statusline command available)"
fi

echo ""
echo "Next steps:"
echo "  1. make verify    # smoke test (run in any git repo)"
echo "  2. Open a new Claude Code session"
