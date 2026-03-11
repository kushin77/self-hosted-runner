#!/usr/bin/env bash
set -euo pipefail

# Integration Test Harness
# Orchestrates smoke tests, security verifications, and deployment validation
# Outputs: summary report with pass/fail counts and detailed logs
# Exit code: 0 if all tests pass, 1 on any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SMOKE_TEST_SCRIPT="$REPO_ROOT/scripts/test/smoke_tests_canonical_secrets.sh"
AUDIT_VERIFY_SCRIPT="$REPO_ROOT/scripts/security/verify_audit_immutability.sh"

TEST_REPORT="${TEST_REPORT:-/tmp/integration_test_report_$(date +%s).jsonl}"
API_ENDPOINT="${API_ENDPOINT:-http://localhost:8000}"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
AUDIT_LOG_PATH="${AUDIT_LOG_PATH:-.}"

echo "========================================"
echo "Integration Test Harness"
echo "========================================"
echo "Test Report: $TEST_REPORT"
echo ""

# Utility: log test suite result
log_suite_result() {
  local suite="$1"
  local status="$2"  # PASSED or FAILED
  local test_count="$3"
  local passed="$4"
  local failed="$5"
  
  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg suite "$suite" \
    --arg status "$status" \
    --arg total "$test_count" \
    --arg passed "$passed" \
    --arg failed "$failed" \
    '{timestamp: $ts, test_suite: $suite, status: $status, total: ($total | tonumber), passed: ($passed | tonumber), failed: ($failed | tonumber)}' \
    >> "$TEST_REPORT"
}

# Pre-flight checks
echo "[PRE-FLIGHT] Checking service health..."
if ! curl -sf "$API_ENDPOINT/api/v1/secrets/health" > /dev/null 2>&1; then
  echo "❌ API endpoint unreachable at $API_ENDPOINT"
  exit 1
fi
echo "✓ API endpoint is healthy"

echo ""
echo "[TEST 1] Running smoke tests..."
if bash "$SMOKE_TEST_SCRIPT" 2>&1 | tee /tmp/smoke_test_output.txt; then
  SMOKE_RESULTS=$(tail -1 /tmp/smoke_test_output.txt)
  PASSED=$(echo "$SMOKE_RESULTS" | jq -r '.passed // 0')
  FAILED=$(echo "$SMOKE_RESULTS" | jq -r '.failed // 0')
  TOTAL=$((PASSED + FAILED))
  log_suite_result "smoke_tests" "PASSED" "$TOTAL" "$PASSED" "$FAILED"
  echo "✓ Smoke tests passed: $PASSED/$TOTAL"
else
  SMOKE_RESULTS=$(tail -1 /tmp/smoke_test_output.txt 2>/dev/null || echo '{"passed":0,"failed":1}')
  PASSED=$(echo "$SMOKE_RESULTS" | jq -r '.passed // 0')
  FAILED=$(echo "$SMOKE_RESULTS" | jq -r '.failed // 1')
  TOTAL=$((PASSED + FAILED))
  log_suite_result "smoke_tests" "FAILED" "$TOTAL" "$PASSED" "$FAILED"
  echo "❌ Smoke tests failed"
fi

echo ""
echo "[TEST 2] Running audit immutability verification..."
if [ -f "$AUDIT_LOG_PATH" ]; then
  if bash "$AUDIT_VERIFY_SCRIPT" 2>&1 | tee /tmp/audit_verify_output.txt; then
    AUDIT_RESULTS=$(tail -1 /tmp/audit_verify_output.txt)
    PASSED=$(echo "$AUDIT_RESULTS" | jq -r '.passed // 0')
    FAILED=$(echo "$AUDIT_RESULTS" | jq -r '.failed // 0')
    TOTAL=$((PASSED + FAILED))
    log_suite_result "audit_immutability" "PASSED" "$TOTAL" "$PASSED" "$FAILED"
    echo "✓ Audit verification passed: $PASSED/$TOTAL"
  else
    AUDIT_RESULTS=$(tail -1 /tmp/audit_verify_output.txt 2>/dev/null || echo '{"passed":0,"failed":1}')
    PASSED=$(echo "$AUDIT_RESULTS" | jq -r '.passed // 0')
    FAILED=$(echo "$AUDIT_RESULTS" | jq -r '.failed // 1')
    TOTAL=$((PASSED + FAILED))
    log_suite_result "audit_immutability" "FAILED" "$TOTAL" "$PASSED" "$FAILED"
    echo "❌ Audit verification failed"
  fi
else
  echo "⚠ Audit log not found at $AUDIT_LOG_PATH; skipping verification"
  log_suite_result "audit_immutability" "SKIPPED" "0" "0" "0"
fi

echo ""
echo "[TEST 3] Deployment validation..."
if [ -d "$REPO_ROOT/deploy" ] && [ -f "$REPO_ROOT/scripts/deploy/deploy_staging.sh" ]; then
  echo "✓ Deployment artifacts present"
  log_suite_result "deployment_validation" "PASSED" "1" "1" "0"
else
  echo "❌ Deployment artifacts missing"
  log_suite_result "deployment_validation" "FAILED" "1" "0" "1"
fi

# Generate final report
echo ""
echo "========================================"
echo "Test Summary Report"
echo "========================================"
cat "$TEST_REPORT" | jq -s '{
  timestamp: now | todate,
  total_suites: length,
  suites_passed: map(select(.status == "PASSED")) | length,
  suites_failed: map(select(.status == "FAILED")) | length,
  total_tests: map(.total) | add,
  total_passed: map(.passed) | add,
  total_failed: map(.failed) | add,
  details: .
}'

# Exit based on test results
TOTAL_FAILED=$(jq -s '[.[] | select(.status == "FAILED")] | length' "$TEST_REPORT")
if [ "$TOTAL_FAILED" -gt 0 ]; then
  echo ""
  echo "❌ $TOTAL_FAILED test suite(s) failed. See $TEST_REPORT for details."
  exit 1
else
  echo ""
  echo "✅ All integration tests passed!"
  exit 0
fi
