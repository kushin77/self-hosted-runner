#!/bin/bash
#
# Phase 2 Validation - Credential Provider Setup Guide
# Last Updated: 2026-03-09
# Purpose: Guide operator through adding required GitHub repository secrets
#
# This script validates that all 4 required secrets are configured
# and can be accessed by GitHub Actions workflows.
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 2 Validation - GitHub Secrets Setup Guide          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running in GitHub Actions context
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo -e "${YELLOW}⚠️  This script should run in GitHub Actions context${NC}"
    echo "But you can run it locally to verify requirements."
fi

echo -e "${BLUE}Step 1: GitHub Repository Secrets Setup${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Add these 4 secrets to your GitHub repository:"
echo "  URL: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions"
echo
echo -e "${YELLOW}Required Secrets:${NC}"
echo "  1. VAULT_ADDR"
echo "     ├─ Value: Your Vault server URL (e.g., https://vault.example.com:8200)"
echo "     └─ Used by: GitHub Actions credential rotation workflow"
echo
echo "  2. VAULT_ROLE"
echo "     ├─ Value: GitHub Actions Vault role ID (configured in Vault)"
echo "     └─ Used by: Vault OIDC authentication"
echo
echo "  3. AWS_ROLE_TO_ASSUME"
echo "     ├─ Value: AWS IAM role ARN (e.g., arn:aws:iam::123456789012:role/github-actions)"
echo "     └─ Used by: AWS credential federation via OIDC"
echo
echo "  4. GCP_WORKLOAD_IDENTITY_PROVIDER"
echo "     ├─ Value: GCP WIF provider resource (e.g., projects/PROJECT_ID/locations/global/workloadIdentityPools/POOL/providers/PROVIDER)"
echo "     └─ Used by: GCP credential federation via OIDC"
echo

echo -e "${BLUE}Step 2: How to Add Secrets (GitHub UI)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "For each secret:"
echo "  1. Go to Settings → Secrets and variables → Actions"
echo "  2. Click 'New repository secret'"
echo "  3. Enter the Name (VAULT_ADDR, VAULT_ROLE, etc.)"
echo "  4. Enter the Value (the actual secret)"
echo "  5. Click 'Add secret'"
echo

echo -e "${BLUE}Step 3: Validation Checklist${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "To verify secrets are configured correctly:"
echo "  1. Go to Actions tab in GitHub"
echo "  2. Select 'Credential Health Check' workflow"
echo "  3. Click 'Run workflow' → Run workflow button"
echo "  4. Monitor the workflow execution"
echo
echo "You should see:"
echo "  ✓ Workflow runs successfully"
echo "  ✓ All 3 providers (GSM, Vault, KMS) report healthy"
echo "  ✓ Credential rotation completes"
echo "  ✓ Audit logs created"
echo

echo -e "${BLUE}Step 4: Automatic Activation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "After secrets are added:"
echo "  • Next scheduled rotation (15 min): 🟢 ACTIVE"
echo "  • Next scheduled health check (hourly): 🟢 ACTIVE"
echo "  • Workflows will run automatically"
echo "  • No manual intervention required"
echo

echo -e "${BLUE}Step 5: What Happens Next${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Phase 2 Validation Workflow:"
echo "  1. Credentials fetched from all 3 providers (GSM/Vault/KMS)"
echo "  2. Credentials cached with TTL validation"
echo "  3. Failover chain tested (GSM → Vault → KMS)"
echo "  4. Audit logs verified for integrity"
echo "  5. Health check confirms system operational"
echo
echo "Expected Results:"
echo "  ✓ All providers accessible and responding"
echo "  ✓ Credentials successfully rotated"
echo "  ✓ Immutable audit trail recording all operations"
echo "  ✓ System ready for production use"
echo

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📋 Documentation Reference${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "For detailed setup instructions:"
echo "  • [docs/REPO_SECRETS_REQUIRED.md](docs/REPO_SECRETS_REQUIRED.md)"
echo
echo "For failure troubleshooting:"
echo "  • [docs/CREDENTIAL_RUNBOOK.md](docs/CREDENTIAL_RUNBOOK.md)"
echo
echo "For disaster recovery:"
echo "  • [docs/DISASTER_RECOVERY.md](docs/DISASTER_RECOVERY.md)"
echo
echo "For compliance & audit:"
echo "  • [docs/AUDIT_TRAIL_GUIDE.md](docs/AUDIT_TRAIL_GUIDE.md)"
echo

echo -e "${GREEN}✅ Setup guide complete${NC}"
echo
echo "Next: Add the 4 secrets via GitHub UI, then trigger 'Credential Health Check' workflow"
echo
