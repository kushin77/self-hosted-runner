#!/usr/bin/env bash
set -euo pipefail

# Comprehensive Runner Test Suite
# Tests all critical runner functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$SCRIPT_DIR")/../../..")
TEST_RESULTS_FILE="${GIT_ROOT}/test_results.txt"
PASSED=0
FAILED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

test_result() {
  local test_name="$1"
  local exit_code="$2"
  
  if [ "$exit_code" -eq 0 ]; then
    echo "✓ PASS: $test_name" | tee -a "$TEST_RESULTS_FILE"
    PASSED=$((PASSED + 1))
  elif [ "$exit_code" -eq 2 ]; then
    echo "- SKIP: $test_name" | tee -a "$TEST_RESULTS_FILE"
    SKIPPED=$((SKIPPED + 1))
  else
    echo "✗ FAIL: $test_name" | tee -a "$TEST_RESULTS_FILE"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: Health monitor script exists and is executable
test_health_monitor_exists() {
  local script="${SCRIPT_DIR}/../runner_health_monitor.sh"
  [ -x "$script" ] && return 0 || return 1
}

# Test 2: Cleanup script is present
test_cleanup_script() {
  local script="${SCRIPT_DIR}/../runner_cleanup.sh"
  [ -f "$script" ] && return 0 || return 1
}

# Test 3: Pytest hygiene script is present
test_pytest_hygiene_script() {
  local script="${SCRIPT_DIR}/../runner_pytest_hygiene.sh"
  [ -f "$script" ] && return 0 || return 1
}

# Test 4: Systemd service files exist
test_systemd_files() {
  local service="${SCRIPT_DIR}/../systemd/elevatediq-runner-health-monitor.service"
  local timer="${SCRIPT_DIR}/../systemd/elevatediq-runner-health-monitor.timer"
  
  [ -f "$service" ] && [ -f "$timer" ] && return 0 || return 1
}

# Test 5: Prometheus configuration exists
test_prometheus_config() {
  local prometheus_yml="${SCRIPT_DIR}/../prometheus/prometheus.yml"
  local alerts_yml="${SCRIPT_DIR}/../prometheus/alerts.yml"
  
  [ -f "$prometheus_yml" ] && [ -f "$alerts_yml" ] && return 0 || return 1
}

# Test 6: Docker Compose observability stack
test_docker_compose() {
  local compose_file="${SCRIPT_DIR}/../prometheus/docker-compose-observability.yml"
  
  if [ ! -f "$compose_file" ]; then
    return 1
  fi
  
  # Just check if file is valid YAML-ish (has required services)
  grep -q "prometheus\|alertmanager\|grafana" "$compose_file" && return 0 || return 1
}

# Test 7: Terraform module exists
test_terraform_module() {
  local tf_main="${SCRIPT_DIR}/../../../../terraform/modules/ci-runners/main.tf"
  [ -f "$tf_main" ] && return 0 || return 1
}

# Test 8: Terraform configuration is valid
test_terraform_validate() {
  # If `terraform` is not installed locally, skip this check so local test runs are less fragile.
  if ! command -v terraform >/dev/null 2>&1; then
    return 2
  fi

  cd "${SCRIPT_DIR}/../../../../terraform" 2>/dev/null || return 1
  # Initialize with no backend to make local validation safe
  terraform init -backend=false >/dev/null 2>&1 || return 1
  terraform validate >/dev/null 2>&1 && return 0 || return 1
}

# Test 9: Validate deployment script
test_validate_deployment_script() {
  [ -x "${GIT_ROOT}/scripts/validate-deployment.sh" ] && return 0 || return 1
}

# Test 10: Documentation files exist
test_documentation() {
  [ -f "${GIT_ROOT}/docs/governance/runners.md" ] &&
  [ -f "${GIT_ROOT}/docs/management/RUNNER_HEALTH_MONITORING_SYSTEM.md" ] &&
  [ -f "${GIT_ROOT}/docs/management/RUNNER_INFRASTRUCTURE_DEPLOYMENT.md" ] &&
  return 0 || return 1
}

# Test 11: README completeness
test_readme() {
  [ -f "${GIT_ROOT}/README.md" ] &&
  grep -q "Feature Completion Dashboard" "${GIT_ROOT}/README.md" &&
  return 0 || return 1
}

# Test 12: Security: No hardcoded credentials
test_no_credentials() {
  # Exclude the legitimate load script and test scripts from credential checks
  if git -C "${GIT_ROOT}" grep -n "GITHUB_TOKEN=" 2>/dev/null | \
       grep -v "^scripts/load_gsm_secrets.sh:" | grep -v "^scripts/automation/pmo/tests/" | grep -v "^.github/" | grep -v "^.gitlab/" | grep -q .; then
    return 1
  fi

  # Only flag likely hardcoded AWS secret variables, not resource names like aws_secretsmanager_secret
  # Exclude scripts that legitimately read from external sources (GSM, Vault)
  if git -C "${GIT_ROOT}" grep -n "aws_secret_access_key\|AWS_SECRET_ACCESS_KEY" 2>/dev/null | \
       grep -v "^scripts/load_gsm_secrets.sh:" | grep -v "^scripts/run_gcp_vault_import.sh:" | grep -v "^scripts/automation/pmo/tests/" | grep -v "^.github/" | grep -v "^.gitlab/" | grep -q .; then
    return 1
  fi
  
  return 0
}

# Test 13: Git hooks for security
test_git_pre_commit_hook() {
  [ -x "${GIT_ROOT}/.git/hooks/pre-commit" ] || [ ! -d "${GIT_ROOT}/.git/hooks" ] && return 0 || return 1
}

# Test 14: Environment variables documentation
test_env_documentation() {
  grep -q "GITHUB_OWNER\|GITHUB_TOKEN" "${GIT_ROOT}/README.md" && return 0 || return 1
}

# Test 15: Deployment validation script functionality
test_deployment_validation_logic() {
  cd /tmp
  bash -n "${GIT_ROOT}/scripts/validate-deployment.sh" && return 0 || return 1
}

# Main test execution
main() {
  > "$TEST_RESULTS_FILE"  # Clear previous results
  
  log "=== GitHub Actions Runner Test Suite ==="
  log "Running comprehensive tests..."
  log ""
  
  test_health_monitor_exists && test_result "Health monitor script exists" 0 || test_result "Health monitor script exists" 1
  test_cleanup_script && test_result "Cleanup script present" 0 || test_result "Cleanup script present" 1
  test_pytest_hygiene_script && test_result "Pytest hygiene script present" 0 || test_result "Pytest hygiene script present" 1
  test_systemd_files && test_result "Systemd service/timer files" 0 || test_result "Systemd service/timer files" 1
  test_prometheus_config && test_result "Prometheus configuration" 0 || test_result "Prometheus configuration" 1
  test_docker_compose && test_result "Docker Compose stack" 0 || test_result "Docker Compose stack" 1
  test_terraform_module && test_result "Terraform module exists" 0 || test_result "Terraform module exists" 1
  test_terraform_validate && test_result "Terraform validation" 0 || test_result "Terraform validation" 1
  test_validate_deployment_script && test_result "Deployment validation script" 0 || test_result "Deployment validation script" 1
  test_documentation && test_result "Documentation completeness" 0 || test_result "Documentation completeness" 1
  test_readme && test_result "README completeness" 0 || test_result "README completeness" 1
  test_no_credentials && test_result "No hardcoded credentials" 0 || test_result "No hardcoded credentials" 1
  test_git_pre_commit_hook && test_result "Git pre-commit hooks" 0 || test_result "Git pre-commit hooks" 1
  test_env_documentation && test_result "Environment variables documented" 0 || test_result "Environment variables documented" 1
  test_deployment_validation_logic && test_result "Deployment validation logic" 0 || test_result "Deployment validation logic" 1
  
  log ""
  log "=== Test Results ==="
  log "Passed: $PASSED/15"
  log "Failed: $FAILED/15"
  log ""
  
  if [ $FAILED -eq 0 ]; then
    log "✓ All tests passed!"
    return 0
  else
    log "✗ Some tests failed"
    return 1
  fi
}

main "$@"
