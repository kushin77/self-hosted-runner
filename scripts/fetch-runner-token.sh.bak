#!/usr/bin/env bash
set -euo pipefail
# fetch-runner-token.sh
# Returns a runner registration token via environment, Vault, or vault CLI.

if [ -n "${RUNNER_TOKEN:-}" ]; then
  echo "$RUNNER_TOKEN"
  exit 0
fi

# Try vault CLI if available
if command -v vault >/dev/null 2>&1 && [ -n "${VAULT_SECRET_PATH:-}" ]; then
  # Try KV v2 and fall back
  vault kv get -format=json "${VAULT_SECRET_PATH}" 2>/dev/null \
    | jq -r '.data.data.token // .data.token' 2>/dev/null && exit 0 || true
fi

# Try HTTP API if VAULT_* vars are present
if [ -n "${VAULT_ADDR:-}" ] && [ -n "${VAULT_TOKEN:-}" ] && [ -n "${VAULT_SECRET_PATH:-}" ]; then
  curl -fsSL --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$VAULT_SECRET_PATH" \
    | jq -r '.data.data.token // .data.token' 2>/dev/null && exit 0 || true
fi

echo ""
exit 0
