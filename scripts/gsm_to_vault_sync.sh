#!/usr/bin/env bash
set -euo pipefail

# Sync selected secrets from Google Secret Manager into Vault (KV v2)
# Designed for unattended runs: reads GSM secrets, authenticates to Vault via AppRole,
# and writes to `secret/data/...` paths using `vault` CLI.
#
# Usage: export SECRET_PROJECT=...; export VAULT_ADDR=...; export VAULT_ROLE_ID=...; export VAULT_SECRET_ID=...; ./scripts/gsm_to_vault_sync.sh

SECRET_PROJECT="${SECRET_PROJECT:-}"
if [ -z "$SECRET_PROJECT" ]; then
  echo "ERROR: SECRET_PROJECT must be set to the GCP project containing secrets"
  exit 1
fi

GSM_SECRETS=( 
  "slack-webhook:secret/data/ci/webhooks:webhook" 
)

die(){ echo "$*" >&2; exit 1; }

if ! command -v gcloud >/dev/null 2>&1; then
  die "gcloud CLI not found"
fi
if ! command -v vault >/dev/null 2>&1; then
  die "vault CLI not found"
fi

echo "Starting GSM→Vault sync (project=$SECRET_PROJECT)"

# Authenticate to Vault via AppRole if role/secret IDs are provided
if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
  echo "Authenticating to Vault via AppRole..."
  token=$(curl -s --fail "$VAULT_ADDR/v1/auth/approle/login" -d "{\"role_id\": \"$VAULT_ROLE_ID\", \"secret_id\": \"$VAULT_SECRET_ID\"}" | jq -r '.auth.client_token') || true
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "AppRole login failed; aborting"
    exit 2
  fi
  export VAULT_TOKEN="$token"
  echo "AppRole auth successful"
else
  echo "VAULT_ROLE_ID/VAULT_SECRET_ID not provided; expecting interactive or pre-authenticated vault CLI"
fi

for entry in "${GSM_SECRETS[@]}"; do
  # Format: gsm-name:vault-path:field
  IFS=":" read -r gsm_name vault_path field <<< "$entry"
  echo "Syncing GSM secret '$gsm_name' -> Vault path '$vault_path' (field='$field')"
  # Fetch from GSM
  secret_value=$(gcloud secrets versions access latest --secret="$gsm_name" --project="$SECRET_PROJECT") || { echo "Failed to read GSM secret $gsm_name"; continue; }
  # Prepare a temp file for vault CLI
  tmpf=$(mktemp)
  jq -n --arg v "$secret_value" '{data: {"'"$field"'": $v}}' > "$tmpf"
  # Use vault kv put for KV v2 if possible; attempt API write as fallback
  if vault kv put --help >/dev/null 2>&1; then
    # vault kv put secret/ci/webhooks webhook="$secret_value"
    echo "Writing to Vault using 'vault kv put'"
    # Convert vault_path like secret/data/ci/webhooks -> secret/ci/webhooks for kv put convenience
    out_path="$vault_path"
    out_path=${out_path#secret/data/}
    vault kv put "secret/$out_path" "$field"="$secret_value" || echo "vault kv put failed for $vault_path"
  else
    echo "Using Vault HTTP API write"
    curl --fail -s -X POST "$VAULT_ADDR/v1/$vault_path" -H "X-Vault-Token: $VAULT_TOKEN" -d @"$tmpf" || echo "HTTP write to Vault failed for $vault_path"
  fi
  rm -f "$tmpf"
done

echo "GSM→Vault sync completed"
