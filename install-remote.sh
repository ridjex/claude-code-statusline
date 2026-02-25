#!/bin/bash
# Claude Code Status Line — Remote Installer
# Downloads pre-built binaries from GitHub Releases and runs install.sh.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ridjex/claude-code-statusline/main/install-remote.sh | bash
#   curl -fsSL ... | bash -s -- v2.0.0    # specific version

set -euo pipefail

REPO="ridjex/claude-code-statusline"
VERSION="${1:-latest}"
TMPDIR_BASE="${TMPDIR:-/tmp}"
WORK_DIR="$TMPDIR_BASE/claude-code-statusline-install-$$"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

mkdir -p "$WORK_DIR"

# Detect platform
detect_platform() {
  local os arch
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  case "$os" in
    darwin) os="darwin" ;;
    linux)  os="linux" ;;
    *)
      echo "Unsupported OS: $os"
      exit 1
      ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $arch"
      exit 1
      ;;
  esac

  echo "${os}-${arch}"
}

PLATFORM=$(detect_platform)
echo "Claude Code Status Line — Remote Installer"
echo "Platform: $PLATFORM"

# Resolve version
if [ "$VERSION" = "latest" ]; then
  echo "Fetching latest release..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  if [ -z "$VERSION" ]; then
    echo "Failed to fetch latest release version"
    exit 1
  fi
fi
echo "Version: $VERSION"

# Download tarball
TARBALL="claude-code-statusline-${VERSION}-${PLATFORM}.tar.gz"
URL="https://github.com/$REPO/releases/download/${VERSION}/${TARBALL}"
CHECKSUM_URL="https://github.com/$REPO/releases/download/${VERSION}/checksums.txt"

echo "Downloading $TARBALL..."
curl -fSL -o "$WORK_DIR/$TARBALL" "$URL"

# Verify checksum
echo "Verifying checksum..."
if ! curl -fsSL -o "$WORK_DIR/checksums.txt" "$CHECKSUM_URL"; then
  echo "Failed to download checksums.txt — check that release $VERSION exists"
  exit 1
fi

cd "$WORK_DIR"
if ! grep -q "$TARBALL" checksums.txt; then
  echo "Checksum entry not found for $TARBALL in checksums.txt"
  exit 1
fi

if command -v sha256sum &>/dev/null; then
  grep "$TARBALL" checksums.txt | sha256sum -c - || {
    echo "Checksum verification FAILED — the download may be corrupted, try again"
    exit 1
  }
elif command -v shasum &>/dev/null; then
  EXPECTED=$(grep "$TARBALL" checksums.txt | awk '{print $1}')
  ACTUAL=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Checksum verification FAILED — the download may be corrupted, try again"
    echo "  Expected: $EXPECTED"
    echo "  Actual:   $ACTUAL"
    exit 1
  fi
  echo "$TARBALL: OK"
else
  echo "Warning: no sha256sum or shasum available, skipping checksum verification"
fi

# Extract and install
echo "Extracting..."
tar xzf "$TARBALL"

EXTRACT_DIR="claude-code-statusline-${VERSION}-${PLATFORM}"
cd "$EXTRACT_DIR"

echo "Running installer..."
bash install.sh

echo ""
echo "Installed claude-code-statusline $VERSION ($PLATFORM)"
