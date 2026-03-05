#!/usr/bin/env bash
# Master test runner orchestrating all integration, security, and cloud deployment tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SUMMARY="${SCRIPT_DIR}/test-summary.json"
TEST_LOG="${SCRIPT_DIR}/test-runner.log"

# Load credentials file if present (created by prepare-creds.sh or CI)
if [ -f "${SCRIPT_DIR}/cloud-creds.env" ]; then
  # shellcheck disable=SC1090
  log "Loading cloud credentials from ${SCRIPT_DIR}/cloud-creds.env"
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/cloud-creds.env"
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_TESTS=()

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${TEST_LOG}"
}

print_header() {
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
}

run_test_suite() {
  local suite_name="$1"
  local test_script="$2"
  local skip_flag="${3:-false}"
  
  TOTAL_SUITES=$((TOTAL_SUITES + 1))
  
  log "Running test suite: ${suite_name}"
  
  if [ "${skip_flag}" == "true" ]; then
    log "⊘ ${suite_name} skipped (dependencies not met)"
    return 0
  fi
  
  if [ ! -f "${test_script}" ]; then
    log "✗ ${suite_name} script not found: ${test_script}"
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_TESTS+=("${suite_name}: Script not found")
    return 1
  fi
  
  if ! bash "${test_script}" 2>&1 | tee -a "${TEST_LOG}"; then
    log "✗ ${suite_name} failed"
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_TESTS+=("${suite_name}")
    return 1
  else
    log "✓ ${suite_name} passed"
    PASSED_SUITES=$((PASSED_SUITES + 1))
    return 0
  fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  print_header "CI/CD Runner Platform - Complete Test Suite"
  
  log "Platform root: $(dirname "${SCRIPT_DIR}")"
  log "Test directory: ${SCRIPT_DIR}"
  log "Test started at: $(date)"
  
  # Parse arguments
  local run_integration=true
  local run_security=true
  local run_cloud_ec2=false
  local run_cloud_gcp=false
  local run_cloud_azure=false
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --only-integration)
        run_security=false
        run_cloud_ec2=false
        run_cloud_gcp=false
        run_cloud_azure=false
        shift
        ;;
      --only-security)
        run_integration=false
        run_cloud_ec2=false
        run_cloud_gcp=false
        run_cloud_azure=false
        shift
        ;;
      --with-ec2)
        run_cloud_ec2=true
        shift
        ;;
      --with-gcp)
        run_cloud_gcp=true
        shift
        ;;
      --with-azure)
        run_cloud_azure=true
        shift
        ;;
      --all)
        run_integration=true
        run_security=true
        run_cloud_ec2=true
        run_cloud_gcp=true
        run_cloud_azure=true
        shift
        ;;
      *)
        log "Unknown option: $1"
        shift
        ;;
    esac
  done
  
  # ======================================================================
  # Run Integration Tests
  # ======================================================================
  
  if [ "${run_integration}" == "true" ]; then
    print_header "1. Platform Integration Tests"
    run_test_suite \
      "Integration Tests" \
      "${SCRIPT_DIR}/integration-test.sh"
  fi
  
  # ======================================================================
  # Run Security Tests
  # ======================================================================
  
  if [ "${run_security}" == "true" ]; then
    print_header "2. Security Tests"
    run_test_suite \
      "Security Tests" \
      "${SCRIPT_DIR}/security-test.sh"
  fi
  
  # ======================================================================
  # Run Cloud Deployment Tests
  # ======================================================================
  
  if [ "${run_cloud_ec2}" == "true" ]; then
    print_header "3. AWS EC2 Deployment Test"
    
    if [ -z "${AWS_REGION:-}" ]; then
      log "⊘ EC2 test skipped (AWS_REGION not set)"
      TOTAL_SUITES=$((TOTAL_SUITES + 1))
    else
      run_test_suite \
        "EC2 Deployment Test" \
        "${SCRIPT_DIR}/cloud-test-ec2.sh"
    fi
  fi
  
  if [ "${run_cloud_gcp}" == "true" ]; then
    print_header "4. GCP Deployment Test"
    
    if [ -z "${GCP_PROJECT:-}" ]; then
      log "⊘ GCP test skipped (GCP_PROJECT not set)"
      TOTAL_SUITES=$((TOTAL_SUITES + 1))
    else
      run_test_suite \
        "GCP Deployment Test" \
        "${SCRIPT_DIR}/cloud-test-gcp.sh"
    fi
  fi
  
  if [ "${run_cloud_azure}" == "true" ]; then
    print_header "5. Azure Deployment Test"
    
    if [ -z "${AZURE_SUBSCRIPTION:-}" ]; then
      log "⊘ Azure test skipped (AZURE_SUBSCRIPTION not set)"
      TOTAL_SUITES=$((TOTAL_SUITES + 1))
    else
      run_test_suite \
        "Azure Deployment Test" \
        "${SCRIPT_DIR}/cloud-test-azure.sh"
    fi
  fi
  
  # ======================================================================
  # Test Summary
  # ======================================================================
  
  print_header "Test Execution Summary"
  
  log "Total test suites: ${TOTAL_SUITES}"
  log "Passed: ${PASSED_SUITES}"
  log "Failed: ${FAILED_SUITES}"
  
  if [ ${FAILED_SUITES} -gt 0 ]; then
    log ""
    log "Failed test suites:"
    for test in "${FAILED_TESTS[@]}"; do
      log "  - ${test}"
    done
    
    echo -e "${RED}✗ Some test suites failed${NC}"
    echo ""
    log "Test execution FAILED"
    exit 1
  else
    echo -e "${GREEN}✓ All test suites passed${NC}"
    echo ""
    log "Test execution PASSED"
    
    # Write summary JSON
    cat > "${TEST_SUMMARY}" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "status": "success",
  "total_suites": ${TOTAL_SUITES},
  "passed_suites": ${PASSED_SUITES},
  "failed_suites": ${FAILED_SUITES},
  "tests": {
    "integration": $([ "${run_integration}" == "true" ] && echo "true" || echo "false"),
    "security": $([ "${run_security}" == "true" ] && echo "true" || echo "false"),
    "cloud_ec2": $([ "${run_cloud_ec2}" == "true" ] && echo "true" || echo "false"),
    "cloud_gcp": $([ "${run_cloud_gcp}" == "true" ] && echo "true" || echo "false"),
    "cloud_azure": $([ "${run_cloud_azure}" == "true" ] && echo "true" || echo "false")
  }
}
EOF
    
    exit 0
  fi
}

