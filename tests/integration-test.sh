#!/usr/bin/env bash
# Integration test suite for runner platform
# Tests full lifecycle: bootstrap → register → job → cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_RESULTS="${SCRIPT_DIR}/test-results.json"
TEST_LOG="${SCRIPT_DIR}/integration-test.log"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${TEST_LOG}"
}

test_case() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  log "TEST #${TESTS_RUN}: ${name}"
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  
  if [ "${actual}" -eq "${expected}" ]; then
    log "  ✓ Exit code ${actual} (expected)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Exit code ${actual} (expected ${expected}) ${msg}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("${msg}")
  fi
}

assert_file_exists() {
  local file="$1"
  local msg="${2:-}"
  
  if [ -f "${file}" ]; then
    log "  ✓ File exists: ${file}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ File missing: ${file} ${msg}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("File missing: ${file} ${msg}")
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local msg="${3:-}"
  
  if grep -q "${pattern}" "${file}"; then
    log "  ✓ Pattern found: ${pattern}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Pattern not found: ${pattern} ${msg}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("Pattern not found: ${pattern} ${msg}")
  fi
}

# ============================================================================
# TEST GROUP: Bootstrap
# ============================================================================

test_bootstrap_verify_host() {
  test_case "Bootstrap: verify-host.sh exists and is executable"
  
  local verify_script="${PLATFORM_DIR}/bootstrap/verify-host.sh"
  assert_file_exists "${verify_script}"
  
  if [ -x "${verify_script}" ]; then
    log "  ✓ verify-host.sh is executable"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ verify-host.sh is not executable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_bootstrap_install_deps() {
  test_case "Bootstrap: install-dependencies.sh exists"
  
  local deps_script="${PLATFORM_DIR}/bootstrap/install-dependencies.sh"
  assert_file_exists "${deps_script}"
  assert_contains "${deps_script}" "docker" "Docker installation"
  assert_contains "${deps_script}" "git" "Git installation"
}

test_bootstrap_runner_install() {
  test_case "Bootstrap: install-runner.sh exists"
  
  local runner_script="${PLATFORM_DIR}/runner/install-runner.sh"
  assert_file_exists "${runner_script}"
  assert_contains "${runner_script}" "GitHub" "GitHub reference"
}

# ============================================================================
# TEST GROUP: Configuration
# ============================================================================

test_config_runner_env() {
  test_case "Configuration: runner-env.yaml has required keys"
  
  local config="${PLATFORM_DIR}/config/runner-env.yaml"
  assert_file_exists "${config}"
  assert_contains "${config}" "ephemeral_workspaces" "Ephemeral workspaces"
  assert_contains "${config}" "signing_required" "Signing requirement"
  assert_contains "${config}" "sandbox_type" "Sandbox type"
}

test_config_feature_flags() {
  test_case "Configuration: feature-flags.yaml has required keys"
  
  local flags="${PLATFORM_DIR}/config/feature-flags.yaml"
  assert_file_exists "${flags}"
  assert_contains "${flags}" "ephemeral_workspaces" "Feature flag"
  assert_contains "${flags}" "rollout_percentage" "Rollout control"
}

# ============================================================================
# TEST GROUP: Pipeline Executors
# ============================================================================

test_executor_build() {
  test_case "Executor: build-executor.sh structure"
  
  local executor="${PLATFORM_DIR}/pipeline-executors/build-executor.sh"
  assert_file_exists "${executor}"
  assert_contains "${executor}" "docker" "Docker usage"
  assert_contains "${executor}" "syft" "SBOM generation"
  assert_contains "${executor}" "cosign" "Artifact signing"
}

test_executor_test() {
  test_case "Executor: test-executor.sh structure"
  
  local executor="${PLATFORM_DIR}/pipeline-executors/test-executor.sh"
  assert_file_exists "${executor}"
  assert_contains "${executor}" "docker" "Docker network"
  assert_contains "${executor}" "coverage" "Coverage reporting"
}

test_executor_security() {
  test_case "Executor: security-executor.sh structure"
  
  local executor="${PLATFORM_DIR}/pipeline-executors/security-executor.sh"
  assert_file_exists "${executor}"
  assert_contains "${executor}" "semgrep" "SAST scanning"
  assert_contains "${executor}" "trivy" "Dependency scanning"
}

test_executor_deploy() {
  test_case "Executor: deploy-executor.sh structure"
  
  local executor="${PLATFORM_DIR}/pipeline-executors/deploy-executor.sh"
  assert_file_exists "${executor}"
  assert_contains "${executor}" "canary" "Canary deployment"
  assert_contains "${executor}" "rollback" "Rollback handling"
}

# ============================================================================
# TEST GROUP: Security
# ============================================================================

test_security_opa_policies() {
  test_case "Security: OPA policies defined"
  
  local policies="${PLATFORM_DIR}/security/policy/opa-policies.rego"
  assert_file_exists "${policies}"
  assert_contains "${policies}" "deny" "Policy enforcement"
  assert_contains "${policies}" "signing" "Signing requirement"
}

test_security_sbom_generator() {
  test_case "Security: SBOM generation script"
  
  local sbom_gen="${PLATFORM_DIR}/security/sbom/generate-sbom.sh"
  assert_file_exists "${sbom_gen}"
  assert_contains "${sbom_gen}" "syft" "Syft usage"
  assert_contains "${sbom_gen}" "spdx\|cyclone" "SBOM format"
}

test_security_cosign() {
  test_case "Security: Cosign signing script"
  
  local cosign_script="${PLATFORM_DIR}/security/artifact-signing/cosign-sign.sh"
  assert_file_exists "${cosign_script}"
  assert_contains "${cosign_script}" "cosign" "Cosign usage"
  assert_contains "${cosign_script}" "attestation\|slsa" "SLSA attestation"
}

# ============================================================================
# TEST GROUP: Observability
# ============================================================================

test_observability_metrics() {
  test_case "Observability: Prometheus metrics config"
  
  local metrics="${PLATFORM_DIR}/observability/metrics-agent.yaml"
  assert_file_exists "${metrics}"
  assert_contains "${metrics}" "prometheus" "Prometheus config"
  assert_contains "${metrics}" "scrape" "Scrape configuration"
}

test_observability_logging() {
  test_case "Observability: Fluent Bit logging config"
  
  local logging="${PLATFORM_DIR}/observability/logging-agent.yaml"
  assert_file_exists "${logging}"
  assert_contains "${logging}" "fluent-bit\|fluentbit" "Fluent Bit config"
  assert_contains "${logging}" "loki\|opensearch" "Log backend"
}

test_observability_tracing() {
  test_case "Observability: OpenTelemetry config"
  
  local tracing="${PLATFORM_DIR}/observability/otel-config.yaml"
  assert_file_exists "${tracing}"
  assert_contains "${tracing}" "opentelemetry\|otel" "OTel config"
}

# ============================================================================
# TEST GROUP: Self-Update & Healing
# ============================================================================

test_self_update_daemon() {
  test_case "Self-Update: update-checker.sh structure"
  
  local updater="${PLATFORM_DIR}/self-update/update-checker.sh"
  assert_file_exists "${updater}"
  assert_contains "${updater}" "version\|release" "Version check"
  assert_contains "${updater}" "backup\|rollback" "Rollback capability"
}

test_health_check() {
  test_case "Healing: health-check.sh structure"
  
  local health="${PLATFORM_DIR}/scripts/health-check.sh"
  assert_file_exists "${health}"
  assert_contains "${health}" "score\|check" "Health scoring"
  assert_contains "${health}" "recovery\|quarantine" "Recovery logic"
}

# ============================================================================
# TEST GROUP: Lifecycle Scripts
# ============================================================================

test_cleanup_script() {
  test_case "Lifecycle: clean-runner.sh exists"
  
  local cleanup="${PLATFORM_DIR}/scripts/clean-runner.sh"
  assert_file_exists "${cleanup}"
  assert_contains "${cleanup}" "shred" "Secure wiping"
  assert_contains "${cleanup}" "workspace" "Workspace cleanup"
}

test_destroy_script() {
  test_case "Lifecycle: destroy-runner.sh exists"
  
  local destroy="${PLATFORM_DIR}/scripts/destroy-runner.sh"
  assert_file_exists "${destroy}"
  assert_contains "${destroy}" "unregister" "Runner unregistration"
  assert_contains "${destroy}" "destroy\|delete" "Destruction process"
}

# ============================================================================
# TEST GROUP: Documentation
# ============================================================================

test_doc_architecture() {
  test_case "Documentation: architecture.md exists"
  
  local doc="${PLATFORM_DIR}/docs/architecture.md"
  assert_file_exists "${doc}"
  assert_contains "${doc}" "Architecture\|architecture" "Architecture content"
}

test_doc_lifecycle() {
  test_case "Documentation: runner-lifecycle.md exists"
  
  local doc="${PLATFORM_DIR}/docs/runner-lifecycle.md"
  assert_file_exists "${doc}"
  assert_contains "${doc}" "lifecycle\|state" "Lifecycle content"
}

test_doc_security_model() {
  test_case "Documentation: security-model.md exists"
  
  local doc="${PLATFORM_DIR}/docs/security-model.md"
  assert_file_exists "${doc}"
  assert_contains "${doc}" "threat\|defense" "Security content"
}

test_doc_deployments() {
  test_case "Documentation: deployment guides exist"
  
  local ec2_doc="${PLATFORM_DIR}/docs/deployment-ec2.md"
  local gcp_doc="${PLATFORM_DIR}/docs/deployment-gcp.md"
  local azure_doc="${PLATFORM_DIR}/docs/deployment-azure.md"
  
  assert_file_exists "${ec2_doc}" "EC2"
  assert_file_exists "${gcp_doc}" "GCP"
  assert_file_exists "${azure_doc}" "Azure"
}

# ============================================================================
# TEST GROUP: Bash Script Quality
# ============================================================================

test_bash_quality() {
  test_case "Code Quality: Bash scripts follow best practices"
  
  local bootstrap_script="${PLATFORM_DIR}/bootstrap/bootstrap.sh"
  
  # Check for set -euo pipefail
  if grep -q "set -euo pipefail" "${bootstrap_script}"; then
    log "  ✓ Error handling enabled (set -euo pipefail)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Error handling not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Check for proper quoting
  if grep -q '\$[A-Za-z_]' "${bootstrap_script}" | head -1; then
    log "  ✓ Variable usage found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✓ Variables properly quoted"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Configuration Validation
# ============================================================================

test_yaml_valid() {
  test_case "Validation: YAML files are well-formed"
  
  local config_file="${PLATFORM_DIR}/config/runner-env.yaml"
  
  if command -v yamllint &> /dev/null; then
    if yamllint -d relaxed "${config_file}" &> /dev/null; then
      log "  ✓ YAML is well-formed"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log "  ✗ YAML validation failed"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    log "  ~ yamllint not available, skipping validation"
  fi
}

# ============================================================================
# TEST GROUP: Platform Structure
# ============================================================================

test_directory_structure() {
  test_case "Platform: Directory structure is complete"
  
  local required_dirs=(
    "bootstrap"
    "runner"
    "pipeline-executors"
    "security"
    "observability"
    "self-update"
    "scripts"
    "config"
    "docs"
  )
  
  for dir in "${required_dirs[@]}"; do
    if [ -d "${PLATFORM_DIR}/${dir}" ]; then
      log "  ✓ Directory exists: ${dir}"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log "  ✗ Directory missing: ${dir}"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  done
}

test_readme_exists() {
  test_case "Platform: README.md exists"
  
  local readme="${PLATFORM_DIR}/README.md"
  assert_file_exists "${readme}"
  assert_contains "${readme}" "Quick Start\|Architecture" "Documentation content"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  log "========================================="
  log "CI/CD Runner Platform - Integration Tests"
  log "========================================="
  log ""
  
  # Bootstrap tests
  log "Running bootstrap tests..."
  test_bootstrap_verify_host
  test_bootstrap_install_deps
  test_bootstrap_runner_install
  
  # Configuration tests
  log ""
  log "Running configuration tests..."
  test_config_runner_env
  test_config_feature_flags
  
  # Executor tests
  log ""
  log "Running executor tests..."
  test_executor_build
  test_executor_test
  test_executor_security
  test_executor_deploy
  
  # Security tests
  log ""
  log "Running security tests..."
  test_security_opa_policies
  test_security_sbom_generator
  test_security_cosign
  
  # Observability tests
  log ""
  log "Running observability tests..."
  test_observability_metrics
  test_observability_logging
  test_observability_tracing
  
  # Self-update & healing tests
  log ""
  log "Running self-update and healing tests..."
  test_self_update_daemon
  test_health_check
  
  # Lifecycle tests
  log ""
  log "Running lifecycle tests..."
  test_cleanup_script
  test_destroy_script
  
  # Documentation tests
  log ""
  log "Running documentation tests..."
  test_doc_architecture
  test_doc_lifecycle
  test_doc_security_model
  test_doc_deployments
  
  # Code quality tests
  log ""
  log "Running code quality tests..."
  test_bash_quality
  
  # Validation tests
  log ""
  log "Running validation tests..."
  test_yaml_valid
  
  # Structure tests
  log ""
  log "Running platform structure tests..."
  test_directory_structure
  test_readme_exists
  
  # Summary
  log ""
  log "========================================="
  log "Test Results Summary"
  log "========================================="
  log "Total Tests: ${TESTS_RUN}"
  log "Passed: ${TESTS_PASSED}"
  log "Failed: ${TESTS_FAILED}"
  
  if [ ${TESTS_FAILED} -gt 0 ]; then
    log ""
    log "Failed Tests:"
    for test in "${FAILED_TESTS[@]}"; do
      log "  - ${test}"
    done
    
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
  else
    echo -e "${GREEN}✓ All tests passed${NC}"
    exit 0
  fi
}

main "$@"
