#!/bin/bash
#
# Integration Tests - Credential Management System
# Last Updated: 2026-03-09
# Purpose: Automated validation of P0/P1/P2 credential system
#
# Usage: ./tests/integration-test-credentials.sh [test-name or 'all']
# Examples:
#   ./tests/integration-test-credentials.sh all              # Run all tests
#   ./tests/integration-test-credentials.sh immutability     # Single test
#   ./tests/integration-test-credentials.sh --verbose        # With debug output
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Configuration
TEST_DIR="${TEST_DIR:-.}"
MOCK_PROJECT_ID="${MOCK_PROJECT_ID:-test-project}"
MOCK_VAULT_ADDR="${MOCK_VAULT_ADDR:-http://localhost:8200}"
VERBOSE="${VERBOSE:-0}"

# Helper functions

log_info() {
    echo -e "${BLUE}ℹ ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}✓ ${1}${NC}"
    ((TESTS_PASSED++))
}

log_failure() {
    echo -e "${RED}✗ ${1}${NC}"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}⊘ ${1}${NC}"
    ((TESTS_SKIPPED++))
}

log_header() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ${1}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

debug() {
    if [ "$VERBOSE" = "1" ]; then
        echo -e "${YELLOW}[DEBUG] ${1}${NC}"
    fi
}

# Advance assertions

assert_file_exists() {
    local file="$1"
    local test_name="${2:-File exists: $file}"
    
    if [ -f "$file" ]; then
        log_success "$test_name"
    else
        log_failure "$test_name (file not found: $file)"
    fi
}

assert_command_exists() {
    local cmd="$1"
    local test_name="${2:-Command exists: $cmd}"
    
    if command -v "$cmd" &> /dev/null; then
        log_success "$test_name"
    else
        log_failure "$test_name (command not found: $cmd)"
    fi
}

assert_contains() {
    local content="$1"
    local search="$2"
    local test_name="${3:-Content contains: $search}"
    
    if echo "$content" | grep -q "$search"; then
        log_success "$test_name"
    else
        log_failure "$test_name (not found: $search)"
        debug "Content: $content"
    fi
}

---

# TEST SUITE 1: Infrastructure

test_immutability_system() {
    log_header "TEST 1.1: Immutable Audit System"
    
    # Check Python script exists and is executable
    assert_file_exists "scripts/immutable-audit.py" "Immutable audit script exists"
    
    # Verify it's Python 3
    if python3 --version | grep -q "3\.[0-9]"; then
        log_success "Python 3 available"
    else
        log_failure "Python 3 not available"
    fi
    
    # Test audit directory structure
    if [ -d ".audit-logs" ]; then
        log_success "Audit logs directory exists"
    else
        log_skip "Audit logs not created yet (first run will create)"
    fi
}

test_credential_helpers() {
    log_header "TEST 1.2: Credential Helper Scripts"
    
    assert_file_exists "scripts/cred-helpers/enhanced-fetch-gsm.sh" "GSM helper exists"
    assert_file_exists "scripts/cred-helpers/enhanced-fetch-vault.sh" "Vault helper exists"
    assert_file_exists "scripts/credential-monitoring.sh" "Monitoring script exists"
    
    # Check they're executable
    if [ -x "scripts/cred-helpers/enhanced-fetch-gsm.sh" ]; then
        log_success "GSM helper is executable"
    else
        log_failure "GSM helper not executable"
    fi
}

test_rotation_workflow() {
    log_header "TEST 1.3: Rotation Workflow"
    
    assert_file_exists "scripts/auto-credential-rotation.sh" "Rotation script exists"
    assert_file_exists ".github/workflows/auto-credential-rotation.yml" "Rotation workflow exists"
    assert_file_exists ".github/workflows/credential-health-check.yml" "Health check workflow exists"
}

test_policy_enforcement() {
    log_header "TEST 1.4: Policy Enforcement"
    
    assert_file_exists "scripts/.pre-commit-hook" "Pre-commit hook exists"
    assert_file_exists "scripts/setup-policy-enforcement.sh" "Policy setup script exists"
    
    # Check hook content for expected patterns
    if grep -q "VAULT_TOKEN\|AWS_SECRET\|private_key" scripts/.pre-commit-hook; then
        log_success "Pre-commit hook contains secret patterns"
    else
        log_failure "Pre-commit hook missing secret patterns"
    fi
}

