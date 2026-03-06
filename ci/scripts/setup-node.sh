#!/usr/bin/env bash
set -euo pipefail
# Install Node.js on self-hosted runners using NodeSource
# Usage: NODE_VERSION=20 ./setup-node.sh

NODE_VERSION=${NODE_VERSION:-20}

echo "Installing Node.js ${NODE_VERSION}..."
if command -v node >/dev/null 2>&1; then
  echo "node already installed: $(node --version)"
  exit 0
fi

curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
apt-get update
apt-get install -y nodejs

echo "node version: $(node --version)"
echo "npm version: $(npm --version)"
