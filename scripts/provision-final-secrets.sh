#!/bin/bash
set -euo pipefail

echo "Starting Final Secret Provisioning & Activation..."

# Validate GCP Key format
if [ -z "${TF_VAR_SERVICE_ACCOUNT_KEY:-}" ]; then
    echo "❌ TF_VAR_SERVICE_ACCOUNT_KEY is missing. Please set it to proceed."
    exit 1
fi

# Set Secrets in GH Repo using gh cli
echo "Provisioning secrets to GitHub repository..."
# Note: We use -b to handle potentially large keys or binary data correctly
# echo "$TF_VAR_SERVICE_ACCOUNT_KEY" | gh secret set GCP_SERVICE_ACCOUNT_KEY -R kushin77/self-hosted-runner

# Check for Vault IDs
if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
    gh secret set VAULT_ROLE_ID -b"$VAULT_ROLE_ID" -R kushin77/self-hosted-runner
    gh secret set VAULT_SECRET_ID -b"$VAULT_SECRET_ID" -R kushin77/self-hosted-runner
    echo "✓ Vault secrets provisioned."
else
    echo "⚠ Vault Role/Secret IDs not found in environment. Awaiting manual input or metadata fetch."
fi

# Trigger the sync and verification workflow
echo "Triggering global secrets recovery/sync..."
gh workflow run deploy-immutable-ephemeral.yml -R kushin77/self-hosted-runner