# Show usage
usage() {
  cat <<EOF
CI/CD Runner Platform - Test Suite Runner

Usage: $(basename "$0") [OPTIONS]

Options:
  --only-integration   Run only integration tests
  --only-security      Run only security tests
  --with-ec2          Include AWS EC2 deployment test
  --with-gcp          Include GCP deployment test
  --with-azure        Include Azure deployment test
  --all               Run all test suites (requires cloud credentials)
  
Examples:
  # Run integration and security tests
  $(basename "$0")
  
  # Run with EC2 deployment tests
  AWS_REGION=us-east-1 $(basename "$0") --with-ec2
  
  # Run all tests (requires AWS, GCP, Azure credentials)
  AWS_REGION=us-east-1 GCP_PROJECT=my-project AZURE_SUBSCRIPTION=xxx $(basename "$0") --all

Environment Variables:
  AWS_REGION          AWS region for EC2 tests (default: unset)
  GCP_PROJECT         GCP project ID for GCP tests (default: unset)
  AZURE_SUBSCRIPTION  Azure subscription ID for Azure tests (default: unset)
  GITHUB_TOKEN        GitHub token for runner registration (may be required)

Log Files:
  - Central log: ${TEST_LOG}
  - Integration test log: ${SCRIPT_DIR}/integration-test.log
  - Security test log: ${SCRIPT_DIR}/security-test.log
  - Cloud test logs: ${SCRIPT_DIR}/cloud-test-*.log
  - Test summary: ${TEST_SUMMARY}

EOF
}

# Entry point
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

main "$@"
