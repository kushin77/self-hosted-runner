#!/bin/bash
#
# Phase 2 Secrets Validation & Provider Testing
# Purpose: Verify all 4 secrets are accessible and providers respond
# Last Updated: 2026-03-09
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_pass() {
    echo -e "${GREEN}✅ ${1}${NC}"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}❌ ${1}${NC}"
    ((FAILED++))
}

log_info() {
    echo -e "${BLUE}ℹ️  ${1}${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  ${1}${NC}"
}

header() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  ${1}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main validation flow

header "Phase 2: Secrets Validation & Provider Testing"

# Section 1: Environment Variable Check
header "1. Environment Variables"

log_info "Checking if secrets are available in current environment..."
echo

for secret in VAULT_ADDR VAULT_ROLE AWS_ROLE_TO_ASSUME GCP_WORKLOAD_IDENTITY_PROVIDER; do
    if [ -z "${!secret:-}" ]; then
        log_warn "$secret not set (expected in workflow environment)"
    else
        # Show first/last few chars (don't expose full secret)
        val="${!secret}"
        if [ ${#val} -gt 20 ]; then
            display="${val:0:10}...${val: -10}"
        else
            display="[set - $(echo -n $val | wc -c) chars]"
        fi
        log_pass "$secret is set ($display)"
    fi
done

echo

# Section 2: Vault Connectivity
header "2. Vault Provider - Connectivity & Authentication"

if [ -z "${VAULT_ADDR:-}" ]; then
    log_fail "VAULT_ADDR not set - cannot test Vault connectivity"
else
    log_info "Testing Vault server at: $VAULT_ADDR"
    
    # Test basic connectivity
    if curl -s -I --connect-timeout 5 "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        log_pass "Vault server is reachable"
        
        # Test health endpoint
        if response=$(curl -s --connect-timeout 5 "$VAULT_ADDR/v1/sys/health" 2>/dev/null); then
            log_pass "Vault health check successful"
            
            # Check sealed status
            sealed=$(echo "$response" | jq -r '.sealed // "unknown"' 2>/dev/null || echo "unknown")
            if [ "$sealed" = "false" ]; then
                log_pass "Vault is unsealed (ready for auth)"
            elif [ "$sealed" = "true" ]; then
                log_fail "Vault is sealed (cannot authenticate)"
            fi
        fi
    else
        log_fail "Cannot reach Vault at $VAULT_ADDR (check URL and network)"
        log_info "Ensure: URL is correct, firewall allows GitHub Actions IPs"
    fi
fi

echo

# Section 3: GitHub OIDC Token
header "3. GitHub OIDC Token - Token Availability"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_warn "GITHUB_TOKEN not set (may be expected locally)"
else
    log_pass "GitHub token is available"
fi

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
    log_warn "ACTIONS_ID_TOKEN_REQUEST_TOKEN not set (expected in GitHub Actions)"
    log_info "This is normal for local testing. In GitHub Actions, this will be available."
else
    log_pass "GitHub Actions ID token request is configured"
fi

echo

# Section 4: AWS Role Configuration
header "4. AWS - Role Configuration & Metadata"

if [ -z "${AWS_ROLE_TO_ASSUME:-}" ]; then
    log_fail "AWS_ROLE_TO_ASSUME not set"
else
    log_pass "AWS_ROLE_TO_ASSUME is configured"
    
    # Parse role details
    # Format: arn:aws:iam::123456789012:role/role-name
    if [[ "$AWS_ROLE_TO_ASSUME" =~ arn:aws:iam::([0-9]+):role/(.+) ]]; then
        account="${BASH_REMATCH[1]}"
        role_name="${BASH_REMATCH[2]}"
        log_info "  Account ID: $account"
        log_info "  Role Name: $role_name"
        
        # Verify ARN format
        if [ ${#account} -eq 12 ] && [ -n "$role_name" ]; then
            log_pass "AWS role ARN format is valid"
        else
            log_fail "AWS role ARN format is invalid (check account ID and role name)"
        fi
    else
        log_fail "AWS role ARN format is invalid (expected: arn:aws:iam::ACCOUNT:role/NAME)"
    fi
fi

echo

# Section 5: GCP Workload Identity
header "5. GCP - Workload Identity Provider Configuration"

if [ -z "${GCP_WORKLOAD_IDENTITY_PROVIDER:-}" ]; then
    log_fail "GCP_WORKLOAD_IDENTITY_PROVIDER not set"
else
    log_pass "GCP_WORKLOAD_IDENTITY_PROVIDER is configured"
    
    # Verify format
    if [[ "$GCP_WORKLOAD_IDENTITY_PROVIDER" =~ ^projects/[0-9]+/locations/global/workloadIdentityPools/.*/providers/.* ]]; then
        log_pass "GCP WIF provider format is valid"
        
        # Extract project ID
        if [[ "$GCP_WORKLOAD_IDENTITY_PROVIDER" =~ projects/([0-9]+)/ ]]; then
            project_id="${BASH_REMATCH[1]}"
            log_info "  GCP Project ID: $project_id"
        fi
    else
        log_fail "GCP WIF provider format is invalid"
        log_info "Expected: projects/PROJECT_ID/locations/global/workloadIdentityPools/POOL/providers/PROVIDER"
    fi
fi

echo

# Section 6: Credential Helpers Test
header "6. Credential Helpers - Testing Retrieval Scripts"

if [ -f "scripts/cred-helpers/enhanced-fetch-vault.sh" ]; then
    log_pass "Vault helper script exists"
    
    if [ -x "scripts/cred-helpers/enhanced-fetch-vault.sh" ]; then
        log_pass "Vault helper is executable"
    else
        log_fail "Vault helper is not executable (run: chmod +x scripts/cred-helpers/enhanced-fetch-vault.sh)"
    fi
else
    log_fail "Vault helper script not found at scripts/cred-helpers/enhanced-fetch-vault.sh"
fi

if [ -f "scripts/cred-helpers/enhanced-fetch-gsm.sh" ]; then
    log_pass "GSM helper script exists"
    if [ -x "scripts/cred-helpers/enhanced-fetch-gsm.sh" ]; then
        log_pass "GSM helper is executable"
    fi
else
    log_fail "GSM helper script not found"
fi

echo

# Section 7: Immutable Audit System
header "7. Immutable Audit - Log System Ready"

if [ -f "scripts/immutable-audit.py" ]; then
    log_pass "Immutable audit script exists"
    
    if python3 -m py_compile scripts/immutable-audit.py 2>/dev/null; then
        log_pass "Audit script has valid Python syntax"
    else
        log_fail "Audit script has syntax errors"
    fi
else
    log_fail "Immutable audit script not found"
fi

# Test audit directory
if mkdir -p .audit-logs 2>/dev/null; then
    log_pass "Audit logs directory writable"
else
    log_fail "Cannot write to .audit-logs directory"
fi

echo

# Section 8: Rotation Workflow
header "8. Rotation Workflow - Automation Ready"

if [ -f ".github/workflows/auto-credential-rotation.yml" ]; then
    log_pass "Rotation workflow exists"
    
    # Check if scheduled
    if grep -q "schedule:" .github/workflows/auto-credential-rotation.yml; then
        log_pass "Rotation workflow is scheduled"
        schedule=$(grep -A 4 "schedule:" .github/workflows/auto-credential-rotation.yml | grep "cron:" || echo "")
        if [ -n "$schedule" ]; then
            log_info "Schedule: $schedule"
        fi
    else
        log_fail "Rotation workflow is not scheduled"
    fi
else
    log_fail "Rotation workflow not found at .github/workflows/auto-credential-rotation.yml"
fi

if [ -f ".github/workflows/credential-health-check.yml" ]; then
    log_pass "Health check workflow exists"
    
    if grep -q "schedule:" .github/workflows/credential-health-check.yml; then
        log_pass "Health check workflow is scheduled"
    fi
else
    log_fail "Health check workflow not found"
fi

echo

# Final Summary
echo
header "Summary"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All validations passed! ($PASSED checks)${NC}"
    echo
    echo "Next steps:"
    echo "  1. Ensure all 4 GitHub secrets are added to the repository"
    echo "  2. Wait for next rotation cycle (15 minutes)"
    echo "  3. Monitor GitHub Actions for workflow success"
    echo "  4. Check audit logs: .audit-logs/audit-*.jsonl"
else
    echo -e "${RED}❌ Some validations failed ($FAILED failures, $PASSED passed)${NC}"
    echo
    echo "Next steps:"
    echo "  1. Fix failures listed above"
    echo "  2. Re-run this script to verify fixes"
    echo "  3. Reference: docs/CREDENTIAL_RUNBOOK.md (troubleshooting)"
fi

echo
exit $FAILED
