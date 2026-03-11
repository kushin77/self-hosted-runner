#!/bin/bash
################################################################################
# CI/CD Local Test Script
# Runs all test suites with coverage reporting
# Part of Phase 1 Foundation - fully automated, idempotent, hands-off
# 
# Usage: ./scripts/ci/test.sh [--coverage]
# 
# Constraints Applied:
# - NO GitHub Actions (direct local execution)
# - Immutable: logs appended to audit trail
# - Idempotent: safe to run multiple times
# - Hands-off: fully automated
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs/ci"
AUDIT_LOG="${LOG_DIR}/test.jsonl"
COVERAGE_MODE="${1:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)
BUILD_ID="${BUILD_ID:-local-$(date +%s)}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

################################################################################
# Logging Functions
################################################################################

log_event() {
  local status="$1"
  local message="$2"
  local details="${3:-}"
  
  # Immutable append-only log (JSONL)
  echo "{\"timestamp\":\"${TIMESTAMP}\",\"build_id\":\"${BUILD_ID}\",\"hostname\":\"${HOSTNAME}\",\"phase\":\"test\",\"status\":\"${status}\",\"message\":\"${message}\",\"details\":${details:-null}}" >> "$AUDIT_LOG"
  
  # Console output
  if [ "$status" = "success" ]; then
    echo "✅ ${message}"
  elif [ "$status" = "error" ]; then
    echo "❌ ${message}" >&2
  else
    echo "⚠️  ${message}"
  fi
}

################################################################################
# Test Functions
################################################################################

run_backend_tests() {
  log_event "info" "Running backend tests..." "{\"component\":\"backend\"}"
  
  cd "$PROJECT_ROOT/backend"
  
  if [ "$COVERAGE_MODE" = "--coverage" ]; then
    if npm run test:cov 2>&1 | tee -a "$AUDIT_LOG"; then
      log_event "success" "Backend tests passed with coverage" "{\"component\":\"backend\",\"with_coverage\":true}"
      return 0
    else
      log_event "error" "Backend tests failed" "{\"component\":\"backend\"}"
      return 1
    fi
  else
    if npm run test 2>&1 | tee -a "$AUDIT_LOG"; then
      log_event "success" "Backend tests passed" "{\"component\":\"backend\",\"with_coverage\":false}"
      return 0
    else
      log_event "error" "Backend tests failed" "{\"component\":\"backend\"}"
      return 1
    fi
  fi
}

run_frontend_tests() {
  log_event "info" "Running frontend tests..." "{\"component\":\"frontend\"}"
  
  cd "$PROJECT_ROOT/frontend"
  
  if [ "$COVERAGE_MODE" = "--coverage" ]; then
    if npm run test:cov 2>&1 | tee -a "$AUDIT_LOG"; then
      log_event "success" "Frontend tests passed with coverage" "{\"component\":\"frontend\",\"with_coverage\":true}"
      return 0
    else
      log_event "error" "Frontend tests failed" "{\"component\":\"frontend\"}"
      return 1
    fi
  else
    if npm run test 2>&1 | tee -a "$AUDIT_LOG"; then
      log_event "success" "Frontend tests passed" "{\"component\":\"frontend\",\"with_coverage\":false}"
      return 0
    else
      log_event "error" "Frontend tests failed" "{\"component\":\"frontend\"}"
      return 1
    fi
  fi
}

run_cypress_e2e() {
  log_event "info" "Running Cypress E2E tests..." "{\"component\":\"cypress_e2e\"}"
  
  cd "$PROJECT_ROOT/frontend"
  
  # Check if Cypress is installed
  if ! command -v npx &> /dev/null || ! npm ls cypress &> /dev/null 2>&1; then
    log_event "warn" "Cypress not installed, skipping E2E tests" "{\"component\":\"cypress_e2e\",\"reason\":\"not_installed\"}"
    return 0
  fi
  
  # Note: E2E tests require running services, so we skip in CI by default
  log_event "info" "E2E tests require running services, skipping in CI" "{\"component\":\"cypress_e2e\",\"note\":\"requires_services\"}"
  return 0
}

################################################################################
# Main Execution
################################################################################

main() {
  local start_time=$(date +%s)
  local any_failed=0
  
  log_event "info" "Starting test pipeline" "{\"build_id\":\"${BUILD_ID}\",\"coverage\":\"${COVERAGE_MODE:-disabled}\"}"
  
  echo "================================"
  echo "🧪 Test Suite Execution"
  echo "================================"
  echo ""
  
  if run_backend_tests; then
    echo ""
  else
    any_failed=1
    echo ""
  fi
  
  if run_frontend_tests; then
    echo ""
  else
    any_failed=1
    echo ""
  fi
  
  if run_cypress_e2e; then
    echo ""
  else
    any_failed=1
    echo ""
  fi
  
  # Summary
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  echo "================================"
  if [ $any_failed -eq 0 ]; then
    log_event "success" "All tests passed!" "{\"duration_seconds\":${duration}}"
    echo "✅ All tests passed!"
    echo "Duration: ${duration}s"
    [ "$COVERAGE_MODE" = "--coverage" ] && echo "Coverage reports generated in coverage/"
    echo "Audit log: $AUDIT_LOG"
    return 0
  else
    log_event "error" "Some tests failed" "{\"duration_seconds\":${duration}}"
    echo "❌ Some tests failed"
    echo "Duration: ${duration}s"
    echo "Audit log: $AUDIT_LOG"
    return 1
  fi
}

# Run main
main "$@"
