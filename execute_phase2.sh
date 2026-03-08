#!/bin/bash
# Phase 2 Execution Script - Simple Method
# Usage: ./execute_phase2.sh
# Or: bash execute_phase2.sh

set -e

echo "================================================"
echo "  PHASE 2: OIDC/WIF CONFIGURATION TRIGGER"
echo "================================================"
echo ""
echo "Starting Phase 2 execution..."
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ Error: GitHub CLI (gh) not found"
    echo "Install with: brew install gh  (macOS)"
    echo "            apt install gh      (Linux)"
    echo "            download from: https://cli.github.com"
    exit 1
fi

# Verify gh authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Error: gh CLI not authenticated"
    echo "Run: gh auth login"
    exit 1
fi

# Trigger the workflow
echo "Triggering setup-oidc-infrastructure workflow..."
echo ""

gh workflow run setup-oidc-infrastructure.yml \
    --ref main \
    --repo kushin77/self-hosted-runner

echo ""
echo "✅ Phase 2 workflow triggered successfully!"
echo ""
echo "Next steps:"
echo "1. Monitor progress at:"
echo "   https://github.com/kushin77/self-hosted-runner/actions/workflows/setup-oidc-infrastructure.yml"
echo ""
echo "2. Wait for green ✓ checkmark (3-5 minutes)"
echo ""
echo "3. Verify 4 secrets created:"
echo "   gh secret list --repo kushin77/self-hosted-runner"
echo ""
echo "4. Expected secrets:"
echo "   - GCP_WIF_PROVIDER_ID"
echo "   - AWS_ROLE_ARN"
echo "   - VAULT_ADDR"
echo "   - VAULT_JWT_ROLE"
echo ""
echo "5. Then proceed to Phase 3 using:"
echo "   See PHASE_3_EXECUTION_GUIDE.md"
echo ""
echo "================================================"
