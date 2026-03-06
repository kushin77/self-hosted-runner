#!/usr/bin/env bash
set -euo pipefail

# setup-buildx.sh
# Ensures Docker Buildx CLI plugin is available on the runner.

if command -v docker >/dev/null 2>&1 && docker buildx version >/dev/null 2>&1; then
  echo "docker buildx already available: $(docker buildx version)"
  exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

KUBE_ARCH=$(uname -m)
if [[ "$KUBE_ARCH" == "x86_64" ]]; then
  PLUGIN_ARCH=amd64
elif [[ "$KUBE_ARCH" == "aarch64" ]]; then
  PLUGIN_ARCH=arm64
else
  PLUGIN_ARCH=amd64
fi

# Determine latest buildx release
RELEASE=$(curl -s https://api.github.com/repos/docker/buildx/releases/latest | jq -r .tag_name)
TARBALL="buildx-${RELEASE}.linux-${PLUGIN_ARCH}.tar.gz"
URL="https://github.com/docker/buildx/releases/download/${RELEASE}/${TARBALL}"

echo "Downloading buildx from $URL"
curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"

if command -v sudo >/dev/null 2>&1; then
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo mv "$TMPDIR/docker-buildx" /usr/local/lib/docker/cli-plugins/docker-buildx
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
else
  mkdir -p "$HOME/.docker/cli-plugins"
  mv "$TMPDIR/docker-buildx" "$HOME/.docker/cli-plugins/docker-buildx"
  chmod +x "$HOME/.docker/cli-plugins/docker-buildx"
  export PATH="$HOME/.docker/cli-plugins:$PATH"
fi

echo "Installed docker buildx: $(docker buildx version)"
