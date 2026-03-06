#!/usr/bin/env bash
set -euo pipefail
# Exchange AppRole RoleID/SecretID for a Vault token
# Usage: ROLE_ID=... SECRET_ID=... VAULT_ADDR=... ./ci/scripts/get-vault-token-approle.sh

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "VAULT_ADDR must be set" >&2
  exit 2
fi

if [ -z "${ROLE_ID:-}" ] || [ -z "${SECRET_ID:-}" ]; then
  echo "ROLE_ID and SECRET_ID must be set" >&2
  exit 2
fi

RESP=$(curl -sS --fail -X POST -d '{"role_id":"'"${ROLE_ID}"'","secret_id":"'"${SECRET_ID}"'"}' "${VAULT_ADDR}/v1/auth/approle/login")
TOKEN=$(echo "$RESP" | jq -r '.auth.client_token')
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Failed to obtain token from Vault" >&2
  echo "$RESP" >&2
  exit 3
fi

echo "$TOKEN"
