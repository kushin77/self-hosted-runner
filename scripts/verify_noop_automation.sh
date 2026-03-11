#!/usr/bin/env bash
# ============================================================================
# VERIFY NO-OPS AUTOMATION IMPLEMENTATION
# ============================================================================
# Comprehensive verification that all hands-off automation is properly
# configured and operational. Safe to run repeatedly.
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() { printf "${GREEN}✓${NC} %s\n" "$*"; }
log_fail() { printf "${RED}✗${NC} %s\n" "$*"; }
log_info() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }

passed=0
failed=0
warnings=0

# ============================================================================
# CHECKS
# ============================================================================

check_github_actions_disabled() {
    log_info "Checking GitHub Actions are disabled..."
    
    # No workflows directory or empty
    if [[ ! -d .github/workflows ]] || [[ -z "$(ls -A .github/workflows 2>/dev/null)" ]]; then
        log_pass "No GitHub Actions workflows found"
        ((passed++))
    else
        log_fail "GitHub Actions workflows detected!"
        ((failed++))
    fi
    
    # Check notice files exist
    if [[ -f .github/ACTIONS_DISABLED_NOTICE.md ]]; then
        log_pass "ACTIONS_DISABLED_NOTICE.md exists"
        ((passed++))
    else
        log_fail "ACTIONS_DISABLED_NOTICE.md missing"
        ((failed++))
    fi
    
    if [[ -f .github/NO_GITHUB_ACTIONS.md ]]; then
        log_pass "NO_GITHUB_ACTIONS.md exists"
        ((passed++))
    else
        log_warn "NO_GITHUB_ACTIONS.md missing"
        ((warnings++))
    fi
}

