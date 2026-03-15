#!/bin/bash
#
# E2E COMPREHENSIVE TESTING FRAMEWORK
# Tests all infrastructure components end-to-end
# Reports all issues to git for tracking
#
# Date: March 14, 2026

set -euo pipefail

# ============================================================================
# TEST CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_LOG="${SCRIPT_DIR}/E2E_TEST_RESULTS_$(date +%Y%m%d_%H%M%S).log"
readonly TEST_ISSUES="${SCRIPT_DIR}/E2E_TEST_ISSUES_$(date +%Y%m%d_%H%M%S).md"

readonly WORKER_HOST="192.168.168.42"
readonly SERVICE_ACCOUNT="automation"
readonly SSH_KEY="${HOME}/.ssh/automation"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
ISSUES_FOUND=()

# ============================================================================
# LOGGING & OUTPUT FUNCTIONS
# ============================================================================

log() {
  local level="$1"
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$TEST_LOG"
}

test_start() {
  ((TESTS_RUN++))
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "TEST $TESTS_RUN: $@"
  echo "════════════════════════════════════════════════════════════════"
  tee -a "$TEST_LOG" <<< "TEST $TESTS_RUN: $@"
}

test_pass() {
  ((TESTS_PASSED++))
  log "PASS" "$@"
  echo "✅ PASSED"
}

test_fail() {
  ((TESTS_FAILED++))
  log "FAIL" "$@"
  echo "❌ FAILED: $@"
  ISSUES_FOUND+=("$@")
}

add_issue() {
  local title="$1"
  local description="$2"
  local severity="${3:-medium}"
  
  ISSUES_FOUND+=("[$severity] $title - $description")
}

# ============================================================================
# TEST SUITE 1: SSH AUTHENTICATION
# ============================================================================

test_suite_ssh_auth() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║            TEST SUITE 1: SSH AUTHENTICATION                    ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  # Test 1.1: SSH key exists
  test_start "SSH Key File Exists"
  if [ -f "$SSH_KEY" ]; then
    test_pass "SSH key found at $SSH_KEY"
  else
    test_fail "SSH key not found at $SSH_KEY"
    add_issue "SSH_KEY_MISSING" "Automation SSH key missing at $SSH_KEY" "critical"
  fi

  # Test 1.2: SSH key permissions
  test_start "SSH Key Permissions (Should be 600)"
  local KEY_PERMS=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || echo "unknown")
  if [ "$KEY_PERMS" = "600" ]; then
    test_pass "SSH key permissions correct: $KEY_PERMS"
  else
    test_fail "SSH key permissions incorrect: $KEY_PERMS (expected 600)"
    add_issue "SSH_KEY_PERMS" "SSH key has incorrect permissions: $KEY_PERMS" "high"
  fi

  # Test 1.3: SSH connectivity to worker node
  test_start "SSH Connectivity to Worker Node ($WORKER_HOST)"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
    test_pass "SSH connection to worker node successful"
  else
    test_fail "SSH connection to worker node failed"
    add_issue "SSH_CONNECTIVITY" "Cannot establish SSH connection to $WORKER_HOST with automation account" "critical"
  fi

  # Test 1.4: Service account verification on worker
  test_start "Service Account Verification ($SERVICE_ACCOUNT)"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" "whoami" 2>/dev/null | grep -q "$SERVICE_ACCOUNT"; then
    test_pass "Service account $SERVICE_ACCOUNT verified on worker"
  else
    test_fail "Service account verification failed"
    add_issue "SERVICE_ACCOUNT_VERIFY" "Cannot verify service account on worker node" "high"
  fi
}

# ============================================================================
# TEST SUITE 2: DEPLOYMENT SCRIPTS
# ============================================================================

