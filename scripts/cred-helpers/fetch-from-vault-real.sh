#!/usr/bin/env bash
set -euo pipefail

# Fetch secret from HashiCorp Vault using JWT auth (OIDC)
# Usage: fetch-from-vault-real.sh <CREDENTIAL_NAME>

CREDENTIAL_NAME="${1:-}"
VAULT_ADDR="${VAULT_ADDR:-}"

log_info(){ echo "[INFO] $1" >&2; }
log_fail(){ echo "[FAIL] $1" >&2; }

if [ -z "$CREDENTIAL_NAME" ]; then
  log_fail "Usage: $0 CREDENTIAL_NAME"
  exit 2
fi

if [ -z "$VAULT_ADDR" ]; then
  log_fail "VAULT_ADDR not set, skipping Vault retrieval"
  exit 1
fi

log_info "Attempting Vault retrieval for $CREDENTIAL_NAME..."

JWT_TOKEN=""
if [[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
  RESP=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}?audience=$VAULT_ADDR" -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" 2>/dev/null || true)
  JWT_TOKEN=$(echo "$RESP" | jq -r '.token // empty' 2>/dev/null || echo "")
fi

if [ -z "$JWT_TOKEN" ]; then
  log_fail "JWT token not available for Vault auth"
  exit 1
fi

AUTH_RESP=$(curl -sS "$VAULT_ADDR/v1/auth/jwt/login" -X POST -H "Content-Type: application/json" -d "{\"jwt\":\"$JWT_TOKEN\"}" 2>/dev/null || echo "")
VAULT_TOKEN=$(echo "$AUTH_RESP" | jq -r '.auth.client_token // empty' 2>/dev/null || echo "")

if [ -z "$VAULT_TOKEN" ]; then
  log_fail "Vault authentication failed"
  exit 1
fi

CRED_VALUE=""
for attempt in 1 2 3; do
  SECRET_RESP=$(curl -sS "$VAULT_ADDR/v1/secret/data/credentials/$CREDENTIAL_NAME" -H "X-Vault-Token: $VAULT_TOKEN" 2>/dev/null || echo "")
  CRED_VALUE=$(echo "$SECRET_RESP" | jq -r '.data.data.value // empty' 2>/dev/null || echo "")
  if [ -n "$CRED_VALUE" ]; then
    log_info "Vault retrieval successful"
    # revoke token
    curl -sS "$VAULT_ADDR/v1/auth/token/revoke-self" -X POST -H "X-Vault-Token: $VAULT_TOKEN" >/dev/null 2>&1 || true
    echo "$CRED_VALUE"
    exit 0
  fi
  if [ $attempt -lt 3 ]; then sleep $((attempt * 2)); fi
done

log_fail "Vault retrieval failed"
exit 1
