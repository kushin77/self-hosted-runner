#!/bin/bash
# Phase 2 Instant Execution Script
# OIDC/WIF Configuration - Automated Setup
# Usage: bash phase2_execute.sh

set -e

echo "════════════════════════════════════════════════════════════════"
echo "  PHASE 2: OIDC/WIF Infrastructure Configuration"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Define workflow
WORKFLOW="setup-oidc-infrastructure.yml"
REPO="kushin77/self-hosted-runner"
DEFAULT_BRANCH="main"

# Default configuration (can be overridden)
GCP_PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null || echo 'YOUR-GCP-PROJECT-ID')}"
AWS_ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'YOUR-AWS-ACCOUNT-ID')}"
VAULT_ADDR="${3:-https://vault.example.com:8200}"
VAULT_NAMESPACE="${4:-}"

echo "Configuration Detected:"
echo "  GCP Project ID:    $GCP_PROJECT_ID"
echo "  AWS Account ID:    $AWS_ACCOUNT_ID"
echo "  Vault Address:     $VAULT_ADDR"
echo "  Vault Namespace:   ${VAULT_NAMESPACE:-(none)}"
echo ""

# Validate GitHub authentication
echo "✓ Validating GitHub CLI authentication..."
if ! gh auth status &> /dev/null; then
  echo "✗ Not authenticated to GitHub. Run: gh auth login"
  exit 1
fi
echo "✓ GitHub authentication verified"
echo ""

# Verify workflow exists
echo "✓ Checking for workflow: $WORKFLOW"
if [ ! -f ".github/workflows/$WORKFLOW" ]; then
  echo "✗ Workflow file not found: .github/workflows/$WORKFLOW"
  exit 1
fi
echo "✓ Workflow file exists"
echo ""

# Trigger workflow
echo "════════════════════════════════════════════════════════════════"
echo "Triggering Phase 2 Workflow..."
echo "════════════════════════════════════════════════════════════════"
echo ""

# Use GitHub CLI to trigger workflow
# Note: Workflow inputs passed as -f flags
gh workflow run "$WORKFLOW" \
  -f gcp_project_id="$GCP_PROJECT_ID" \
  -f aws_account_id="$AWS_ACCOUNT_ID" \
  -f vault_address="$VAULT_ADDR" \
  -f vault_namespace="$VAULT_NAMESPACE" \
  --ref "$DEFAULT_BRANCH" 2>&1 || {
  echo "✗ Failed to trigger workflow"
  exit 1
}

echo ""
echo "✅ Workflow triggered successfully!"
echo ""

# Monitor execution
echo "Waiting for workflow to appear in run queue..."
sleep 3

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "PHASE 2 EXECUTION STARTED"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📊 Monitor Progress:"
echo "  Dashboard:  https://github.com/$REPO/actions"
echo "  Workflow:   https://github.com/$REPO/actions/workflows/$WORKFLOW"
echo ""
echo "⏱️  Expected Duration: 3-5 minutes"
echo ""
echo "📋 Workflow will:"
echo "  1. SetUp GCP Workload Identity Federation (WIF) pool & provider"
echo "  2. Setup AWS OIDC provider & GitHub role"
echo "  3. Configure HashiCorp Vault JWT authentication"
echo "  4. Create GitHub repository secrets for all providers"
echo "  5. Output configuration artifacts"
echo ""
echo "⬇️  Next Steps:"
echo "  1. Monitor workflow execution at above URL"
echo "  2. Wait for completion (green checkmark)"
echo "  3. Download artifacts with provider IDs"
echo "  4. Verify GitHub secrets created: gh secret list"
echo "  5. Close Issue #1947"
echo "  6. Proceed to Phase 3: Key Revocation"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Phase 2 Queued"
echo "════════════════════════════════════════════════════════════════"
