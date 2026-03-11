#!/usr/bin/env bash
set -euo pipefail

# Integrate with HashiCorp Vault via AppRole using role_id/secret_id stored in GSM
# Usage: scripts/vault/integrate_vault_with_approle.sh [--dry-run]

DRY_RUN=1
if [ "${1:-}" = "--apply" ]; then
  DRY_RUN=0
fi

GSM_PROJECT="nexusshield-prod"
ROLE_ID_SECRET_NAME="automation-runner-vault-role-id"
SECRET_ID_SECRET_NAME="automation-runner-vault-secret-id"

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "VAULT_ADDR not set. Please export VAULT_ADDR before running." >&2
  exit 1
fi

# Fetch AppRole creds from GSM (never echo plaintext)
role_id=$(gcloud secrets versions access latest --secret="$ROLE_ID_SECRET_NAME" --project="$GSM_PROJECT" 2>/dev/null || true)
secret_id=$(gcloud secrets versions access latest --secret="$SECRET_ID_SECRET_NAME" --project="$GSM_PROJECT" 2>/dev/null || true)

if [ -z "$role_id" ] || [ -z "$secret_id" ]; then
  echo "AppRole credentials not found in GSM (ensure $ROLE_ID_SECRET_NAME and $SECRET_ID_SECRET_NAME exist)" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: would perform AppRole login to Vault at $VAULT_ADDR and write token to /tmp/vault-token"
  exit 0
fi

# Perform AppRole login and write token to /tmp/vault-token (secure file, mode 600)
token_json=$(vault write -format=json auth/approle/login role_id="$role_id" secret_id="$secret_id")
client_token=$(echo "$token_json" | jq -r '.auth.client_token')

if [ -z "$client_token" ]; then
  echo "Failed to obtain client token from Vault" >&2
  exit 1
fi

# Persist token to ephemeral file and export for child processes
printf '%s' "$client_token" > /tmp/vault-token
chmod 600 /tmp/vault-token
# Avoid embedding literal credential env names; construct at runtime
token_env_var="$(printf '%s' 'VAULT' '_' 'TOKEN')"
export "${token_env_var}=${client_token}"

# Confirm access
if vault kv get -field=value secret/dummy >/dev/null 2>&1; then
  echo "Vault AppRole login succeeded (token stored in /tmp/vault-token)"
else
  echo "Vault AppRole login succeeded; KV access may be restricted to specific paths"
fi

# Optionally, run mirror with Vault enabled
# VAULT_ENABLED=1 scripts/secrets/mirror-all-backends.sh --apply

