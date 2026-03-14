#!/bin/bash
set -euo pipefail

TEST_LOG="E2E_TEST_RESULTS_QUICK_$(date +%Y%m%d_%H%M%S).log"
{
  echo "════════════════════════════════════════════════════════════════"
  echo "QUICK E2E TEST SUITE - Critical Components Only"
  echo "════════════════════════════════════════════════════════════════"
  echo ""

  PASS=0
  FAIL=0

  echo "TEST 1: SSH Key Exists"
  if [ -f ~/.ssh/automation ]; then
    echo "✅ PASS: SSH key exists"
    ((PASS++))
  else
    echo "❌ FAIL: SSH key missing"
    ((FAIL++))
  fi
  
  echo ""
  echo "TEST 2: SSH Key Permissions"
  PERMS=$(stat -c "%a" ~/.ssh/automation 2>/dev/null || echo "000")
  if [ "$PERMS" = "600" ]; then
    echo "✅ PASS: Permissions correct ($PERMS)"
    ((PASS++))
  else
    echo "❌ FAIL: Permissions incorrect ($PERMS, expected 600)"
    ((FAIL++))
  fi

  echo ""
  echo "TEST 3: Deployment Scripts Exist"
  SCRIPTS_MISSING=0
  for script in deploy-worker-node.sh SETUP_SSH_SERVICE_ACCOUNT.sh; do
    if [ -f "$script" ] && [ -x "$script" ]; then
      echo "✅ PASS: $script exists and executable"
      ((PASS++))
    else
      echo "❌ FAIL: $script missing or not executable"
      ((FAIL++))
      ((SCRIPTS_MISSING++))
    fi
  done

  echo ""
  echo "TEST 4: Documentation Files"
  for doc in DEPLOY_SSH_SERVICE_ACCOUNT.md SSH_ISSUE_FIXED.md; do
    if [ -f "$doc" ]; then
      SIZE=$(ls -lh "$doc" | awk '{print $5}')
      echo "✅ PASS: $doc exists ($SIZE)"
      ((PASS++))
    else
      echo "❌ FAIL: $doc missing"
      ((FAIL++))
    fi
  done

  echo ""
  echo "TEST 5: Bash Syntax Validation"
  for script in deploy-worker-node.sh SETUP_SSH_SERVICE_ACCOUNT.sh; do
    if bash -n "$script" 2>&1 | grep -qE "syntax error|error:"; then
      echo "❌ FAIL: Syntax error in $script"
      bash -n "$script" 2>&1 | head -3
      ((FAIL++))
    else
      echo "✅ PASS: $script syntax valid"
      ((PASS++))
    fi
  done

  echo ""
  echo "TEST 6: Completion Reports"
  REPORTS=$(ls -1 TRIAGE_ALL_PHASES_COMPLETION* EXECUTION_SUMMARY_MASTER* 2>/dev/null | wc -l)
  if [ "$REPORTS" -gt 0 ]; then
    echo "✅ PASS: Completion reports found ($REPORTS)"
    ((PASS++))
  else
    echo "❌ FAIL: No completion reports found"
    ((FAIL++))
  fi

  echo ""
  echo "TEST 7: Service Account Keys"
  SSH_KEYS=$(ls ~/.ssh/svc-keys -1 2>/dev/null | wc -l)
  if [ "$SSH_KEYS" -ge 50 ]; then
    echo "✅ PASS: Service account keys available ($SSH_KEYS)"
    ((PASS++))
  else
    echo "⚠ WARN: Low service account key count: $SSH_KEYS"
    ((FAIL++))
  fi

  echo ""
  echo "TEST 8: Systemd Services"
  if systemctl list-unit-files 2>/dev/null | grep -q "monitoring-alert-triage"; then
    echo "✅ PASS: Monitoring service configured"
    ((PASS++))
  else
    echo "⚠ WARN: Monitoring service not found (may require investigation)"
    ((FAIL++))
  fi

  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "TEST SUMMARY"
  echo "════════════════════════════════════════════════════════════════"
  echo "Total Tests: $((PASS + FAIL))"
  echo "Passed: $PASS"
  echo "Failed: $FAIL"
  SUCCESS_RATE=$((PASS * 100 / (PASS + FAIL)))
  echo "Success Rate: $SUCCESS_RATE%"
  echo ""
  
  if [ $FAIL -eq 0 ]; then
    echo "🟢 ALL TESTS PASSED"
  else
    echo "❌ Some tests failed - see details above"
  fi

} | tee "$TEST_LOG"

echo ""
echo "Test log: $TEST_LOG"
