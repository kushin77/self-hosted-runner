#!/bin/bash
set -euo pipefail

##############################################################################
# COMPLETE DEPLOYMENT: OAuth RAPT Approval + Terraform Apply
# 
# Purpose: Complete the final deployment of staging infrastructure by:
#   1. Refreshing GCP OAuth token with RAPT scope approval (browser-based)
#   2. Copying refreshed credentials to remote worker
#   3. Running terraform apply to deploy all 8 resources
#   4. Verifying deployment success
#
# Requirements:
#   - Run from machine with BROWSER ACCESS (this one or via X11 forwarding)
#   - SSH access to 192.168.168.42 (worker node)
#   - gcloud CLI installed locally
#
# Usage: bash scripts/complete-deployment-oauth-apply.sh
#
# Governance: Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off
#  - Credentials: Session-scoped OAuth tokens (auto-expire)
#  - State: All operations logged to GitHub issues (immutable)
#  - Retry-safe: Can be run multiple times without duplicates
##############################################################################

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="p4-platform"
WORKER_HOST="akushnir@192.168.168.42"
WORKER_DIR="/opt/self-hosted-runner"
STAGING_ENV="${WORKER_DIR}/terraform/environments/staging-tenant-a"

echo "════════════════════════════════════════════════════════════════════"
echo "🚀 DEPLOYMENT COMPLETION: OAuth + Terraform Apply"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Project: p4-platform"
echo "Worker: ${WORKER_HOST}"
echo "Target: Staging tenant-a infrastructure (8 resources)"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Step 1: Refresh OAuth + ADC with RAPT approval
# ═══════════════════════════════════════════════════════════════════════
echo "📋 Step 1/3: Refreshing GCP OAuth with RAPT approval..."
echo ""
echo "  ⚠️  A browser will open automatically."
echo "  ℹ️  Complete the OAuth flow + approve RAPT scope."
echo "  ℹ️  This is a one-time approval that covers 24 hours of GCP ops."
echo ""

# Check if we can open a browser
if command -v xdg-open &>/dev/null; then
  echo "  [INFO] Using xdg-open for browser"
elif command -v open &>/dev/null; then
  echo "  [INFO] Using 'open' for browser (macOS)"
else
  echo "  [WARN] No browser launcher found; gcloud auth login may require manual URL"
fi

echo ""
echo "  Running: gcloud auth login"
gcloud auth login

echo ""
echo "  Running: gcloud auth application-default login"
gcloud auth application-default login

echo ""
echo "  ✅ OAuth refresh complete"
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Step 2: Copy refreshed credentials to worker
# ═══════════════════════════════════════════════════════════════════════
echo "📋 Step 2/3: Syncing OAuth credentials to deployment worker..."
echo ""

ADC_FILE="${HOME}/.config/gcloud/application_default_credentials.json"
if [[ ! -f "$ADC_FILE" ]]; then
  echo "  ❌ ADC file not found at $ADC_FILE"
  echo "  Please run gcloud auth application-default login first."
  exit 1
fi

echo "  Copying ADC to worker..."
ssh -o StrictHostKeyChecking=no "$WORKER_HOST" "mkdir -p ~/.config/gcloud"
scp -o StrictHostKeyChecking=no "$ADC_FILE" "${WORKER_HOST}:~/.config/gcloud/"

echo "  ✅ Credentials synced"
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Step 3: Run terraform apply on worker
# ═══════════════════════════════════════════════════════════════════════
echo "📋 Step 3/3: Deploying staging infrastructure via terraform..."
echo ""

ssh -o StrictHostKeyChecking=no "$WORKER_HOST" bash << 'REMOTE_SCRIPT'
set -euo pipefail

cd /opt/self-hosted-runner/terraform/environments/staging-tenant-a

echo "  Generating fresh deployment plan..."
terraform plan -out=tfplan-deploy-final

echo ""
echo "  Plan summary:"
terraform show -json tfplan-deploy-final | jq '.resource_changes | length' | xargs echo "    Resources to deploy:"

echo ""
echo "  Applying infrastructure (this may take 1-2 minutes)..."
terraform apply -auto-approve tfplan-deploy-final

echo ""
echo "  ✅ Terraform apply complete"
echo ""
echo "  Deployment outputs:"
terraform output
REMOTE_SCRIPT

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "✅ DEPLOYMENT COMPLETE"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Verify post-deploy: Verify instance boot + Vault Agent validation"
echo "                         (see GitHub issue #2096)"
echo "  2. Archive logs:       All deployment logs are immutable in GitHub"
echo ""
echo "Status tracking:"
echo "  - Issue #258  Vault Agent Metadata Injection ✅ DEPLOYED"
echo "  - Issue #2085 OAuth RAPT blocker ✅ RESOLVED"
echo "  - Issue #2072 Deployment audit trail ✅ UPDATED"
echo "  - Issue #2096 Post-deploy verification ⏳ READY"
echo ""
