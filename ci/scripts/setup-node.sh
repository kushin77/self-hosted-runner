#!/usr/bin/env bash
set -euo pipefail

# setup-node.sh
# Installs a Node.js binary on the runner. Intended for self-hosted runners where
# actions/setup-node is not available. This script prefers sudo installation to
# /usr/local; it will fall back to a user-local install if sudo is not available.

NODE_VERSION="${1:-${NODE_VERSION:-20}}"

echo "Setting up Node.js $NODE_VERSION"

if command -v node >/dev/null 2>&1; then
  INSTALLED=$(node -v | sed 's/v//')
  INST_MAJOR=${INSTALLED%%.*}
  REQ_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
  if [[ "$INST_MAJOR" == "$REQ_MAJOR" ]]; then
    echo "Node $INSTALLED already installed; skipping"
    exit 0
  fi
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH=x64
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH=arm64
fi

TARBALL="node-v${NODE_VERSION}.linux-${ARCH}.tar.xz"
URL="https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading $URL"
curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"

if command -v sudo >/dev/null 2>&1; then
  echo "Installing to /usr/local (requires sudo)"
  sudo tar -xJf "$TMPDIR/$TARBALL" -C /usr/local --strip-components=1
else
  echo "sudo not available; installing to $HOME/.local"
  mkdir -p "$HOME/.local"
  tar -xJf "$TMPDIR/$TARBALL" -C "$HOME/.local" --strip-components=1
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" || true
fi

echo "Node installation complete: $(node -v)"
