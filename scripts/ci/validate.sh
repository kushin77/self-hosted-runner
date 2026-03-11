#!/bin/bash
################################################################################
# CI/CD Local Validation Script
# Runs linting, formatting, and type checks
# Part of Phase 1 Foundation - fully automated, idempotent, hands-off
# 
# Usage: ./scripts/ci/validate.sh [--fix]
# 
# Constraints Applied:
# - NO GitHub Actions (direct local execution)
# - Immutable: logs appended to audit trail
# - Idempotent: safe to run multiple times
# - Hands-off: automated, no manual intervention
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs/ci"
AUDIT_LOG="${LOG_DIR}/validate.jsonl"
BACKEND_DIR="${PROJECT_ROOT}/backend"
FRONTEND_DIR="${PROJECT_ROOT}/frontend"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Configuration
FIX_MODE="${1:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)
BUILD_ID="${BUILD_ID:-local-$(date +%s)}"

################################################################################
# Logging Functions
################################################################################

log_event() {
  local status="$1"
  local message="$2"
  local details="${3:-}"
  
  # Immutable append-only log (JSONL - never delete, never update)
  echo "{\"timestamp\":\"${TIMESTAMP}\",\"build_id\":\"${BUILD_ID}\",\"hostname\":\"${HOSTNAME}\",\"phase\":\"validate\",\"status\":\"${status}\",\"message\":\"${message}\",\"details\":${details:-null}}" >> "$AUDIT_LOG"
  
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
# Validation Functions
################################################################################

validate_typescript() {
  log_event "info" "Validating TypeScript compilation..." "{\"component\":\"typescript\"}"
  
  cd "$BACKEND_DIR"
  if npx tsc --noEmit 2>&1; then
    log_event "success" "TypeScript validation passed" "{\"component\":\"typescript\",\"files_checked\":\"all\"}"
    return 0
  else
    log_event "error" "TypeScript compilation failed" "{\"component\":\"typescript\"}"
    return 1
  fi
}

validate_eslint() {
  log_event "info" "Running ESLint checks..." "{\"component\":\"eslint\"}"
  
  local eslint_errors=0
  
  # Backend ESLint
  cd "$BACKEND_DIR"
  if ! npx eslint src --ext .ts 2>&1 | tee -a "$AUDIT_LOG"; then
    eslint_errors=$((eslint_errors + 1))
  fi
  
  # Frontend ESLint
  cd "$FRONTEND_DIR"
  if ! npx eslint src --ext .ts,.tsx 2>&1 | tee -a "$AUDIT_LOG"; then
    eslint_errors=$((eslint_errors + 1))
  fi
  
  if [ $eslint_errors -eq 0 ]; then
    log_event "success" "ESLint validation passed" "{\"component\":\"eslint\"}"
    return 0
  else
    log_event "error" "ESLint found issues" "{\"component\":\"eslint\",\"error_count\":$eslint_errors}"
    return 1
  fi
}

validate_prettier() {
  log_event "info" "Checking code formatting..." "{\"component\":\"prettier\"}"
  
  cd "$BACKEND_DIR"
  if npx prettier --check "src/**/*.ts" 2>&1; then
    log_event "success" "Prettier formatting validation passed" "{\"component\":\"prettier\"}"
    return 0
  else
    log_event "error" "Code formatting issues detected" "{\"component\":\"prettier\"}"
    
    if [ "$FIX_MODE" = "--fix" ]; then
      log_event "info" "Auto-fixing code formatting..." "{\"component\":\"prettier\",\"action\":\"repair\"}"
      npx prettier --write "src/**/*.ts"
      log_event "success" "Code formatting auto-fixed" "{\"component\":\"prettier\",\"action\":\"repair_complete\"}"
      return 0
    else
      return 1
    fi
  fi
}

validate_security() {
  log_event "info" "Running security checks..." "{\"component\":\"security\"}"
  
  # Check for hardcoded secrets
  cd "$PROJECT_ROOT"
  if command -v detect-secrets &> /dev/null; then
    if detect-secrets scan --all-files --force-use-all-plugins 2>&1 | grep -q '"type":'; then
      log_event "error" "Potential secrets detected in code" "{\"component\":\"security\",\"check\":\"secrets\"}"
      return 1
    fi
  fi
  
  log_event "success" "Security validation passed" "{\"component\":\"security\"}"
  return 0
}

################################################################################
# Main Execution
################################################################################

main() {
  local start_time=$(date +%s)
  local all_passed=0
  
  log_event "info" "Starting CI validation pipeline" "{\"build_id\":\"${BUILD_ID}\",\"fix_mode\":\"${FIX_MODE:-disabled}\"}"
  
  # Run validation checks
  echo "================================"
  echo "🔍 CI/CD Validation Pipeline"
  echo "================================"
  echo ""
  
  if validate_typescript; then
    echo ""
  else
    all_passed=1
  fi
  
  if validate_eslint; then
    echo ""
  else
    all_passed=1
  fi
  
  if validate_prettier; then
    echo ""
  else
    all_passed=1
  fi
  
  if validate_security; then
    echo ""
  else
    all_passed=1
  fi
  
  # Summary
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  echo "================================"
  if [ $all_passed -eq 0 ]; then
    log_event "success" "All validation checks passed!" "{\"duration_seconds\":${duration}}"
    echo "✅ All validation checks passed!"
    echo "Duration: ${duration}s"
    echo "Audit log: $AUDIT_LOG"
    return 0
  else
    log_event "error" "Validation checks failed" "{\"duration_seconds\":${duration},\"fix_available\":${FIX_MODE:-no}}"
    echo "❌ Some validation checks failed"
    echo "Duration: ${duration}s"
    echo "Audit log: $AUDIT_LOG"
    if [ -z "$FIX_MODE" ]; then
      echo ""
      echo "💡 Tip: Run with --fix to auto-fix formatting issues"
    fi
    return 1
  fi
}

# Run main
main "$@"
