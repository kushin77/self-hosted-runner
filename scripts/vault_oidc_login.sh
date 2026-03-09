#!/usr/bin/env bash
set -euo pipefail

# Example: exchange GitHub Actions OIDC token for Vault token (oidc auth method)
# Usage: run within a GitHub Action step that has `id-token: write` permission.
# Expects VAULT_ADDR and VAULT_ROLE to be set.

VAULT_ADDR=${VAULT_ADDR:-https://vault.example}
VAULT_ROLE=${VAULT_ROLE:-github-actions-role}

# Request OIDC token from Actions runtime
ACTIONS_URL=${ACTIONS_ID_TOKEN_REQUEST_URL}
ACTIONS_TOKEN=${ACTIONS_ID_TOKEN_REQUEST_TOKEN}
AUDIENCE=${AUDIENCE:-vault}

if [ -z "$ACTIONS_URL" ] || [ -z "$ACTIONS_TOKEN" ]; then
  echo "This script expects to run inside GitHub Actions with id-token: write"
  exit 2
fi

JWT=$(curl -sS -H "Authorization: Bearer $ACTIONS_TOKEN" "$ACTIONS_URL?audience=$AUDIENCE")
JWT_VALUE=$(echo "$JWT" | jq -r '.value // .' )

# Exchange at Vault oidc login endpoint
resp=$(curl -sS --request POST --data '{"role":"'"$VAULT_ROLE"'","jwt":"'"$JWT_VALUE"'"}' "$VAULT_ADDR/v1/auth/oidc/login")
client_token=$(echo "$resp" | jq -r '.auth.client_token')

if [ -z "$client_token" ] || [ "$client_token" = "null" ]; then
  echo "Failed to get Vault token: $resp"
  exit 3
fi

echo "VAULT_TOKEN=$client_token"
export VAULT_TOKEN=$client_token

# Example: read a secret
# curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/myapp" | jq '.'
