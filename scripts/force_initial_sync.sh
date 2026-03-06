#!/usr/bin/env bash
set -euo pipefail

# Helper to attempt initial GSM->Vault sync. If remote Vault is unreachable
# this will attempt to start a local dev Vault (docker) and re-run the sync.

SECRET_PROJECT="${SECRET_PROJECT:-gcp-eiq}"
export SECRET_PROJECT

export VAULT_ADDR="http://192.168.168.41:8200"
export VAULT_ROLE_ID="${VAULT_ROLE_ID:-$(gcloud secrets versions access latest --secret=vault-approle-role-id --project=$SECRET_PROJECT || true)}"
export VAULT_SECRET_ID="${VAULT_SECRET_ID:-$(gcloud secrets versions access latest --secret=vault-approle-secret-id --project=$SECRET_PROJECT || true)}"

echo "Running initial GSM→Vault sync (will fallback to local dev Vault if necessary)"
./scripts/gsm_to_vault_sync.sh

echo "Initial sync run complete. Check Vault for secret at 'secret/data/ci/webhooks'"
echo "If a local dev Vault was started, it listens at http://127.0.0.1:8201 with token 'devroot'"
