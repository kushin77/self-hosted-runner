#!/usr/bin/env bash
# Skeleton script to sync a secret from HashiCorp Vault to Google Secret Manager (GSM).
# Requires: `vault` CLI authenticated, `gcloud` CLI authenticated with project set.

set -euo pipefail

VAULT_PATH="secret/data/nexus/app"
GSM_SECRET_ID="nexus-app-secret"
PROJECT_ID="$(gcloud config get-value project -q)"

# Read secret from Vault (adjust path and key as needed)
SECRET_JSON=$(vault kv get -format=json "$VAULT_PATH")
# Extract value using jq (example key: data.data.password)
SECRET_VALUE=$(echo "$SECRET_JSON" | jq -r '.data.data.value')

if [[ -z "$SECRET_VALUE" || "$SECRET_VALUE" == "null" ]]; then
  echo "No secret value found at $VAULT_PATH"
  exit 1
fi

# Create the secret if missing
if ! gcloud secrets describe "$GSM_SECRET_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud secrets create "$GSM_SECRET_ID" --project="$PROJECT_ID" --replication-policy="automatic"
fi

# Add a new secret version
printf "%s" "$SECRET_VALUE" | gcloud secrets versions add "$GSM_SECRET_ID" --project="$PROJECT_ID" --data-file=-

echo "Secret synced to GSM: $GSM_SECRET_ID"
