#!/bin/bash
# Verify deployment field provisioning and provider connectivity
# Tests all 4 critical fields and their associated credential providers
#
# Usage: verify-deployment-provisioning.sh [--verbose]

set -euo pipefail

VERBOSE=${VERBOSE:-false}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_LOG="${REPO_ROOT}/logs/deployment-verification-audit.jsonl"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# UTILITIES
# ============================================================================

verbose_log() {
    if [ "$VERBOSE" = "true" ] || [ "$VERBOSE" = "1" ]; then
        echo "[VERBOSE] $*" >&2
    fi
}

pass() { echo -e "${GREEN}✅${NC} $*"; }
fail() { echo -e "${RED}❌${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️${NC} $*"; }

audit_verification() {
    local field="$1" test="$2" result="$3"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local entry="{\"timestamp\":\"$timestamp\",\"field\":\"$field\",\"test\":\"$test\",\"result\":\"$result\",\"hostname\":\"$(hostname)\"}"
    mkdir -p "$(dirname "$AUDIT_LOG")"
    echo "$entry" >> "$AUDIT_LOG"
}

# ============================================================================
# VERIFICATION FUNCTIONS
# ============================================================================

verify_field_exists() {
    local field="$1"
    verbose_log "Checking if $field is set..."
    
    if [ -n "${!field:-}" ]; then
        pass "$field is configured"
        audit_verification "$field" "field_exists" "pass"
        return 0
    else
        fail "$field is not configured"
        audit_verification "$field" "field_exists" "fail"
        return 1
    fi
}

verify_field_not_placeholder() {
    local field="$1"
    local value="${!field:-}"
    
    verbose_log "Checking if $field is not a placeholder..."
    
    if echo "$value" | grep -qiE "(example\.com|placeholder|YOUR_|EXAMPLE|PLACEHOLDER|\*\*\*|123456789012)"; then
        warn "$field contains placeholder value: $value"
        audit_verification "$field" "not_placeholder" "fail"
        return 1
    else
        pass "$field contains actual value (not placeholder)"
        audit_verification "$field" "not_placeholder" "pass"
        return 0
    fi
}

verify_vault_connectivity() {
    verbose_log "Testing Vault connectivity..."
    
    local vault_addr="${VAULT_ADDR:-}"
    if [ -z "$vault_addr" ]; then
        warn "VAULT_ADDR not set, skipping Vault connectivity test"
        audit_verification "VAULT_ADDR" "vault_connectivity" "skip"
        return 2
    fi
    
    # Test basic connectivity
    if curl -s --connect-timeout 5 -I "$vault_addr/v1/sys/health" > /dev/null 2>&1; then
        pass "Vault server is reachable at $vault_addr"
        audit_verification "VAULT_ADDR" "vault_reachable" "pass"
        
        # Test health endpoint
        if response=$(curl -s --connect-timeout 5 "$vault_addr/v1/sys/health" 2>/dev/null); then
            sealed=$(echo "$response" | jq -r '.sealed // "unknown"' 2>/dev/null || echo "unknown")
            initialized=$(echo "$response" | jq -r '.initialized // "unknown"' 2>/dev/null || echo "unknown")
            
            if [ "$initialized" = "true" ]; then
                pass "Vault is initialized"
                audit_verification "VAULT_ADDR" "vault_initialized" "pass"
            else
                fail "Vault is not initialized"
                audit_verification "VAULT_ADDR" "vault_initialized" "fail"
                return 1
            fi
            
            if [ "$sealed" = "false" ]; then
                pass "Vault is unsealed and ready"
                audit_verification "VAULT_ADDR" "vault_unsealed" "pass"
                return 0
            else
                fail "Vault is sealed (cannot authenticate)"
                audit_verification "VAULT_ADDR" "vault_sealed" "fail"
                return 1
            fi
        fi
    else
        fail "Cannot reach Vault at $vault_addr"
        audit_verification "VAULT_ADDR" "vault_reachable" "fail"
        return 1
    fi
}

