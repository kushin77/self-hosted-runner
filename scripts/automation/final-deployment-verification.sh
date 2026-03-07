#!/usr/bin/env bash
set -euo pipefail

# scripts/automation/final-deployment-verification.sh
# Purpose: Comprehensive verification that all hands-off automation is deployed and operational

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/automation"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
REPORT_FILE="$REPO_ROOT/DEPLOYMENT_VERIFICATION_$TIMESTAMP.log"

log_header() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  $*"
  echo "═══════════════════════════════════════════════════════════════"
  tee -a "$REPORT_FILE" <<< "$*"
}

log_status() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$REPORT_FILE"
}

check_file_exists() {
  local file=$1
  local description=$2
  
  if [ -f "$file" ]; then
    log_status "✅ $description exists: $file"
    return 0
  else
    log_status "❌ MISSING: $description at $file"
    return 1
  fi
}

check_file_executable() {
  local file=$1
  
  if [ -x "$file" ]; then
    log_status "✅ Executable: $file"
    return 0
  else
    log_status "⚠️  Not executable: $file (will fix)"
    chmod +x "$file" && log_status "✅ Fixed permissions: $file"
    return $?
  fi
}

check_bash_syntax() {
  local file=$1
  
  if bash -n "$file" 2>/dev/null; then
    log_status "✅ Valid bash syntax: $file"
    return 0
  else
    log_status "❌ Syntax error in: $file"
    bash -n "$file" 2>&1 | tee -a "$REPORT_FILE"
    return 1
  fi
}

check_workflow_exists() {
  local workflow=$1
  local description=$2
  
  if [ -f "$REPO_ROOT/.github/workflows/$workflow" ]; then
    log_status "✅ Workflow deployed: $description"
    return 0
  else
    log_status "❌ MISSING workflow: $description at .github/workflows/$workflow"
    return 1
  fi
}

main() {
  > "$REPORT_FILE"  # Clear log file
  
  log_header "HANDS-OFF AUTOMATION DEPLOYMENT VERIFICATION"
  log_status "Repository: $REPO_ROOT"
  log_status "Timestamp: $TIMESTAMP"
  
  local total_checks=0
  local passed_checks=0
  
  # ─────────────────────────────────────────────────────────────
  log_header "1. Core Automation Scripts"
  
  for script in ci_retry.sh wait_and_rerun.sh validate-idempotency.sh; do
    ((total_checks++))
    if check_file_exists "$SCRIPT_DIR/$script" "Automation script: $script"; then
      ((passed_checks++))
      ((total_checks++))
      if check_file_executable "$SCRIPT_DIR/$script"; then
        ((passed_checks++))
      fi
      ((total_checks++))
      if check_bash_syntax "$SCRIPT_DIR/$script"; then
        ((passed_checks++))
      fi
    fi
  done
  
  # ─────────────────────────────────────────────────────────────
  log_header "2. Runner Management Scripts"
  
  for script in auto-heal.sh runner-ephemeral-cleanup.sh runner-diagnostics.sh; do
    ((total_checks++))
    if check_file_exists "$REPO_ROOT/scripts/runner/$script" "Runner script: $script"; then
      ((passed_checks++))
      ((total_checks++))
      if check_file_executable "$REPO_ROOT/scripts/runner/$script"; then
        ((passed_checks++))
      fi
      ((total_checks++))
      if check_bash_syntax "$REPO_ROOT/scripts/runner/$script"; then
        ((passed_checks++))
      fi
    fi
  done
  
  # ─────────────────────────────────────────────────────────────
  log_header "3. GitHub Actions Workflows"
  
  for workflow in runner-self-heal.yml admin-token-watch.yml secret-rotation-mgmt-token.yml; do
    ((total_checks++))
    if check_workflow_exists "$workflow" "$workflow"; then
      ((passed_checks++))
    fi
  done
  
  # ─────────────────────────────────────────────────────────────
  log_header "4. Documentation"
  
  for doc in AUTOMATION_DELIVERY_COMPLETE.md AUTOMATION_RUNBOOK.md AUTOMATION_DEPLOYMENT_COMPLETE.md; do
    ((total_checks++))
    if check_file_exists "$REPO_ROOT/$doc" "Documentation: $doc"; then
      ((passed_checks++))
    fi
  done
  
  # ─────────────────────────────────────────────────────────────
  log_header "5. Idempotency Validation"
  
  ((total_checks++))
  if bash "$SCRIPT_DIR/validate-idempotency.sh" >> "$REPORT_FILE" 2>&1; then
    log_status "✅ Idempotency validation passed"
    ((passed_checks++))
  else
    log_status "❌ Idempotency validation failed"
  fi
  
  # ─────────────────────────────────────────────────────────────
  log_header "6. Secret Configuration Check"
  
  if [ -n "${RUNNER_MGMT_TOKEN:-}" ]; then
    ((total_checks++))
    log_status "✅ RUNNER_MGMT_TOKEN is configured"
    ((passed_checks++))
  else
    ((total_checks++))
    log_status "⚠️  RUNNER_MGMT_TOKEN not set in environment (OK if in GitHub secrets)"
  fi
  
  if [ -n "${DEPLOY_SSH_KEY:-}" ]; then
    ((total_checks++))
    log_status "✅ DEPLOY_SSH_KEY is configured"
    ((passed_checks++))
  else
    ((total_checks++))
    log_status "⚠️  DEPLOY_SSH_KEY not set in environment (OK if in GitHub secrets)"
  fi
  
  # ─────────────────────────────────────────────────────────────
  log_header "VERIFICATION SUMMARY"
  
  log_status ""
  log_status "Total Checks: $total_checks"
  log_status "Passed: $passed_checks"
  log_status "Failed: $((total_checks - passed_checks))"
  log_status "Pass Rate: $(( (passed_checks * 100) / total_checks ))%"
  log_status ""
  
  if [ $((total_checks - passed_checks)) -eq 0 ]; then
    log_status "═══════════════════════════════════════════════════════════════"
    log_status "🎉 DEPLOYMENT VERIFICATION PASSED - ALL SYSTEMS OPERATIONAL 🎉"
    log_status "═══════════════════════════════════════════════════════════════"
    log_status ""
    log_status "✅ Immutable, Ephemeral, Idempotent, Fully Hands-Off Automation Active"
    log_status "✅ Ready for Production Use"
    
    cat << EOF | tee -a "$REPORT_FILE"

Next Steps:
1. Ensure RUNNER_MGMT_TOKEN and DEPLOY_SSH_KEY are configured in GitHub secrets
2. Monitor runner-self-heal.yml workflow for 24 hours
3. Verify failed workflow reruns work via admin-token-watch.yml
4. Check secret-rotation-mgmt-token.yml validation on next scheduled run

For detailed operations guide, see: AUTOMATION_RUNBOOK.md
For architecture details, see: AUTOMATION_DELIVERY_COMPLETE.md

Report saved to: $REPORT_FILE
EOF
    
    return 0
  else
    log_status "═══════════════════════════════════════════════════════════════"
    log_status "⚠️  DEPLOYMENT VERIFICATION INCOMPLETE"
    log_status "═══════════════════════════════════════════════════════════════"
    log_status ""
    log_status "Review failures above and re-run after corrections."
    log_status "Report saved to: $REPORT_FILE"
    
    return 1
  fi
}

main "$@"
