#!/bin/sh
set -euo pipefail

# Load VAULT_TOKEN from file if provided (ephemeral token file recommended)
if [ -n "${VAULT_TOKEN_FILE:-}" ] && [ -f "$VAULT_TOKEN_FILE" ]; then
  export VAULT_TOKEN="$(cat "$VAULT_TOKEN_FILE")"
  echo "VAULT_TOKEN loaded from $VAULT_TOKEN_FILE"
fi

# If Vault binary is available and a config file exists, run Vault Agent in background
VAULT_CFG=${VAULT_AGENT_CONFIG:-/etc/vault/agent-config.hcl}
if command -v vault >/dev/null 2>&1 && [ -f "$VAULT_CFG" ]; then
  echo "Starting Vault Agent with config $VAULT_CFG"
  vault agent -config="$VAULT_CFG" >/app/logs/vault-agent.log 2>&1 &
  AGENT_PID=$!
  echo "Vault Agent pid=$AGENT_PID"
fi

# Run the application (exec to receive signals)
exec node server.js
