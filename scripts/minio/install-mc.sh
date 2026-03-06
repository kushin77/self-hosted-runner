#!/usr/bin/env bash
set -euo pipefail

MC_BIN=${MC_BIN:-/usr/local/bin/mc}
MC_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"

if command -v mc >/dev/null 2>&1; then
  echo "mc already installed at $(command -v mc)"
  exit 0
fi

echo "Installing mc to ${MC_BIN}"
curl -fsSL ${MC_URL} -o /tmp/mc && chmod +x /tmp/mc && sudo mv /tmp/mc ${MC_BIN}
${MC_BIN} --version
