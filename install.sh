#!/bin/bash
# Claude Code Status Line — Installer
# Idempotent: safe to run on fresh install, upgrade, or to fix broken config.

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

# Backup and copy scripts (upgrade-safe)
for f in statusline.sh cumulative-stats.sh; do
  if [ -f "$DEST_DIR/$f" ]; then
    cp "$DEST_DIR/$f" "$DEST_DIR/$f.bak"
  fi
done

cp "$SCRIPT_DIR/src/statusline.sh" "$DEST_DIR/statusline.sh"
cp "$SCRIPT_DIR/src/cumulative-stats.sh" "$DEST_DIR/cumulative-stats.sh"
chmod +x "$DEST_DIR/statusline.sh" "$DEST_DIR/cumulative-stats.sh"
echo "[ok] Scripts installed"

# Copy default config (only if user doesn't have one)
SL_ENV="$DEST_DIR/statusline.env"
if [ ! -f "$SL_ENV" ]; then
  cp "$SCRIPT_DIR/src/statusline.env.default" "$SL_ENV"
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
