#!/bin/bash
# Claude Code Status Line — Installer
# Copies scripts and creates cache directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${HOME}/.claude"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline"

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

# Backup existing files
for f in statusline.sh cumulative-stats.sh; do
  if [ -f "$DEST_DIR/$f" ]; then
    cp "$DEST_DIR/$f" "$DEST_DIR/$f.bak"
    echo "[ok] Backed up $f -> $f.bak"
  fi
done

# Copy scripts
cp "$SCRIPT_DIR/src/statusline.sh" "$DEST_DIR/statusline.sh"
cp "$SCRIPT_DIR/src/cumulative-stats.sh" "$DEST_DIR/cumulative-stats.sh"
chmod +x "$DEST_DIR/statusline.sh" "$DEST_DIR/cumulative-stats.sh"
echo "[ok] Scripts installed"

echo ""
echo "Installed:"
echo "  $DEST_DIR/statusline.sh"
echo "  $DEST_DIR/cumulative-stats.sh"
echo "  $CACHE_DIR/"
echo ""
echo "Activate:"
echo "  claude config set --global statusline \"~/.claude/statusline.sh\""
echo ""
echo "Verify (run in any git repo):"
echo "  echo '{\"model\":{\"display_name\":\"Test\"},\"context_window\":{\"used_percentage\":42,\"total_input_tokens\":100,\"total_output_tokens\":50},\"cost\":{\"total_cost_usd\":1.0,\"total_duration_ms\":60000,\"total_api_duration_ms\":40000},\"workspace\":{}}' | ~/.claude/statusline.sh"
