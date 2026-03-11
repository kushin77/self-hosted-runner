#!/bin/bash
################################################################################
# CI/CD Local Security Scanning Script
# Runs SAST, dependency checks, and secrets scanning
# Part of Phase 1 Foundation - fully automated, idempotent, hands-off
# 
# Usage: ./scripts/ci/security-scan.sh
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
AUDIT_LOG="${LOG_DIR}/security-scan.jsonl"
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
  echo "{\"timestamp\":\"${TIMESTAMP}\",\"build_id\":\"${BUILD_ID}\",\"hostname\":\"${HOSTNAME}\",\"phase\":\"security\",\"status\":\"${status}\",\"message\":\"${message}\",\"details\":${details:-null}}" >> "$AUDIT_LOG"
  
  # Console output
  if [ "$status" = "success" ]; then
    echo "✅ ${message}"
  elif [ "$status" = "error" ]; then
    echo "❌ ${message}" >&2
  elif [ "$status" = "warn" ]; then
    echo "⚠️  ${message}"
  else
    echo "ℹ️  ${message}"
  fi
}

################################################################################
# Security Scanning Functions
################################################################################

scan_dependencies() {
  log_event "info" "Scanning dependencies for vulnerabilities..." "{\"component\":\"dependencies\"}"
  
  cd "$PROJECT_ROOT"
  local vuln_count=0
  
  echo "🔍 Backend dependencies..."
  cd backend
  if npm audit --audit-level=moderate 2>&1; then
    log_event "success" "Backend dependencies audit passed" "{\"component\":\"backend-deps\"}"
  else
    vuln_count=$((vuln_count + 1))
    log_event "warn" "Backend dependencies have vulnerabilities" "{\"component\":\"backend-deps\"),\"action\":\"review\"}"
  fi
  
  echo ""
  echo "🔍 Frontend dependencies..."
  cd "$PROJECT_ROOT"/frontend
  if npm audit --audit-level=moderate 2>&1; then
    log_event "success" "Frontend dependencies audit passed" "{\"component\":\"frontend-deps\"}"
  else
    vuln_count=$((vuln_count + 1))
    log_event "warn" "Frontend dependencies have vulnerabilities" "{\"component\":\"frontend-deps\",\"action\":\"review\"}"
  fi
  
  if [ $vuln_count -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

scan_secrets() {
  log_event "info" "Scanning for hardcoded secrets..." "{\"component\":\"secrets\"}"
  
  cd "$PROJECT_ROOT"
  
  # Use detect-secrets if available
  if command -v detect-secrets &> /dev/null; then
    if detect-secrets scan --all-files --baseline .secrets.baseline 2>&1; then
      log_event "success" "Secrets scan completed (no new secrets detected)" "{\"component\":\"secrets\"}"
      return 0
    else
      log_event "error" "Potential secrets detected" "{\"component\":\"secrets\"}"
      return 1
    fi
  else
    log_event "warn" "detect-secrets not installed, skipping secrets scan" "{\"component\":\"secrets\",\"tool\":\"detect-secrets\"}"
    return 0
  fi
}

scan_static_analysis() {
  log_event "info" "Running static code analysis..." "{\"component\":\"sast\"}"
  
  cd "$PROJECT_ROOT/backend"
  
  # TypeScript strict mode (caught errors before runtime)
  if npx tsc --noEmit --strict 2>&1 | tee -a "$AUDIT_LOG"; then
    log_event "success" "Static analysis passed (TypeScript strict mode)" "{\"component\":\"sast\",\"tool\":\"tsc\"}"
    return 0
  else
    log_event "error" "Static analysis found issues" "{\"component\":\"sast\",\"tool\":\"tsc\"}"
    return 1
  fi
}

scan_infrastructure() {
  log_event "info" "Scanning infrastructure for security issues..." "{\"component\":\"infrastructure\"}"
  
  # Check for hardcoded credentials in dockerfile/compose
  cd "$PROJECT_ROOT"
  
  local found_issues=0
  
  # Check Dockerfiles
  if grep -r "ENV.*PASSWORD\|ENV.*SECRET\|ENV.*TOKEN\|ENV.*KEY" \
    backend/Dockerfile* frontend/Dockerfile* 2>/dev/null | grep -v "^#"; then
    log_event "error" "Found hardcoded credentials in Dockerfiles" "{\"component\":\"infrastructure\",\"file\":\"Dockerfile\"}"
    found_issues=1
  fi
  
  # Check docker-compose files
  if grep -r "MYSQL_PASSWORD\|SECRET\|TOKEN.*:" config/docker-compose*.yml 2>/dev/null | \
    grep -v "^#\|environment:" | grep -v "^\s*#"; then
    log_event "warn" "Review docker-compose credentials (should use .env)" "{\"component\":\"infrastructure\",\"file\":\"docker-compose\"}"
  fi
  
  if [ $found_issues -eq 0 ]; then
    log_event "success" "Infrastructure security check passed" "{\"component\":\"infrastructure\"}"
    return 0
  else
    return 1
  fi
}

################################################################################
# Main Execution
################################################################################

main() {
  local start_time=$(date +%s)
  local any_failed=0
  
  log_event "info" "Starting security scan pipeline" "{\"build_id\":\"${BUILD_ID}\"}"
  
  echo "================================"
  echo "🔒 Security Scanning Pipeline"
  echo "================================"
  echo ""
  
  if scan_dependencies; then
    echo ""
  else
    any_failed=1
    echo ""
  fi
  
  if scan_secrets; then
    echo ""
  else
    any_failed=1
    echo ""
  fi
  
  if scan_static_analysis; then
    echo ""
  else
    any_failed=1
    echo ""
  fi
  
  if scan_infrastructure; then
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
    log_event "success" "Security scan passed!" "{\"duration_seconds\":${duration}}"
    echo "✅ Security scan passed!"
    echo "Duration: ${duration}s"
    echo "Audit log: $AUDIT_LOG"
    return 0
  else
    log_event "error" "Security scan detected issues" "{\"duration_seconds\":${duration}}"
    echo "⚠️  Security scan found issues (review above)"
    echo "Duration: ${duration}s"
    echo "Audit log: $AUDIT_LOG"
    return 1
  fi
}

# Run main
main "$@"
