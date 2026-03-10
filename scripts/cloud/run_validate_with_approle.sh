#!/usr/bin/env bash
# Wrapper to login to Vault using AppRole, run the cloud validation, then clean up.
set -euo pipefail

if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "ERROR: VAULT_ADDR must be set" >&2
  exit 2
fi

# Accept role_id/secret_id via env or files for safer operator usage
ROLE_ID="${VAULT_ROLE_ID:-}"
SECRET_ID="${VAULT_SECRET_ID:-}"

if [[ -z "$ROLE_ID" && -f "/run/secrets/vault/role_id" ]]; then
  ROLE_ID=$(cat /run/secrets/vault/role_id)
fi
if [[ -z "$SECRET_ID" && -f "/run/secrets/vault/secret_id" ]]; then
  SECRET_ID=$(cat /run/secrets/vault/secret_id)
fi

if [[ -z "$ROLE_ID" || -z "$SECRET_ID" ]]; then
  echo "ERROR: VAULT_ROLE_ID and VAULT_SECRET_ID must be provided via env or files" >&2
  exit 3
fi

# Login using AppRole and capture token
LOGIN_JSON=$(vault write -format=json auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
VAULT_TOKEN=$(echo "$LOGIN_JSON" | awk '/"client_token"/ {print $2}' | tr -d '",')
if [[ -z "$VAULT_TOKEN" ]]; then
  echo "ERROR: failed to obtain Vault token from AppRole login" >&2
  exit 4
fi

export VAULT_TOKEN
export VAULT_TOKEN_FILE="/tmp/vault_token_$$"
# Write token to a temp file for compatibility
printf "%s" "$VAULT_TOKEN" > "$VAULT_TOKEN_FILE"
chmod 600 "$VAULT_TOKEN_FILE"

echo "Logged in to Vault via AppRole; running cloud validation..."

# Run validation script (it will look for VAULT_TOKEN_FILE or VAULT_TOKEN)
./scripts/cloud/validate_gsm_vault_kms.sh
STATUS=$?

# Clean up token
rm -f "$VAULT_TOKEN_FILE"
unset VAULT_TOKEN

if [[ $STATUS -ne 0 ]]; then
  echo "Cloud validation failed with status $STATUS" >&2
  exit $STATUS
fi

echo "Cloud validation completed successfully. Token cleaned up." 
exit 0