verify_vault_role() {
    verbose_log "Verifying Vault role configuration..."
    
    local vault_role="${VAULT_ROLE:-}"
    if [ -z "$vault_role" ]; then
        fail "VAULT_ROLE not set"
        audit_verification "VAULT_ROLE" "vault_role_set" "fail"
        return 1
    fi
    
    if echo "$vault_role" | grep -qiE "(placeholder|example|YOUR_)"; then
        fail "VAULT_ROLE contains placeholder: $vault_role"
        audit_verification "VAULT_ROLE" "vault_role_placeholder" "fail"
        return 1
    fi
    
    pass "VAULT_ROLE is configured: $vault_role"
    audit_verification "VAULT_ROLE" "vault_role_configured" "pass"
    return 0
}

verify_aws_role_arn() {
    verbose_log "Verifying AWS role ARN format..."
    
    local aws_role="${AWS_ROLE_TO_ASSUME:-}"
    
    if [ -z "$aws_role" ]; then
        fail "AWS_ROLE_TO_ASSUME not set"
        audit_verification "AWS_ROLE_TO_ASSUME" "aws_role_set" "fail"
        return 1
    fi
    
    # Validate ARN format: arn:aws:iam::ACCOUNT:role/ROLE-NAME
    if echo "$aws_role" | grep -qE "^arn:aws:iam::[0-9]{12}:role/[a-zA-Z0-9_-]+"; then
        pass "AWS_ROLE_TO_ASSUME has valid ARN format"
        audit_verification "AWS_ROLE_TO_ASSUME" "aws_role_arn_format" "pass"
        
        # Extract and display account ID (for verification)
        local account=$(echo "$aws_role" | grep -oE '[0-9]{12}')
        verbose_log "AWS Account ID: $account"
        
        return 0
    else
        fail "AWS_ROLE_TO_ASSUME invalid format: $aws_role"
        fail "Expected format: arn:aws:iam::123456789012:role/RoleName"
        audit_verification "AWS_ROLE_TO_ASSUME" "aws_role_arn_format" "fail"
        return 1
    fi
}

verify_aws_oidc_provider() {
    verbose_log "Verifying AWS OIDC provider availability..."
    
    if ! command -v aws &>/dev/null; then
        warn "AWS CLI not available, cannot verify OIDC provider"
        audit_verification "AWS_ROLE_TO_ASSUME" "aws_cli_available" "skip"
        return 2
    fi
    
    # Try to get OIDC provider information
    if aws sts get-caller-identity &>/dev/null 2>&1; then
        pass "AWS credentials are available"
        audit_verification "AWS_ROLE_TO_ASSUME" "aws_credentials_available" "pass"
        return 0
    else
        warn "AWS credentials not available (may be expected outside GitHub Actions)"
        audit_verification "AWS_ROLE_TO_ASSUME" "aws_credentials_available" "skip"
        return 2
    fi
}

verify_gcp_wif_provider() {
    verbose_log "Verifying GCP Workload Identity Federation provider..."
    
    local gcp_provider="${GCP_WORKLOAD_IDENTITY_PROVIDER:-}"
    
    if [ -z "$gcp_provider" ]; then
        fail "GCP_WORKLOAD_IDENTITY_PROVIDER not set"
        audit_verification "GCP_WORKLOAD_IDENTITY_PROVIDER" "gcp_provider_set" "fail"
        return 1
    fi
    
    # Validate WIF provider format: projects/PROJECT_ID/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID
    if echo "$gcp_provider" | grep -qE "^projects/[^/]+/locations/global/workloadIdentityPools/[^/]+/providers/[^/]+"; then
        pass "GCP_WORKLOAD_IDENTITY_PROVIDER has valid format"
        audit_verification "GCP_WORKLOAD_IDENTITY_PROVIDER" "gcp_provider_format" "pass"
        
        # Extract project ID for verification
        local project_id=$(echo "$gcp_provider" | cut -d'/' -f2)
        verbose_log "GCP Project ID: $project_id"
        
        return 0
    else
        fail "GCP_WORKLOAD_IDENTITY_PROVIDER invalid format: $gcp_provider"
        fail "Expected format: projects/PROJECT/locations/global/workloadIdentityPools/POOL/providers/PROVIDER"
        audit_verification "GCP_WORKLOAD_IDENTITY_PROVIDER" "gcp_provider_format" "fail"
        return 1
    fi
}