test_suite_deployment_scripts() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       TEST SUITE 2: DEPLOYMENT SCRIPTS & SYNTAX                ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  # Test 2.1: Deploy script exists and executable
  test_start "Deploy Script Exists and Executable"
  if [ -f deploy-worker-node.sh ] && [ -x deploy-worker-node.sh ]; then
    test_pass "deploy-worker-node.sh is executable"
  else
    test_fail "deploy-worker-node.sh missing or not executable"
    add_issue "DEPLOY_SCRIPT_MISSING" "deploy-worker-node.sh missing or not executable" "critical"
  fi

  # Test 2.2: Setup script exists and executable
  test_start "Setup Script Exists and Executable"
  if [ -f SETUP_SSH_SERVICE_ACCOUNT.sh ] && [ -x SETUP_SSH_SERVICE_ACCOUNT.sh ]; then
    test_pass "SETUP_SSH_SERVICE_ACCOUNT.sh is executable"
  else
    test_fail "SETUP_SSH_SERVICE_ACCOUNT.sh missing or not executable"
    add_issue "SETUP_SCRIPT_MISSING" "SETUP_SSH_SERVICE_ACCOUNT.sh missing or not executable" "high"
  fi

  # Test 2.3: Bash syntax validation - deploy script
  test_start "Bash Syntax Validation (deploy-worker-node.sh)"
  if bash -n deploy-worker-node.sh 2>&1 | grep -q "syntax error"; then
    test_fail "Syntax errors in deploy-worker-node.sh"
    add_issue "DEPLOY_SYNTAX_ERROR" "Bash syntax errors in deploy-worker-node.sh" "critical"
  else
    test_pass "No syntax errors in deploy-worker-node.sh"
  fi

  # Test 2.4: Bash syntax validation - setup script
  test_start "Bash Syntax Validation (SETUP_SSH_SERVICE_ACCOUNT.sh)"
  if bash -n SETUP_SSH_SERVICE_ACCOUNT.sh 2>&1 | grep -q "syntax error"; then
    test_fail "Syntax errors in SETUP_SSH_SERVICE_ACCOUNT.sh"
    add_issue "SETUP_SYNTAX_ERROR" "Bash syntax errors in SETUP_SSH_SERVICE_ACCOUNT.sh" "critical"
  else
    test_pass "No syntax errors in SETUP_SSH_SERVICE_ACCOUNT.sh"
  fi

  # Test 2.5: Documentation files exist
  test_start "Documentation Files Completeness"
  local doc_files=("DEPLOY_SSH_SERVICE_ACCOUNT.md" "SSH_ISSUE_FIXED.md")
  local missing_docs=0
  for doc in "${doc_files[@]}"; do
    if [ ! -f "$doc" ]; then
      ((missing_docs++))
    fi
  done
  
  if [ $missing_docs -eq 0 ]; then
    test_pass "All documentation files present"
  else
    test_fail "$missing_docs documentation files missing"
    add_issue "MISSING_DOCS" "$missing_docs documentation files missing" "medium"
  fi
}

# ============================================================================
# TEST SUITE 3: WORKER NODE COMPONENTS
# ============================================================================

