#!/usr/bin/env bash
set -euo pipefail

# setup-kubectl.sh
# Installs kubectl CLI on the runner.

KUBECTL_VERSION="${1:-1.28.0}"

if command -v kubectl >/dev/null 2>&1; then
  echo "kubectl already installed: $(kubectl version --client --short)"
  exit 0
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH=amd64
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH=arm64
fi

URL="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "$TMPDIR/kubectl"
chmod +x "$TMPDIR/kubectl"
if command -v sudo >/dev/null 2>&1; then
  sudo mv "$TMPDIR/kubectl" /usr/local/bin/kubectl
else
  mkdir -p "$HOME/.local/bin"
  mv "$TMPDIR/kubectl" "$HOME/.local/bin/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" || true
fi

echo "kubectl installed: $(kubectl version --client --short)"
