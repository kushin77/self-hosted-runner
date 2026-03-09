#!/bin/bash
#
# Phase 2 Validation - Runtime Checker
# Last Updated: 2026-03-09
# Purpose: Validates that GitHub repository secrets are configured and accessible
#
# Usage: ./scripts/phase2-validate.sh [--check-only]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
SECRETS_FOUND=0
SECRETS_REQUIRED=4
VALIDATION_ERRORS=0

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Phase 2 Validation - Secret Configuration Check${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

# Check if running in GitHub Actions
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo -e "${GREEN}✓ Running in GitHub Actions context${NC}"
else
    echo -e "${YELLOW}⚠ Not in GitHub Actions context (local test mode)${NC}"
fi

echo
echo -e "${BLUE}Checking required secrets:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Helper function to check secret
check_secret() {
    local secret_name="$1"
    local secret_value="${!secret_name:-}"
    
    if [ -z "$secret_value" ]; then
        echo -e "${RED}✗ ${secret_name}${NC} - NOT CONFIGURED"
        ((VALIDATION_ERRORS++))
        return 1
    else
        # Show first 10 chars + "..." for security
        local display_value="${secret_value:0:10}..."
        echo -e "${GREEN}✓ ${secret_name}${NC} - configured (${display_value})"
        ((SECRETS_FOUND++))
        return 0
    fi
}

# Check each required secret
check_secret "VAULT_ADDR" || true
check_secret "VAULT_ROLE" || true
check_secret "AWS_ROLE_TO_ASSUME" || true
check_secret "GCP_WORKLOAD_IDENTITY_PROVIDER" || true

echo
echo -e "${BLUE}Summary:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Secrets configured: ${SECRETS_FOUND}/${SECRETS_REQUIRED}"
echo "  Validation errors:  ${VALIDATION_ERRORS}"
echo

# Phase 2 validation
if [ $VALIDATION_ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All secrets configured - Phase 2 validation READY${NC}"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Trigger credential rotation: ./scripts/auto-credential-rotation.sh rotate"
    echo "  2. Verify rotation: ./scripts/credential-monitoring.sh all"
    echo "  3. Check audit logs: grep 'credential_rotation' .audit-logs/*.jsonl"
    echo
    exit 0
else
    echo -e "${RED}❌ Missing or incomplete secrets - Phase 2 validation BLOCKED${NC}"
    echo
    echo -e "${YELLOW}Action Required:${NC}"
    echo "  1. Go to: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions"
    echo "  2. Add the missing secrets"
    echo "  3. Re-run this validation script"
    echo
    exit 1
fi
