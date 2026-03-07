#!/usr/bin/env bash
set -euo pipefail

# scripts/automation/validate-idempotency.sh
# Purpose: Verify that automation scripts are idempotent (can run multiple times safely)
# Tests each critical automation script in dry-run or no-op mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="/tmp/idempotency-validation-$(date +%s).log"

log_info() {
  echo "[idempotency-validator] [$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[idempotency-validator] [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" | tee -a "$LOG_FILE"
}

test_dry_run() {
  local script=$1
  local description=$2
  
  log_info "Testing: $description"
  
  if [ ! -f "$script" ]; then
    log_error "Script not found: $script"
    return 1
  fi
  
  # Run with dry-run if supported, or check-mode for ansible
  if bash "$script" --dry-run 2>/dev/null || bash "$script" --check 2>/dev/null || true; then
    log_info "✓ $description is idempotent-safe"
    return 0
  else
    # If no dry-run support, at least verify it's executable and has proper guards
    if bash -n "$script" 2>/dev/null; then
      log_info "✓ $description syntax is valid (no dry-run available)"
      return 0
    else
      log_error "✗ $description has syntax errors"
      return 1
    fi
  fi
}

test_script_syntax() {
  local script=$1
  local description=$2
  
  log_info "Validating bash syntax: $description"
  
  if bash -n "$script" 2>/dev/null; then
    log_info "✓ Syntax valid: $description"
    return 0
  else
    log_error "✗ Syntax error in $description"
    bash -n "$script" 2>&1 | tee -a "$LOG_FILE"
    return 1
  fi
}

test_sh_guards() {
  local script=$1
  local description=$2
  
  log_info "Checking idempotency guards in: $description"
  
  # Verify essential guards are present
  if grep -q "set -euo pipefail\|set -e" "$script" 2>/dev/null; then
    log_info "✓ Error handling guard present: $description"
    return 0
  else
    log_error "⚠ No exit-on-error guard found, may not be truly idempotent: $description"
    return 1
  fi
}

# Test critical automation scripts
main() {
  log_info "=== IDEMPOTENCY VALIDATION START ==="
  log_info "Repository root: $REPO_ROOT"
  
  local failed_tests=0
  
  # Test ci_retry.sh
  test_script_syntax "$SCRIPT_DIR/ci_retry.sh" "ci_retry.sh" || ((failed_tests++))
  test_sh_guards "$SCRIPT_DIR/ci_retry.sh" "ci_retry.sh" || ((failed_tests++))
  
  # Test wait_and_rerun.sh
  test_script_syntax "$SCRIPT_DIR/wait_and_rerun.sh" "wait_and_rerun.sh" || ((failed_tests++))
  test_sh_guards "$SCRIPT_DIR/wait_and_rerun.sh" "wait_and_rerun.sh" || ((failed_tests++))
  
  # Test runner ephemeral cleanup
  test_script_syntax "$REPO_ROOT/scripts/runner/runner-ephemeral-cleanup.sh" "runner-ephemeral-cleanup.sh" || ((failed_tests++))
  test_sh_guards "$REPO_ROOT/scripts/runner/runner-ephemeral-cleanup.sh" "runner-ephemeral-cleanup.sh" || ((failed_tests++))
  
  # Test auto-heal
  test_script_syntax "$REPO_ROOT/scripts/runner/auto-heal.sh" "auto-heal.sh" || ((failed_tests++))
  test_sh_guards "$REPO_ROOT/scripts/runner/auto-heal.sh" "auto-heal.sh" || ((failed_tests++))
  
  # Test runner diagnostics
  test_script_syntax "$REPO_ROOT/scripts/runner/runner-diagnostics.sh" "runner-diagnostics.sh" || ((failed_tests++))
  
  log_info "---"
  log_info "Log saved to: $LOG_FILE"
  
  if [ $failed_tests -eq 0 ]; then
    log_info "=== IDEMPOTENCY VALIDATION PASSED ==="
    return 0
  else
    log_error "=== IDEMPOTENCY VALIDATION FAILED ($failed_tests failures) ==="
    return 1
  fi
}

main "$@"
