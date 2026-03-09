#!/bin/bash
# Fetch secrets from HashiCorp Vault using OIDC authentication
# Usage: fetch-vault-secrets.sh <vault-path> <field> [--plain]

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.example.com}"
VAULT_PATH="${1:-}"
FIELD_NAME="${2:-}"

if [[ -z "$VAULT_PATH" ]]; then
    echo "Usage: $0 <vault-path> [field-name]"
    exit 1
fi

# Authenticate using OIDC token from GitHub
OIDC_TOKEN="${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}"
if [[ -z "$OIDC_TOKEN" ]]; then
    echo "Error: OIDC token not available"
    exit 1
fi

# Exchange OIDC token for Vault token
VAULT_TOKEN=$(curl -s -X POST \
    "$VAULT_ADDR/v1/auth/oidc/login" \
    -H "Content-Type: application/json" \
    -d "{\"role\":\"github-actions\",\"jwt\":\"$OIDC_TOKEN\"}" \
    | jq -r '.auth.client_token')

if [[ -z "$VAULT_TOKEN" ]]; then
    echo "Error: Failed to authenticate with Vault"
    exit 1
fi

# Fetch secret from Vault
curl -s -X GET \
    "$VAULT_ADDR/v1/$VAULT_PATH" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    | jq -r ".data.data.${FIELD_NAME:-.}"