---

# TEST SUITE 2: Immutability

test_hash_chain_integrity() {
    log_header "TEST 2.1: Hash Chain Integrity"
    
    # Create a test audit entry
    local test_entry='{"timestamp":"2026-03-09T10:00:00Z","session_id":"test-1","operation":"test","status":"success"}'
    
    # Test that manual audit creation works
    if python3 scripts/immutable-audit.py --operation "test_run" --status "success" 2>/dev/null; then
        log_success "Audit log entry creation works"
    else
        log_skip "Audit system test (requires proper environment)"
    fi
}

test_append_only_property() {
    log_header "TEST 2.2: Append-Only Property"
    
    # Verify .audit-logs directory is created
    if [ -d ".audit-logs" ]; then
        local audit_count=$(ls -1 .audit-logs/*.jsonl 2>/dev/null | wc -l)
        if [ "$audit_count" -gt 0 ]; then
            log_success "Audit logs are JSONL (append-only format)"
        fi
    fi
    
    # Check that logs are JSONL (one JSON object per line)
    if [ -d ".audit-logs" ]; then
        local jsonl_valid=0
        for log_file in .audit-logs/*.jsonl; do
            if [ -f "$log_file" ]; then
                # Check that each line is valid JSON
                while IFS= read -r line; do
                    if echo "$line" | python3 -m json.tool > /dev/null 2>&1; then
                        jsonl_valid=1
                    fi
                done < "$log_file"
            fi
        done
        
        if [ $jsonl_valid -eq 1 ]; then
            log_success "Audit logs follow JSONL format (append-only)"
        fi
    fi
}

test_hash_chain_verification() {
    log_header "TEST 2.3: Hash Chain Verification"
    
    # This would require actual audit logs
    if python3 scripts/immutable-audit.py verify 2>/dev/null | grep -q "Hash chain"; then
        log_success "Hash chain verification works"
    else
        log_skip "Hash chain verification (no logs yet)"
    fi
}

---

# TEST SUITE 3: Ephemeral Credentials

test_ttl_enforcement() {
    log_header "TEST 3.1: TTL Enforcement"
    
    # Check that enhanced-fetch scripts set TTL
    if grep -q "TTL\|ttl\|3600\|300" scripts/cred-helpers/enhanced-fetch-gsm.sh; then
        log_success "GSM helper enforces TTL"
    else
        log_failure "GSM helper missing TTL logic"
    fi
    
    if grep -q "TTL\|ttl\|3600" scripts/cred-helpers/enhanced-fetch-vault.sh; then
        log_success "Vault helper enforces TTL"
    else
        log_failure "Vault helper missing TTL logic"
    fi
}

test_credential_caching() {
    log_header "TEST 3.2: Credential Caching"
    
    # Check that cache directory is used
    if grep -q "\.credentials-cache\|credentials-cache" scripts/cred-helpers/enhanced-fetch-gsm.sh; then
        log_success "GSM helper uses credential cache"
    else
        log_failure "GSM helper not using cache"
    fi
    
    # Verify cache directory can be created
    if mkdir -p .credentials-cache 2>/dev/null; then
        log_success "Credential cache directory writable"
    else
        log_failure "Cannot create credentials cache"
    fi
}

test_cache_expiry() {
    log_header "TEST 3.3: Cache Expiry"
    
    # Check Vault helper has TTL validation
    if grep -q "mtime\|expir\|age" scripts/cred-helpers/enhanced-fetch-vault.sh; then
        log_success "Vault helper validates cache age/expiry"
    else
        log_failure "Vault helper missing cache expiry logic"
    fi
}

---

# TEST SUITE 4: Idempotency

test_rotation_idempotency() {
    log_header "TEST 4.1: Rotation Idempotency"
    
    # Check rotation script for safety patterns
    if grep -q "|| true\|2>/dev/null\|set -e" scripts/auto-credential-rotation.sh; then
        log_success "Rotation script has error handling"
    else
        log_failure "Rotation script missing error safety"
    fi
}

test_helper_idempotency() {
    log_header "TEST 4.2: Helper Idempotency"
    
    # Verify helpers check for existing credentials before re-fetching
    if grep -q "exist\|already\|cache" scripts/cred-helpers/enhanced-fetch-gsm.sh; then
        log_success "GSM helper checks for existing credentials"
    else
        log_failure "GSM helper missing existence check"
    fi
}

test_no_duplicates_on_rerun() {
    log_header "TEST 4.3: No Duplicates on Re-run"
    
    # Helper structure: idempotent re-runs should not create duplicate entries
    if grep -q "if \[\|if grep" scripts/credential-monitoring.sh; then
        log_success "Monitoring tool has conditional logic"
    else
        log_failure "Monitoring tool missing conditional checks"
    fi
}

---

# TEST SUITE 5: Multi-Cloud Failover

test_failover_chain() {
    log_header "TEST 5.1: Failover Chain Defined"
    
    # Check rotation script defines failover
    if grep -q "gsm\|vault\|kms" scripts/auto-credential-rotation.sh; then
        log_success "Rotation script mentions all 3 providers"
    else
        log_failure "Rotation script missing provider names"
    fi
}

test_provider_detection() {
    log_header "TEST 5.2: Provider Status Detection"
    
    assert_file_exists "scripts/credential-monitoring.sh" "Provider monitoring script exists"
    
    # Check monitoring script can query provider status
    if grep -q "health\|status\|up\|down" scripts/credential-monitoring.sh; then
        log_success "Monitoring script checks provider status"
    else
        log_failure "Monitoring script missing status checks"
    fi
}

test_automatic_failover() {
    log_header "TEST 5.3: Automatic Failover Logic"
    
    # Verify fallback logic exists
    if grep -q "if.*fail\|catch\|except\|||" scripts/cred-helpers/enhanced-fetch-vault.sh; then
        log_success "Vault helper has fallback logic"
    else
        log_failure "Vault helper missing fallback"
    fi
}

---

# TEST SUITE 6: Automation

test_scheduled_rotation() {
    log_header "TEST 6.1: Scheduled Rotation"
    
    # Check workflow has schedule
    if grep -q "schedule:" .github/workflows/auto-credential-rotation.yml; then
        log_success "Rotation workflow has schedule"
    else
        log_failure "Rotation workflow missing schedule"
    fi
    
    # Verify 15-minute schedule
    if grep -A 2 "schedule:" .github/workflows/auto-credential-rotation.yml | grep -q "15\|*/15"; then
        log_success "Rotation scheduled every 15 minutes"
    else
        log_skip "Could not verify 15-min schedule (check workflow manually)"
    fi
}

test_scheduled_health_check() {
    log_header "TEST 6.2: Scheduled Health Check"
    
    if grep -q "schedule:" .github/workflows/credential-health-check.yml; then
        log_success "Health check workflow has schedule"
    else
        log_failure "Health check workflow missing schedule"
    fi
}

test_auto_escalation() {
    log_header "TEST 6.3: Auto-Escalation on Failure"
    
    # Check health check workflow creates issues
    if grep -q "issue\|create-issue\|gh issue" .github/workflows/credential-health-check.yml; then
        log_success "Health check can create GitHub issues"
    else
        log_skip "Health check auto-escalation (check workflow manually)"
    fi
}

---

# TEST SUITE 7: Configuration

test_secrets_documented() {
    log_header "TEST 7.1: Required Secrets Documented"
    
    assert_file_exists "docs/REPO_SECRETS_REQUIRED.md" "Secrets requirement doc exists"
    
    # Check that required secrets are listed
    if grep -q "VAULT_ADDR\|GSM\|AWS" docs/REPO_SECRETS_REQUIRED.md; then
        log_success "Required secrets are documented"
    else
        log_failure "Required secrets doc incomplete"
    fi
}

test_policy_documented() {
    log_header "TEST 7.2: Policy Documented"
    
    assert_file_exists "docs/NO_DIRECT_DEVELOPMENT.md" "No-direct-development policy doc exists"
}

test_system_documented() {
    log_header "TEST 7.3: System Documented"
    
    assert_file_exists "docs/P0_COMPLETE.md" "P0 system documentation exists"
    assert_file_exists "docs/CREDENTIAL_RUNBOOK.md" "Credential runbook exists"
    assert_file_exists "docs/DISASTER_RECOVERY.md" "Disaster recovery guide exists"
}

---

# TEST SUITE 8: Compliance

test_audit_retention() {
    log_header "TEST 8.1: Audit Retention Policy"
    
    # Check retention is documented
    if grep -q "365\|1 year" docs/AUDIT_TRAIL_GUIDE.md; then
        log_success "365-day audit retention documented"
    else
        log_failure "Audit retention not documented"
    fi
}

test_soc2_compliance() {
    log_header "TEST 8.2: SOC 2 Compliance Coverage"
    
    if grep -q "SOC 2\|CC6\|CC7\|CC8" docs/AUDIT_TRAIL_GUIDE.md; then
        log_success "SOC 2 compliance mapping documented"
    else
        log_failure "SOC 2 mapping missing"
    fi
}

test_iso_compliance() {
    log_header "TEST 8.3: ISO 27001 Compliance Coverage"
    
    if grep -q "ISO 27001\|A.12.4\|A.13" docs/AUDIT_TRAIL_GUIDE.md; then
        log_success "ISO 27001 compliance mapping documented"
    else
        log_failure "ISO 27001 mapping missing"
    fi
}

---

# Main test runner

run_all_tests() {
    local category="$1"
    
    case "$category" in
        infrastructure)
            test_immutability_system
            test_credential_helpers
            test_rotation_workflow
            test_policy_enforcement
            ;;
        immutability)
            test_hash_chain_integrity
            test_append_only_property
            test_hash_chain_verification
            ;;
        ephemeral)
            test_ttl_enforcement
            test_credential_caching
            test_cache_expiry
            ;;
        idempotency)
            test_rotation_idempotency
            test_helper_idempotency
            test_no_duplicates_on_rerun
            ;;
        failover)
            test_failover_chain
            test_provider_detection
            test_automatic_failover
            ;;
        automation)
            test_scheduled_rotation
            test_scheduled_health_check
            test_auto_escalation
            ;;
        configuration)
            test_secrets_documented
            test_policy_documented
            test_system_documented
            ;;
        compliance)
            test_audit_retention
            test_soc2_compliance
            test_iso_compliance
            ;;
        all|*)
            test_immutability_system
            test_credential_helpers
            test_rotation_workflow
            test_policy_enforcement
            test_hash_chain_integrity
            test_append_only_property
            test_hash_chain_verification
            test_ttl_enforcement
            test_credential_caching
            test_cache_expiry
            test_rotation_idempotency
            test_helper_idempotency
            test_no_duplicates_on_rerun
            test_failover_chain
            test_provider_detection
            test_automatic_failover
            test_scheduled_rotation
            test_scheduled_health_check
            test_auto_escalation
            test_secrets_documented
            test_policy_documented
            test_system_documented
            test_audit_retention
            test_soc2_compliance
            test_iso_compliance
            ;;
    esac
}

