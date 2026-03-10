#!/usr/bin/env bash
set -euo pipefail

# Sync specified secrets from Google Secret Manager into Vault KV v2
# Usage: ./scripts/vault/sync_gsm_to_vault.sh <gsm-secret-name> <vault-path>

GSM_NAME=${1:-}
VAULT_PATH=${2:-}

if [ -z "$GSM_NAME" ] || [ -z "$VAULT_PATH" ]; then
  echo "Usage: $0 <gsm-secret-name> <vault-path>"
  exit 2
fi

# Requires: gcloud authenticated and `vault` CLI configured (VAULT_ADDR, VAULT_TOKEN or auth method)
SECRET=$(gcloud secrets versions access latest --secret="$GSM_NAME" --format='get(payload.data)' | tr '_-' '/+' | base64 -d)

# Write into Vault KV v2
vault kv put "$VAULT_PATH" value="$(printf '%s' "$SECRET" | base64 -w0)"

echo "Synced GSM secret $GSM_NAME -> Vault $VAULT_PATH"
