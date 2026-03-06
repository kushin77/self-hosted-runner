#!/usr/bin/env bash
set -euo pipefail

# setup-helm.sh
# Installs Helm CLI on the runner.

HELM_VERSION="${1:-3.12.0}"

if command -v helm >/dev/null 2>&1; then
  echo "helm already installed: $(helm version --short)"
  exit 0
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH=amd64
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH=arm64
fi

TARBALL="helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz"
URL="https://get.helm.sh/${TARBALL}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
if command -v sudo >/dev/null 2>&1; then
  sudo mv "$TMPDIR/linux-${ARCH}/helm" /usr/local/bin/helm
else
  mkdir -p "$HOME/.local/bin"
  mv "$TMPDIR/linux-${ARCH}/helm" "$HOME/.local/bin/helm"
  chmod +x "$HOME/.local/bin/helm"
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" || true
fi

echo "helm installed: $(helm version --short)"