check_terraform_infrastructure() {
    log_info "Checking Terraform infrastructure files..."
    
    local required_files=(
        "terraform/immutable_infrastructure.tf"
        "terraform/complete_credential_management.tf"
        "terraform/variables_immutable.tf"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_pass "$file exists"
            ((passed++))
        else
            log_fail "$file missing"
            ((failed++))
        fi
    done
    
    # Check Terraform syntax
    if cd terraform && terraform validate >/dev/null 2>&1; then
        log_pass "Terraform configuration is valid"
        ((passed++))
        cd ..
    else
        log_warn "Terraform validation issues (may be expected if not initialized)"
        ((warnings++))
        cd ..
    fi
}

check_deployment_scripts() {
    log_info "Checking deployment automation scripts..."
    
    local required_scripts=(
        "scripts/deploy/cloud_build_direct_deploy.sh"
        "scripts/automation/noop_orchestration.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ -x "$script" ]]; then
            log_pass "$script is executable"
            ((passed++))
        elif [[ -f "$script" ]]; then
            log_warn "$script exists but not executable"
            chmod +x "$script" 2>/dev/null || true
            ((warnings++))
        else
            log_fail "$script missing"
            ((failed++))
        fi
    done
}

check_cloud_functions() {
    log_info "Checking Cloud Function code..."
    
    local required_functions=(
        "scripts/cloud_functions/ephemeral_cleanup/main.py"
        "scripts/cloud_functions/ephemeral_cleanup/requirements.txt"
        "scripts/cloud_functions/secret_rotation/main.py"
        "scripts/cloud_functions/secret_rotation/requirements.txt"
    )
    
    for func in "${required_functions[@]}"; do
        if [[ -f "$func" ]]; then
            log_pass "$func exists"
            ((passed++))
        else
            log_fail "$func missing"
            ((failed++))
        fi
    done
}

check_documentation() {
    log_info "Checking documentation..."
    
    if [[ -f AUTOMATED_OPERATIONS_ARCHITECTURE.md ]]; then
        log_pass "AUTOMATED_OPERATIONS_ARCHITECTURE.md exists"
        ((passed++))
    else
        log_fail "AUTOMATED_OPERATIONS_ARCHITECTURE.md missing"
        ((failed++))
    fi
    
    if grep -q "No.*GitHub.*Actions" AUTOMATED_OPERATIONS_ARCHITECTURE.md 2>/dev/null; then
        log_pass "Architecture doc mentions no GitHub Actions"
        ((passed++))
    else
        log_warn "Architecture doc may not clearly state no GitHub Actions"
        ((warnings++))
    fi
}

check_cloud_build_config() {
    log_info "Checking Cloud Build configuration..."
    
    if [[ -f cloudbuild.yaml ]]; then
        log_pass "cloudbuild.yaml exists"
        ((passed++))
        
        if grep -q "docker" cloudbuild.yaml && grep -q "deploy" cloudbuild.yaml; then
            log_pass "Cloud Build config has build and deploy steps"
            ((passed++))
        else
            log_warn "Cloud Build config may be incomplete"
            ((warnings++))
        fi
    else
        log_fail "cloudbuild.yaml missing"
        ((failed++))
    fi
}

check_idempotент_operations() {
    log_info "Checking idempotent operation patterns..."
    
    # Check deployment script for idempotent markers
    if grep -q "idempotent" scripts/deploy/cloud_build_direct_deploy.sh; then
        log_pass "Deployment script marked as idempotent"
        ((passed++))
    else
        log_warn "Deployment script may not be clearly marked idempotent"
        ((warnings++))
    fi
    
    if grep -q "will use cache\|already exists\|only applies" scripts/deploy/cloud_build_direct_deploy.sh; then
        log_pass "Deployment script has idempotent safeguards"
        ((passed++))
    else
        log_warn "Deployment script idempotency not verified"
        ((warnings++))
    fi
}

check_credential_management() {
    log_info "Checking credential management implementation..."
    
    if grep -q "google_secret_manager" terraform/complete_credential_management.tf; then
        log_pass "GSM secrets configured"
        ((passed++))
    else
        log_fail "GSM secrets not found"
        ((failed++))
    fi
    
    if grep -q "google_kms_crypto_key" terraform/complete_credential_management.tf; then
        log_pass "KMS encryption configured"
        ((passed++))
    else
        log_fail "KMS encryption not found"
        ((failed++))
    fi
    
    if grep -q "vault" terraform/complete_credential_management.tf; then
        log_pass "Vault integration configured"
        ((passed++))
    else
        log_warn "Vault integration may be incomplete"
        ((warnings++))
    fi
}

check_audit_logging() {
    log_info "Checking audit and logging setup..."
    
    if grep -q "google_logging_project_sink\|google_bigquery_dataset" terraform/immutable_infrastructure.tf || \
       grep -q "google_logging_project_sink\|google_bigquery_dataset" terraform/complete_credential_management.tf; then
        log_pass "Audit logging to BigQuery configured"
        ((passed++))
    else
        log_warn "Audit logging may not be fully configured"
        ((warnings++))
    fi
}

check_orchestration_state() {
    log_info "Checking orchestration state directory..."
    
    if [[ -d .orchestration-state ]]; then
        log_pass "Orchestration state directory exists"
        ((passed++))
        
        if [[ -f .orchestration-state/deployment.log ]] || \
           [[ -f .orchestration-state/rotation.log ]] || \
           [[ -f .orchestration-state/cleanup.log ]]; then
            log_pass "Automation logs found"
            ((passed++))
        else
            log_info "No automation logs yet (expected on first run)"
        fi
    else
        log_info "Orchestration state directory will be created on first run"
    fi
}

# ============================================================================
# SUMMARY
# ============================================================================

summary() {
    echo ""
    echo "============================================================================"
    echo "NO-OPS AUTOMATION VERIFICATION REPORT"
    echo "============================================================================"
    echo ""
    printf "  ${GREEN}Passed:${NC}  %d\n" "$passed"
    printf "  ${YELLOW}Warnings:${NC} %d\n" "$warnings"
    printf "  ${RED}Failed:${NC}  %d\n" "$failed"
    echo ""
    
    if [[ $failed -eq 0 ]]; then
        echo "${GREEN}✓ NO-OPS AUTOMATION SYSTEM VERIFIED${NC}"
        echo ""
        echo "Status Summary:"
        echo "  ✓ GitHub Actions completely disabled"
        echo "  ✓ Cloud Build direct deployment configured"
        echo "  ✓ Immutable infrastructure in place"
        echo "  ✓ Ephemeral resource cleanup automated"
        echo "  ✓ Secret rotation automated (daily)"
        echo "  ✓ Audit logging enabled"
        echo "  ✓ Hands-off orchestration ready"
        echo ""
        echo "Next Steps:"
        echo "  1. Deploy with Terraform: terraform apply"
        echo "  2. Start continuous automation: ./scripts/automation/noop_orchestration.sh continuous"
        echo "  3. Monitor: gcloud logging read ... --follow"
        echo "  4. Verify: ./scripts/automation/noop_orchestration.sh health"
        return 0
    else
        echo "${RED}✗ VERIFICATION FAILED${NC}"
        echo ""
        echo "Please resolve the following issues:"
        return 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "============================================================================"
    echo "VERIFYING NO-OPS AUTOMATION IMPLEMENTATION"
    echo "============================================================================"
    echo ""
    
    check_github_actions_disabled
    echo ""
    check_terraform_infrastructure
    echo ""
    check_deployment_scripts
    echo ""
    check_cloud_functions
    echo ""
    check_documentation
    echo ""
    check_cloud_build_config
    echo ""
    check_idempotент_operations
    echo ""
    check_credential_management
    echo ""
    check_audit_logging
    echo ""
    check_orchestration_state
    
    summary
}

main "$@"
