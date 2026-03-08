#!/bin/bash
# VAULT AppRole Authentication Helper
# Properties: Idempotent, immutable, no-ops (read-only auth)

set -e

VAULT_ADDR="${VAULT_ADDR:-https://vault.example.com}"
APPROLE_MOUNT="${APPROLE_MOUNT:-approle}"
VAULT_ROLE_ID="${VAULT_ROLE_ID:?VAULT_ROLE_ID required}"
VAULT_SECRET_ID="${VAULT_SECRET_ID:?VAULT_SECRET_ID required}"

# Authenticate to VAULT using AppRole
echo "[INFO] Authenticating to VAULT using AppRole..." >&2

TOKEN_RESPONSE=$(curl -s -X POST \
  "${VAULT_ADDR}/v1/auth/${APPROLE_MOUNT}/login" \
  -d "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}")

VAULT_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.auth.client_token')

if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
  echo "[ERROR] Failed to authenticate to VAULT" >&2
  exit 1
fi

# Output token for use in subsequent commands
export VAULT_TOKEN="$VAULT_TOKEN"
echo "$VAULT_TOKEN"

echo "[INFO] VAULT authentication successful (token obtained)" >&2
