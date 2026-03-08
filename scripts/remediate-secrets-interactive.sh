#!/bin/bash
# Automated Secrets Remediation Script
# Purpose: Guide operator through replacing placeholder secrets with real values
# Usage: bash scripts/remediate-secrets-interactive.sh

set -e

REPO="kushin77/self-hosted-runner"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔧 Multi-Layer Secrets Remediation Tool"
echo "=========================================="
echo ""
echo "This script will help you replace placeholder secrets with real values."
echo "You'll be prompted for each value interactively."
echo ""

# Helper function to prompt for input
prompt_for_value() {
  local var_name="$1"
  local description="$2"
  local current_value="$3"
  local value=""
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 $var_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Description: $description"
  if [[ -n "$current_value" ]]; then
    echo "Current: $current_value (placeholder)"
  fi
  echo ""
  read -p "Enter real value for $var_name: " value
  
  if [[ -z "$value" ]]; then
    echo "❌ Value cannot be empty. Aborting."
    exit 1
  fi
  
  echo "$value"
}

# Step 1: Collect values
echo ""
echo "Step 1/3: Collecting real secret values..."
echo ""

GCP_PROJECT_ID=$(prompt_for_value "GCP_PROJECT_ID" \
  "Your GCP project ID (e.g., 'my-project-123')" \
  "placeholder-GCP_PROJECT_ID")

GCP_WORKLOAD_IDENTITY_PROVIDER=$(prompt_for_value "GCP_WORKLOAD_IDENTITY_PROVIDER" \
  "GCP Workload Identity Provider resource name (e.g., 'projects/123.../workloadIdentityPools/...')" \
  "placeholder-WIF_PROVIDER")

VAULT_ADDR=$(prompt_for_value "VAULT_ADDR" \
  "Vault address (e.g., 'https://vault.internal.example.com:8200')" \
  "https://placeholder-vault.example")

AWS_KMS_KEY_ID=$(prompt_for_value "AWS_KMS_KEY_ID" \
  "AWS KMS Key ARN (e.g., 'arn:aws:kms:us-east-1:...:key/...')" \
  "alias/placeholder-kms-key")

# Step 2: Confirm before applying
echo ""
echo "Step 2/3: Review values before applying..."
echo ""
echo "Summary of values to be set:"
echo "  GCP_PROJECT_ID: ${GCP_PROJECT_ID:0:50}..."
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: ${GCP_WORKLOAD_IDENTITY_PROVIDER:0:50}..."
echo "  VAULT_ADDR: ${VAULT_ADDR:0:50}..."
echo "  AWS_KMS_KEY_ID: ${AWS_KMS_KEY_ID:0:50}..."
echo ""
read -p "Proceed with setting these secrets? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "❌ Cancelled. No secrets were updated."
  exit 0
fi

# Step 3: Apply secrets
echo ""
echo "Step 3/3: Applying secrets to repository..."
echo ""

echo "Setting GCP_PROJECT_ID..."
gh secret set GCP_PROJECT_ID -R "$REPO" -b "$GCP_PROJECT_ID" && echo "  ✅ Set"

echo "Setting GCP_WORKLOAD_IDENTITY_PROVIDER..."
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER -R "$REPO" -b "$GCP_WORKLOAD_IDENTITY_PROVIDER" && echo "  ✅ Set"

echo "Setting VAULT_ADDR..."
gh secret set VAULT_ADDR -R "$REPO" -b "$VAULT_ADDR" && echo "  ✅ Set"

echo "Setting AWS_KMS_KEY_ID..."
gh secret set AWS_KMS_KEY_ID -R "$REPO" -b "$AWS_KMS_KEY_ID" && echo "  ✅ Set"

echo ""
echo "=========================================="
echo "✅ All secrets updated successfully!"
echo "=========================================="
echo ""
echo "Next: Trigger the health-check workflow..."
echo ""

read -p "Trigger secrets-health-multi-layer.yml now? (yes/no): " trigger

if [[ "$trigger" == "yes" ]]; then
  echo "Triggering workflow..."
  gh workflow run secrets-health-multi-layer.yml --repo "$REPO" --ref main
  
  echo ""
  echo "✅ Workflow triggered!"
  echo ""
  echo "Monitor the run at:"
  echo "  https://github.com/$REPO/actions/workflows/secrets-health-multi-layer.yml"
  echo ""
  echo "Next steps:"
  echo "  1. Wait for the workflow to complete (usually 1-2 minutes)"
  echo "  2. Check the health-check results"
  echo "  3. Reply to issue #1691 with confirmation"
  echo ""
else
  echo ""
  echo "You can manually trigger the workflow later with:"
  echo "  gh workflow run secrets-health-multi-layer.yml --repo $REPO --ref main"
  echo ""
fi

echo "✅ Manual remediation phase complete!"
