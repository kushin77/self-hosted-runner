#!/usr/bin/env bash
set -euo pipefail
# Ensure Docker Buildx is available on runner

if docker buildx version >/dev/null 2>&1; then
  echo "buildx already available"
  exit 0
fi

echo "Setting up Docker Buildx..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/buildx/releases/download/v0.11.0/buildx-v0.11.0.linux-amd64" -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

echo "buildx installed: $(/usr/local/lib/docker/cli-plugins/docker-buildx --version || true)"