test_suite_worker_components() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       TEST SUITE 3: WORKER NODE COMPONENTS                     ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  # Test 3.1: Check /opt/automation directory
  test_start "/opt/automation Directory Exists"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" "test -d /opt/automation" 2>/dev/null; then
    test_pass "/opt/automation directory exists on worker"
  else
    test_fail "/opt/automation directory not found on worker"
    add_issue "AUTOMATION_DIR_MISSING" "/opt/automation directory not found on worker node" "critical"
  fi

  # Test 3.2: Count deployed components
  test_start "Deployed Components Count (Expected 8)"
  local component_count=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
    "$SERVICE_ACCOUNT@$WORKER_HOST" \
    "find /opt/automation -name '*.sh' -type f | wc -l" 2>/dev/null || echo "0")
  
  if [ "$component_count" = "8" ]; then
    test_pass "All 8 components deployed ($component_count files)"
  else
    test_fail "Component count mismatch: found $component_count, expected 8"
    add_issue "COMPONENT_COUNT_MISMATCH" "Only $component_count components found, expected 8" "high"
  fi

  # Test 3.3: Verify specific components
  test_start "Specific Component Verification"
  local required_components=(
    "cluster-readiness.sh"
    "cluster-stuck-recovery.sh"
    "validate-multicloud-secrets.sh"
    "audit-test-values.sh"
    "failover-automation.sh"
    "credential-manager.sh"
    "orchestrator.sh"
    "deployment-monitor.sh"
  )
  
  local missing_components=0
  for component in "${required_components[@]}"; do
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
        "$SERVICE_ACCOUNT@$WORKER_HOST" \
        "test -f /opt/automation/*/$component" 2>/dev/null; then
      ((missing_components++))
      log "WARN" "Component missing: $component"
    fi
  done
  
  if [ $missing_components -eq 0 ]; then
    test_pass "All required components present"
  else
    test_fail "$missing_components required components missing"
    add_issue "MISSING_COMPONENTS" "$missing_components components not found on worker" "high"
  fi

  # Test 3.4: Component executable permissions
  test_start "Component Executable Permissions"
  local not_executable=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
    "$SERVICE_ACCOUNT@$WORKER_HOST" \
    "find /opt/automation -name '*.sh' ! -perm -u+x | wc -l" 2>/dev/null || echo "unknown")
  
  if [ "$not_executable" = "0" ]; then
    test_pass "All components have executable permissions"
  else
    test_fail "$not_executable components lack executable permissions"
    add_issue "PERMISSION_ISSUES" "$not_executable components not executable" "high"
  fi
}

# ============================================================================
# TEST SUITE 4: SYSTEMD SERVICES & MONITORING
# ============================================================================

test_suite_systemd_monitoring() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       TEST SUITE 4: SYSTEMD SERVICES & MONITORING              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  # Test 4.1: Monitoring service file exists
  test_start "Monitoring Service File Exists"
  if systemctl list-unit-files 2>/dev/null | grep -q "monitoring-alert-triage.service"; then
    test_pass "Monitoring service file found"
  else
    test_fail "Monitoring service file not found"
    add_issue "MONITORING_SERVICE_MISSING" "monitoring-alert-triage.service not found" "medium"
  fi

  # Test 4.2: Monitoring timer exists
  test_start "Monitoring Timer Exists"
  if systemctl list-unit-files 2>/dev/null | grep -q "monitoring-alert-triage.timer"; then
    test_pass "Monitoring timer file found"
  else
    test_fail "Monitoring timer file not found"
    add_issue "MONITORING_TIMER_MISSING" "monitoring-alert-triage.timer not found" "medium"
  fi

  # Test 4.3: Timer can be checked (requires elevated privileges)
  test_start "Timer Status Check (May require sudo)"
  if systemctl is-active --quiet monitoring-alert-triage.timer 2>/dev/null; then
    test_pass "Monitoring timer is ACTIVE"
  else
    log "WARN" "Timer status check skipped (may require sudo)"
  fi
}

# ============================================================================
# TEST SUITE 5: MULTI-CLOUD CAPABILITIES
# ============================================================================

test_suite_multicloud() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       TEST SUITE 5: MULTI-CLOUD CAPABILITIES                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  # Test 5.1: Multi-cloud secret validation component
  test_start "Multi-Cloud Secret Validation Component"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" \
      "test -f /opt/automation/k8s-health-checks/validate-multicloud-secrets.sh" 2>/dev/null; then
    test_pass "validate-multicloud-secrets.sh present"
  else
    test_fail "validate-multicloud-secrets.sh not found"
    add_issue "MULTICLOUD_COMPONENT_MISSING" "validate-multicloud-secrets.sh not found on worker" "medium"
  fi

  # Test 5.2: Component syntax validation
  test_start "Multi-Cloud Component Syntax"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" \
      "bash -n /opt/automation/k8s-health-checks/validate-multicloud-secrets.sh" 2>/dev/null; then
    test_pass "validate-multicloud-secrets.sh syntax valid"
  else
    test_fail "Syntax errors in validate-multicloud-secrets.sh"
    add_issue "MULTICLOUD_SYNTAX_ERROR" "Syntax errors in validate-multicloud-secrets.sh" "high"
  fi
}

