#!/usr/bin/env bash
# Security testing suite for runner platform
# Validates isolation, policy enforcement, and cryptographic signing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_LOG="${SCRIPT_DIR}/security-test.log"

TESTS_PASSED=0
TESTS_FAILED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${TEST_LOG}"
}

test_case() {
  log "TEST: $1"
}

# ============================================================================
# TEST GROUP: Container Isolation
# ============================================================================

test_executor_isolation() {
  test_case "Isolation: Build executor runs in isolated container"
  
  if grep -q "docker run.*--cap-drop=ALL" "${PLATFORM_DIR}/pipeline-executors/build-executor.sh"; then
    log "  ✓ Capabilities dropped"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Capabilities not dropped"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  if grep -q "security-opt no-new-privileges" "${PLATFORM_DIR}/pipeline-executors/build-executor.sh"; then
    log "  ✓ Privilege escalation disabled"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Privilege escalation controls missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_readonly_filesystem() {
  test_case "Isolation: Code mounted read-only in executor"
  
  if grep -q ":ro\|read-only" "${PLATFORM_DIR}/pipeline-executors/build-executor.sh"; then
    log "  ✓ Read-only volume for code"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Code volume not read-only"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_network_isolation() {
  test_case "Isolation: Test executor creates isolated networks"
  
  if grep -q "docker network\|--network" "${PLATFORM_DIR}/pipeline-executors/test-executor.sh"; then
    log "  ✓ Network isolation configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Network isolation missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Artifact Signing
# ============================================================================

test_cosign_signing() {
  test_case "Signing: Cosign configuration exists"
  
  if [ -f "${PLATFORM_DIR}/security/artifact-signing/cosign-sign.sh" ]; then
    if grep -q "cosign sign" "${PLATFORM_DIR}/security/artifact-signing/cosign-sign.sh"; then
      log "  ✓ Cosign signing implemented"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log "  ✗ Cosign signing not found"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    log "  ✗ Cosign script missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_slsa_attestations() {
  test_case "Signing: SLSA attestations supported"
  
  if grep -q "slsa\|attestation" "${PLATFORM_DIR}/security/artifact-signing/cosign-sign.sh"; then
    log "  ✓ SLSA attestations configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ SLSA attestations not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_keyless_oidc() {
  test_case "Signing: Keyless OIDC mode available"
  
  if grep -q "oidc\|keyless" "${PLATFORM_DIR}/security/artifact-signing/cosign-sign.sh"; then
    log "  ✓ Keyless OIDC available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Keyless mode not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: SBOM Generation
# ============================================================================

test_sbom_generation() {
  test_case "SBOM: Generation script implemented"
  
  if [ -f "${PLATFORM_DIR}/security/sbom/generate-sbom.sh" ]; then
    log "  ✓ SBOM generation script exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ SBOM generation missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_sbom_formats() {
  test_case "SBOM: Multiple formats supported"
  
  if grep -qi "spdx" "${PLATFORM_DIR}/security/sbom/generate-sbom.sh"; then
    log "  ✓ SPDX format supported"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ SPDX format not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  if grep -qi "cyclone" "${PLATFORM_DIR}/security/sbom/generate-sbom.sh"; then
    log "  ✓ CycloneDX format supported"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ CycloneDX format not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: OPA Policies
# ============================================================================

test_opa_policy_enforcement() {
  test_case "Policy: OPA policies defined"
  
  if [ -f "${PLATFORM_DIR}/security/policy/opa-policies.rego" ]; then
    if grep -q "deny" "${PLATFORM_DIR}/security/policy/opa-policies.rego"; then
      log "  ✓ OPA deny rules configured"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log "  ✗ OPA deny rules not found"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    log "  ✗ OPA policy file missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_signing_policy() {
  test_case "Policy: Signing enforcement in OPA"
  
  if grep -q "signing\|digest" "${PLATFORM_DIR}/security/policy/opa-policies.rego"; then
    log "  ✓ Signing enforcement policy exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Signing enforcement not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_container_policy() {
  test_case "Policy: Container security policies in OPA"
  
  if grep -q "privileged\|securityContext" "${PLATFORM_DIR}/security/policy/opa-policies.rego"; then
    log "  ✓ Container security policies exist"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Container security policies not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_compliance_policies() {
  test_case "Policy: Compliance enforcement (SOC2, PCI, HIPAA)"
  
  if grep -q "soc2\|pci\|hipaa" "${PLATFORM_DIR}/security/policy/opa-policies.rego"; then
    log "  ✓ Compliance policies configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Compliance policies not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Secret Handling
# ============================================================================

test_no_hardcoded_secrets() {
  test_case "Secrets: No hardcoded secrets in scripts"
  
  local found_secrets=0
  local script_files=(
    "bootstrap/bootstrap.sh"
    "runner/install-runner.sh"
    "pipeline-executors/build-executor.sh"
  )
  
  for script in "${script_files[@]}"; do
    if grep -iE "password|secret|token|key" "${PLATFORM_DIR}/${script}" | \
       grep -vE "environment|export|^\s*#" >/dev/null; then
      log "  ⚠ Potential hardcoded secret in ${script}"
      found_secrets=$((found_secrets + 1))
    fi
  done
  
  if [ ${found_secrets} -eq 0 ]; then
    log "  ✓ No hardcoded secrets found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Found ${found_secrets} potential secrets"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_env_injection() {
  test_case "Secrets: Environment variable injection used"
  
  if grep -q "export\|GITHUB_TOKEN\|API_KEY" "${PLATFORM_DIR}/bootstrap/bootstrap.sh"; then
    log "  ✓ Secret environment injection found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Secret injection pattern not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Workspace Security
# ============================================================================

test_secure_wiping() {
  test_case "Workspace: Secure wiping implemented"
  
  if grep -q "shred\|srm\|dd if=/dev/zero" "${PLATFORM_DIR}/scripts/clean-runner.sh"; then
    log "  ✓ Secure wiping configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Secure wiping not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_ephemeral_cleanup() {
  test_case "Workspace: Ephemeral cleanup on job completion"
  
  if grep -q "clean\|cleanup\|rm -rf\|destroy" "${PLATFORM_DIR}/scripts/clean-runner.sh"; then
    log "  ✓ Cleanup script found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Cleanup script incomplete"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_environment_wipe() {
  test_case "Workspace: Environment variables wiped"
  
  if grep -q "unset\|env -i\|env.*clean" "${PLATFORM_DIR}/scripts/clean-runner.sh"; then
    log "  ✓ Environment wiping found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Environment wiping missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Audit Logging
# ============================================================================

test_audit_logging() {
  test_case "Audit: Logging to syslog/journald"
  
  if grep -q "logger\|journalctl\|syslog" "${PLATFORM_DIR}/scripts/destroy-runner.sh"; then
    log "  ✓ Audit logging configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Audit logging missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_destruction_logging() {
  test_case "Audit: Destruction events logged"
  
  if grep -q "log\|logger\|echo.*log" "${PLATFORM_DIR}/scripts/destroy-runner.sh"; then
    log "  ✓ Destruction logging found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Destruction logging missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Observability & Detection
# ============================================================================

test_malicious_code_detection() {
  test_case "Detection: Observability for malicious activity"
  
  if [ -f "${PLATFORM_DIR}/observability/otel-config.yaml" ]; then
    log "  ✓ OpenTelemetry tracing available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Tracing infrastructure missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_suspicious_command_detection() {
  test_case "Detection: Health checks include malicious activity detection"
  
  if grep -q "detect\|suspicious\|anomaly" "${PLATFORM_DIR}/scripts/health-check.sh"; then
    log "  ✓ Detection mechanisms configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Detection mechanisms missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Vulnerability Scanning
# ============================================================================

test_sbom_scanning() {
  test_case "Scanning: SBOM generating for dependencies"
  
  if grep -q "syft" "${PLATFORM_DIR}/pipeline-executors/security-executor.sh"; then
    log "  ✓ SBOM scanning integrated"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ SBOM scanning missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_image_scanning() {
  test_case "Scanning: Container image scanning"
  
  if grep -q "trivy" "${PLATFORM_DIR}/pipeline-executors/security-executor.sh"; then
    log "  ✓ Image vulnerability scanning configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Image scanning missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_sast_scanning() {
  test_case "Scanning: Static code analysis (SAST)"
  
  if grep -q "semgrep" "${PLATFORM_DIR}/pipeline-executors/security-executor.sh"; then
    log "  ✓ SAST scanning configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ SAST scanning missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_secret_scanning() {
  test_case "Scanning: Secret detection"
  
  if grep -q "trufflehog\|gitleaks" "${PLATFORM_DIR}/pipeline-executors/security-executor.sh"; then
    log "  ✓ Secret scanning configured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "  ✗ Secret scanning missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  log "========================================="
  log "CI/CD Runner Platform - Security Tests"
  log "========================================="
  log ""
  
  # Container isolation
  log "Running container isolation tests..."
  test_executor_isolation
  test_readonly_filesystem
  test_network_isolation
  
  # Artifact signing
  log ""
  log "Running artifact signing tests..."
  test_cosign_signing
  test_slsa_attestations
  test_keyless_oidc
  
  # SBOM generation
  log ""
  log "Running SBOM tests..."
  test_sbom_generation
  test_sbom_formats
  
  # OPA policies
  log ""
  log "Running OPA policy tests..."
  test_opa_policy_enforcement
  test_signing_policy
  test_container_policy
  test_compliance_policies
  
  # Secret handling
  log ""
  log "Running secret handling tests..."
  test_no_hardcoded_secrets
  test_env_injection
  
  # Workspace security
  log ""
  log "Running workspace security tests..."
  test_secure_wiping
  test_ephemeral_cleanup
  test_environment_wipe
  
  # Audit logging
  log ""
  log "Running audit logging tests..."
  test_audit_logging
  test_destruction_logging
  
  # Observability
  log ""
  log "Running observability and detection tests..."
  test_malicious_code_detection
  test_suspicious_command_detection
  
  # Vulnerability scanning
  log ""
  log "Running vulnerability scanning tests..."
  test_sbom_scanning
  test_image_scanning
  test_sast_scanning
  test_secret_scanning
  
  # Summary
  log ""
  log "========================================="
  log "Security Test Results"
  log "========================================="
  log "Passed: ${TESTS_PASSED}"
  log "Failed: ${TESTS_FAILED}"
  
  if [ ${TESTS_FAILED} -gt 0 ]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"
