#!/usr/bin/env bash
set -euo pipefail

# setup-kind.sh
# Installs kind (Kubernetes in Docker) on the runner.

KIND_VERSION="${1:-v0.20.0}"

if command -v kind >/dev/null 2>&1; then
  echo "kind already installed: $(kind --version)"
  exit 0
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH=amd64
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH=arm64
fi

URL="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "$TMPDIR/kind"
chmod +x "$TMPDIR/kind"
if command -v sudo >/dev/null 2>&1; then
  sudo mv "$TMPDIR/kind" /usr/local/bin/kind
else
  mkdir -p "$HOME/.local/bin"
  mv "$TMPDIR/kind" "$HOME/.local/bin/kind"
  chmod +x "$HOME/.local/bin/kind"
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" || true
fi

echo "kind installed: $(kind --version)"