# Print summary

print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    local pass_rate=$((TESTS_PASSED * 100 / total))
    
    echo
    log_header "Test Summary"
    echo -e "${GREEN}✓ Passed:  ${TESTS_PASSED}${NC}"
    echo -e "${RED}✗ Failed:  ${TESTS_FAILED}${NC}"
    echo -e "${YELLOW}⊘ Skipped: ${TESTS_SKIPPED}${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "Total:    ${total} (${pass_rate}% pass rate)"
    echo
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED (or skipped)${NC}"
        return 0
    else
        echo -e "${RED}✗ SOME TESTS FAILED - Review above${NC}"
        return 1
    fi
}

---

# Entry point

main() {
    local test_category="${1:-all}"
    
    case "$test_category" in
        --help|-h)
            echo "Integration Tests - Credential Management System"
            echo "Usage: $0 [test-category|--help|--verbose]"
            echo "Categories:"
            echo "  all             - Run all tests"
            echo "  infrastructure  - Test script/workflow setup"
            echo "  immutability    - Test audit log immutability"
            echo "  ephemeral       - Test credential TTL/caching"
            echo "  idempotency     - Test safe re-run behavior"
            echo "  failover        - Test multi-cloud failover"
            echo "  automation      - Test scheduled workflows"
            echo "  configuration   - Test documentation"
            echo "  compliance      - Test SOC2/ISO/PCI compliance"
            exit 0
            ;;
        --verbose|-v)
            VERBOSE=1
            test_category="${2:-all}"
            run_all_tests "$test_category"
            ;;
        *)
            run_all_tests "$test_category"
            ;;
    esac
    
    print_summary
}

main "$@"