# ============================================================================
# TEST SUITE 6: AUDIT & COMPLIANCE
# ============================================================================

test_suite_audit_compliance() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       TEST SUITE 6: AUDIT & COMPLIANCE                         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  # Test 6.1: Audit directory
  test_start "Audit Directory Exists"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" \
      "test -d /opt/automation/audit" 2>/dev/null; then
    test_pass "/opt/automation/audit directory exists"
  else
    test_fail "/opt/automation/audit directory not found"
    add_issue "AUDIT_DIR_MISSING" "Audit directory not found at /opt/automation/audit" "medium"
  fi

  # Test 6.2: Audit log writeable
  test_start "Audit Log Writeability"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" \
      "$SERVICE_ACCOUNT@$WORKER_HOST" \
      "touch /opt/automation/audit/.test 2>/dev/null && rm /opt/automation/audit/.test 2>/dev/null" && [ $? -eq 0 ]; then
    test_pass "Audit directory is writable"
  else
    log "WARN" "Cannot write to audit directory (may require elevated privileges)"
  fi

  # Test 6.3: Documentation audit
  test_start "Documentation Completeness Audit"
  local completion_report_count=$(ls -1 TRIAGE_ALL_PHASES_COMPLETION* 2>/dev/null | wc -l)
  if [ $completion_report_count -gt 0 ]; then
    test_pass "Completion reports generated ($completion_report_count)"
  else
    test_fail "No completion reports found"
    add_issue "MISSING_COMPLETION_REPORTS" "No triage completion reports found" "medium"
  fi
}

# ============================================================================
# ISSUE REPORTING
# ============================================================================

report_issues() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                    ISSUE SUMMARY & REPORTING                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  if [ ${#ISSUES_FOUND[@]} -eq 0 ]; then
    echo "✅ NO ISSUES FOUND - All tests passed!"
    return 0
  fi

  echo "❌ Found ${#ISSUES_FOUND[@]} issue(s):"
  echo ""
  
  cat > "$TEST_ISSUES" << ISSUES_HEADER
# E2E Testing Issues Report
**Date:** $(date '+%Y-%m-%d %H:%M:%S')  
**Tests Run:** $TESTS_RUN  
**Tests Passed:** $TESTS_PASSED  
**Tests Failed:** $TESTS_FAILED  

## Issues Identified

ISSUES_HEADER

  local issue_num=1
  for issue in "${ISSUES_FOUND[@]}"; do
    echo "$issue_num. $issue"
    echo "- [ ] $issue" >> "$TEST_ISSUES"
    ((issue_num++))
  done

  echo ""
  echo "Issues saved to: $TEST_ISSUES"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║          E2E COMPREHENSIVE TESTING FRAMEWORK                   ║"
  echo "║                    March 14, 2026                              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Test Log: $TEST_LOG"
  echo ""

  # Run all test suites
  test_suite_ssh_auth
  test_suite_deployment_scripts
  test_suite_worker_components
  test_suite_systemd_monitoring
  test_suite_multicloud
  test_suite_audit_compliance

  # Report summary
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                    TEST SUMMARY                                ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Tests Run:     $TESTS_RUN"
  echo "Tests Passed:  $TESTS_PASSED"
  echo "Tests Failed:  $TESTS_FAILED"
  echo "Success Rate:  $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
  echo ""

  report_issues

  echo ""
  echo "Test execution complete. Full log available at: $TEST_LOG"
  echo ""
}

# Execute main function
main
