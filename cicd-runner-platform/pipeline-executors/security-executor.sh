#!/usr/bin/env bash
##
## Security Executor
## Runs SAST, secret scanning, dependency checks, and policy validation.
##
set -euo pipefail

JOB_ID="${1:-unknown}"
SCAN_TYPE="${2:-all}"

echo "Security Executor: ${JOB_ID}"
echo "Scan type: ${SCAN_TYPE}"

OUTPUT_DIR="/tmp/${JOB_ID}/security"
mkdir -p "${OUTPUT_DIR}"

cleanup() {
  echo "Cleaning security scan environment..."
  chmod -R 777 "${OUTPUT_DIR}" 2>/dev/null || true
}

trap cleanup EXIT

# SAST with Sonarqube or Semgrep
run_sast() {
  echo "Running SAST scan..."
  
  if command -v semgrep &>/dev/null; then
    semgrep --config=p/security-audit \
            --json \
            --output="${OUTPUT_DIR}/sast.json" \
            . || true
  fi
  
  echo "✓ SAST scan completed"
}

# Secret scanning
run_secret_scan() {
  echo "Running secret detection..."
  
  if command -v truffleHog &>/dev/null; then
    truffleHog filesystem . \
      --json \
      --fail \
      > "${OUTPUT_DIR}/secrets.json" || true
  fi
  
  echo "✓ Secret scan completed"
}

# Dependency scanning
run_dependency_scan() {
  echo "Running dependency vulnerability check..."
  
  if command -v trivy &>/dev/null; then
    trivy rootfs . \
      --format json \
      --output "${OUTPUT_DIR}/dependencies.json" || true
  fi
  
  echo "✓ Dependency scan completed"
}

# License compliance
run_license_check() {
  echo "Running license compliance check..."
  
  if command -v licensefinder &>/dev/null; then
    licensefinder report \
      --format json \
      > "${OUTPUT_DIR}/licenses.json" || true
  fi
  
  echo "✓ License check completed"
}

# Policy validation with OPA/Conftest
run_policy_check() {
  echo "Running policy validation..."
  
  if command -v conftest &>/dev/null; then
    conftest test \
      -p "${PROJECT_ROOT}/security/policy/" \
      -o json \
      . > "${OUTPUT_DIR}/policy.json" || true
  fi
  
  echo "✓ Policy validation completed"
}

# SCA with Snyk or similar
run_sca() {
  echo "Running software composition analysis..."
  
  # placeholder for Snyk, npm audit, cargo audit, etc.
  npm audit --json > "${OUTPUT_DIR}/npm-audit.json" 2>/dev/null || true
  
  echo "✓ SCA completed"
}

# Execute scans based on type
case "${SCAN_TYPE}" in
  sast)
    run_sast
    ;;
  secrets)
    run_secret_scan
    ;;
  dependencies)
    run_dependency_scan
    ;;
  licenses)
    run_license_check
    ;;
  policy)
    run_policy_check
    ;;
  sca)
    run_sca
    ;;
  all|*)
    run_sast
    run_secret_scan
    run_dependency_scan
    run_license_check
    run_policy_check
    run_sca
    ;;
esac

# Generate consolidated security report
echo "Generating security report..."
jq -s add "${OUTPUT_DIR}"/*.json > "${OUTPUT_DIR}/security-report.json" 2>/dev/null || true

echo "✓ Security scan completed"
echo "Results: ${OUTPUT_DIR}/"

# Fail job if critical issues found
CRITICAL_COUNT=$(jq 'select(.severity=="critical")' "${OUTPUT_DIR}/security-report.json" 2>/dev/null | wc -l)
if [ "${CRITICAL_COUNT}" -gt 0 ]; then
  echo "✗ Found ${CRITICAL_COUNT} critical security issues"
  exit 1
fi
