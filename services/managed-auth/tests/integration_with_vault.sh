#!/usr/bin/env bash
set -euo pipefail

echo "Running managed-auth integration test against Vault"

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
  echo "VAULT_ADDR and VAULT_TOKEN must be set for this integration test" >&2
  exit 2
fi

cwd=$(pwd)
cd "$(dirname "$0")/.."

export SECRETS_BACKEND=vault
export VAULT_ADDR
export VAULT_TOKEN

echo "Using VAULT_ADDR=$VAULT_ADDR"

SIMULATE_OAUTH=1 PORT=$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()
PY
) node index.js &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT

sleep 0.8

echo "Running provision_flow.sh against running managed-auth (vault)"
bash tests/provision_flow.sh
