#!/bin/bash
set -euo pipefail

echo "===== ACTIVATING HANDS-OFF AUTOMATION ====="

# Check if we have the critical foundation secret (GCP_SERVICE_ACCOUNT_KEY)
# In this environment, it's available via TF_VAR_SERVICE_ACCOUNT_KEY.
if [ -z "${TF_VAR_SERVICE_ACCOUNT_KEY:-}" ]; then
    echo "❌ Missing TF_VAR_SERVICE_ACCOUNT_KEY. Cannot bridge secrets."
    exit 1
fi

# 1. Update issue 1023 to signal activation
gh issue comment 1023 --repo kushin77/self-hosted-runner --body "🚀 **Activation Protocol Triggered.** Starting automated secret bridging and verification."

# 2. Provision GCP Key to GitHub Actions
echo "Bridging GCP credentials to GitHub..."
echo "$TF_VAR_SERVICE_ACCOUNT_KEY" | gh secret set GCP_SERVICE_ACCOUNT_KEY --repo kushin77/self-hosted-runner

# 3. Trigger the Master Recovery/Sync Workflow
# This workflow is designed to sync secrets across GCP -> AWS -> GitHub -> Local
echo "Triggering master secrets reconciliation (GCP -> Multi-Cloud)..."
gh workflow run deploy-immutable-ephemeral.yml --repo kushin77/self-hosted-runner

# 4. Success marker
echo "✅ Hands-off activation complete. System is now reconciling secrets."