verify_gcp_credentials_available() {
    verbose_log "Verifying GCP credentials availability..."
    
    if ! command -v gcloud &>/dev/null; then
        warn "gcloud CLI not available, cannot verify GCP credentials"
        audit_verification "GCP_WORKLOAD_IDENTITY_PROVIDER" "gcloud_available" "skip"
        return 2
    fi
    
    if gcloud auth application-default print-access-token &>/dev/null 2>&1; then
        pass "GCP credentials are available"
        audit_verification "GCP_WORKLOAD_IDENTITY_PROVIDER" "gcp_credentials_available" "pass"
        return 0
    else
        warn "GCP credentials not available (may be expected outside GCP/GitHub Actions)"
        audit_verification "GCP_WORKLOAD_IDENTITY_PROVIDER" "gcp_credentials_available" "skip"
        return 2
    fi
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================

generate_summary() {
    local passed_count=$1
    local failed_count=$2
    local skipped_count=$3
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  DEPLOYMENT FIELD VERIFICATION SUMMARY                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Passed:  ${GREEN}✅ $passed_count${NC}"
    echo "  Failed:  ${RED}❌ $failed_count${NC}"
    echo "  Skipped: ${YELLOW}⏭️  $skipped_count${NC}"
    echo ""
    
    if [ $failed_count -eq 0 ]; then
        echo "${GREEN}✅ All deployment fields are properly configured!${NC}"
        return 0
    else
        echo "${RED}❌ Some deployment fields need attention.${NC}"
        return 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo "🔍 Verifying deployment field provisioning..."
    echo ""
    
    local passed=0
    local failed=0
    local skipped=0
    
    # Tests for VAULT_ADDR
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VAULT_ADDR - Vault Server URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    verify_field_exists "VAULT_ADDR" && ((passed++)) || ((failed++))
    verify_field_not_placeholder "VAULT_ADDR" && ((passed++)) || ((failed++))
    verify_vault_connectivity && ((passed++)) || ((failed++)) || ((skipped++))
    echo ""
    
    # Tests for VAULT_ROLE
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VAULT_ROLE - Vault GitHub Actions Role"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    verify_field_exists "VAULT_ROLE" && ((passed++)) || ((failed++))
    verify_field_not_placeholder "VAULT_ROLE" && ((passed++)) || ((failed++))
    verify_vault_role && ((passed++)) || ((failed++))
    echo ""
    
    # Tests for AWS_ROLE_TO_ASSUME
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AWS_ROLE_TO_ASSUME - AWS IAM Role ARN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    verify_field_exists "AWS_ROLE_TO_ASSUME" && ((passed++)) || ((failed++))
    verify_field_not_placeholder "AWS_ROLE_TO_ASSUME" && ((passed++)) || ((failed++))
    verify_aws_role_arn && ((passed++)) || ((failed++))
    verify_aws_oidc_provider && ((passed++)) || ((skipped++)) || ((failed++))
    echo ""
    
    # Tests for GCP_WORKLOAD_IDENTITY_PROVIDER
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "GCP_WORKLOAD_IDENTITY_PROVIDER - GCP WIF Provider"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    verify_field_exists "GCP_WORKLOAD_IDENTITY_PROVIDER" && ((passed++)) || ((failed++))
    verify_field_not_placeholder "GCP_WORKLOAD_IDENTITY_PROVIDER" && ((passed++)) || ((failed++))
    verify_gcp_wif_provider && ((passed++)) || ((failed++))
    verify_gcp_credentials_available && ((passed++)) || ((skipped++)) || ((failed++))
    echo ""
    
    # Generate summary
    generate_summary "$passed" "$failed" "$skipped"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

main
exit $([ "$failed" -eq 0 ] && echo 0 || echo 1)
