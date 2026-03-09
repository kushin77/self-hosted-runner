#!/bin/bash
################################################################################
# Orchestration script to run all unit tests
# Handles exit codes correctly without set -e trap issues
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASSED=0
FAILED=0

run_test() {
  local test_script="$1"
  local test_name="$2"
  
  echo ""
  echo "▶ Running: $test_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if bash "$test_script" 2>&1; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ PASSED: $test_name"
    PASSED=$((PASSED + 1))
  else
    local exit_code=$?
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✗ FAILED: $test_name (exit code: $exit_code)"
    FAILED=$((FAILED + 1))
  fi
}

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         CREDENTIAL HELPER UNIT TEST SUITE                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"

# Run all unit tests
run_test "$SCRIPT_DIR/unit-test-gsm-helper.sh" "GSM Helper Tests"
run_test "$SCRIPT_DIR/unit-test-vault-helper.sh" "Vault Helper Tests"
run_test "$SCRIPT_DIR/unit-test-kms-helper.sh" "KMS Helper Tests"

# Syntax check all helpers
echo ""
echo "▶ Running: Credential Helper Syntax Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$SCRIPT_DIR/.." || exit 1

SYNTAX_FAILED=0
for helper in cred-helpers/fetch-from-*.sh; do
  if bash -n "$helper" 2>&1; then
    echo "✓ $helper"
  else
    echo "✗ SYNTAX ERROR in $helper"
    SYNTAX_FAILED=$((SYNTAX_FAILED + 1))
    FAILED=$((FAILED + 1))
  fi
done

# Check main credential manager
if bash -n credential-manager.sh 2>&1; then
  echo "✓ credential-manager.sh"
else
  echo "✗ SYNTAX ERROR in credential-manager.sh"
  SYNTAX_FAILED=$((SYNTAX_FAILED + 1))
  FAILED=$((FAILED + 1))
fi

if [ $SYNTAX_FAILED -eq 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ PASSED: Syntax Checks"
  PASSED=$((PASSED + 1))
fi

# Print summary
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                     TEST SUMMARY                          ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║ PASSED: $PASSED"
echo "║ FAILED: $FAILED"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if [ $FAILED -eq 0 ]; then
  echo "✓ All tests passed successfully!"
  exit 0
else
  echo "✗ Some tests failed. Please review the output above."
  exit 1
fi
