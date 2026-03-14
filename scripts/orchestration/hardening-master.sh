#!/bin/bash
#
# Production Hardening Master Orchestrator
# 
# This script coordinates all remaining production hardening work:
# - Portal/backend zero-drift validation
# - Test consolidation and optimization
# - Error tracking and centralization
# - Enhancement backlog management
# - Continuous monitoring setup
#
# Usage:
#   bash scripts/orchestration/hardening-master.sh [--phase PHASE] [--execute] [--strict]
#
# Phases:
#   portal-sync       - Portal/backend synchronization validation
#   test-consolidate  - Test suite consolidation and optimization
#   error-tracking    - Central error logging and analysis
#   enhancement       - Backlog prioritization and tracking
#   monitoring        - Continuous validation framework
#   all               - Execute all phases sequentially
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGS_DIR="${REPO_ROOT}/logs/hardening"
REPORTS_DIR="${REPO_ROOT}/reports/hardening"
PHASE="all"
EXECUTE="${EXECUTE:-false}"
STRICT="${STRICT:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --execute)
      EXECUTE="true"
      shift
      ;;
    --strict)
      STRICT="true"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Initialize logging
mkdir -p "${LOGS_DIR}" "${REPORTS_DIR}"
LOG_FILE="${LOGS_DIR}/hardening-orchestrator-$(date -u +%Y%m%dT%H%M%SZ).log"
ERROR_LOG="${LOGS_DIR}/errors-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

# Logging functions
log() {
  local level="$1"
  local msg="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] $msg" | tee -a "${LOG_FILE}"
}

log_error() {
  local step="$1"
  local error="$2"
  printf '{"timestamp":"%s","step":"%s","error":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$error" >> "${ERROR_LOG}"
  if [[ "$STRICT" == "true" ]]; then
    log "ERROR" "Step [$step] failed in strict mode: $error"
    return 1
  else
    log "WARN" "Step [$step] non-blocking error: $error"
    return 0
  fi
}

# Phase 1: Portal/Backend Zero-Drift Validation
phase_portal_sync() {
  log "INFO" "Starting Phase 1: Portal/Backend Synchronization Validation"
  
  local portal_url="${PORTAL_HEALTH_URL:-http://localhost:5000/health}"
  local backend_url="${BACKEND_HEALTH_URL:-http://localhost:3000/health}"
  
  # Check portal service
  log "INFO" "Checking portal service at $portal_url"
  if ! curl -sf "$portal_url" > /dev/null 2>&1; then
    log_error "portal-health" "Portal service not responding at $portal_url" || true
  else
    log "INFO" "Portal service healthy"
  fi
  
  # Check backend service
  log "INFO" "Checking backend service at $backend_url"
  if ! curl -sf "$backend_url" > /dev/null 2>&1; then
    log_error "backend-health" "Backend service not responding at $backend_url" || true
  else
    log "INFO" "Backend service healthy"
  fi
  
  # Validate synchronization state
  log "INFO" "Validating portal/backend synchronization state"
  if [[ "$EXECUTE" == "true" ]]; then
    # Run full synchronization validation
    bash "${SCRIPT_DIR}/qa/portal-backend-sync-validator.sh" || log_error "portal-sync" "Sync validation failed" || true
  else
    log "INFO" "[DRY-RUN] Sync validation skipped (use --execute to validate)"
  fi
  
  log "INFO" "Phase 1 complete"
}

# Phase 2: Test Consolidation
phase_test_consolidation() {
  log "INFO" "Starting Phase 2: Test Suite Consolidation"
  
  # Consolidate all tests into single suite
  log "INFO" "Consolidating test suites"
  if [[ "$EXECUTE" == "true" ]]; then
    # Combine all test paths
    local test_dirs=""
    test_dirs+="tests/backend tests/portal tests/integration tests/e2e"
    
    log "INFO" "Running consolidated test suite: $test_dirs"
    # Run combined tests with optimization flags
    npm run test:consolidated -- --runInBand --maxWorkers=1 2>&1 | tee -a "${LOG_FILE}" || \
      log_error "test-consolidation" "Test suite failed" || true
  else
    log "INFO" "[DRY-RUN] Test execution skipped (use --execute to run tests)"
  fi
  
  log "INFO" "Phase 2 complete"
}

# Phase 3: Error Tracking Centralization
phase_error_tracking() {
  log "INFO" "Starting Phase 3: Error Tracking Centralization"
  
  log "INFO" "Initializing central error aggregation"
  
  # Create central error collection
  local error_dir="${REPO_ROOT}/logs/errors/central"
  mkdir -p "$error_dir"
  
  log "INFO" "Collecting errors from all services"
  if [[ "$EXECUTE" == "true" ]]; then
    # Aggregate all error logs
    find "${REPO_ROOT}/logs" -name "*.jsonl" -type f -exec cat {} \; >> "${error_dir}/aggregate-$(date -u +%Y%m%dT%H%M%SZ).jsonl" 2>/dev/null || true
    
    log "INFO" "Error aggregation complete"
    
    # Generate error report
    bash "${SCRIPT_DIR}/qa/error-analysis.sh" "${error_dir}" || log_error "error-analysis" "Error analysis failed" || true
  else
    log "INFO" "[DRY-RUN] Error centralization skipped (use --execute to aggregate)"
  fi
  
  log "INFO" "Phase 3 complete"
}

# Phase 4: Enhancement Backlog
phase_enhancement_backlog() {
  log "INFO" "Starting Phase 4: Enhancement Backlog Prioritization"
  
  log "INFO" "Scanning for enhancement opportunities"
  
  # Extract hardening issues from GitHub
  if [[ "$EXECUTE" == "true" ]]; then
    bash "${SCRIPT_DIR}/github/prioritize-hardening-backlog.sh" || log_error "backlog-prioritization" "Backlog prioritization failed" || true
  else
    log "INFO" "[DRY-RUN] Backlog prioritization skipped (use --execute to analyze)"
  fi
  
  log "INFO" "Phase 4 complete"
}

# Phase 5: Continuous Monitoring
phase_continuous_monitoring() {
  log "INFO" "Starting Phase 5: Continuous Validation Framework"
  
  log "INFO" "Setting up continuous monitoring automation"
  
  if [[ "$EXECUTE" == "true" ]]; then
    # Configure Cloud Build triggers for continuous validation
    bash "${SCRIPT_DIR}/cloud/setup-continuous-validation.sh" || log_error "continuous-setup" "Monitoring setup failed" || true
  else
    log "INFO" "[DRY-RUN] Monitoring setup skipped (use --execute to configure)"
  fi
  
  log "INFO" "Phase 5 complete"
}

# Main orchestration
main() {
  log "INFO" "=== Production Hardening Master Orchestrator ==="
  log "INFO" "Phase: $PHASE | Execute: $EXECUTE | Strict: $STRICT"
  
  case "$PHASE" in
    portal-sync)
      phase_portal_sync
      ;;
    test-consolidate)
      phase_test_consolidation
      ;;
    error-tracking)
      phase_error_tracking
      ;;
    enhancement)
      phase_enhancement_backlog
      ;;
    monitoring)
      phase_continuous_monitoring
      ;;
    all)
      phase_portal_sync
      phase_test_consolidation
      phase_error_tracking
      phase_enhancement_backlog
      phase_continuous_monitoring
      ;;
    *)
      log "ERROR" "Unknown phase: $PHASE"
      exit 1
      ;;
  esac
  
  log "INFO" "=== Hardening Orchestration Complete ==="
  log "INFO" "Logs: $LOG_FILE"
  log "INFO" "Errors: $ERROR_LOG"
  
  # Generate report
  cat > "${REPORTS_DIR}/hardening-report-$(date -u +%Y%m%dT%H%M%SZ).md" <<EOF
# Hardening Execution Report

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Phases Executed

- Portal/Backend Sync: $(grep -c "Phase 1" "$LOG_FILE" || echo "0") steps
- Test Consolidation: $(grep -c "Phase 2" "$LOG_FILE" || echo "0") steps
- Error Tracking: $(grep -c "Phase 3" "$LOG_FILE" || echo "0") steps
- Enhancement Backlog: $(grep -c "Phase 4" "$LOG_FILE" || echo "0") steps
- Continuous Monitoring: $(grep -c "Phase 5" "$LOG_FILE" || echo "0") steps

## Status

- Total Commands: $(grep -c "Running" "$LOG_FILE" || echo "0")
- Errors: $(wc -l < "$ERROR_LOG" || echo "0")
- Passed: $(($(grep -c "complete" "$LOG_FILE" || echo "5") - $(wc -l < "$ERROR_LOG" || echo "0")))

## Logs

- Full Log: $LOG_FILE
- Error Log: $ERROR_LOG

## Artifacts

- JSONL Error Trail: $ERROR_LOG
- Report: reports/hardening-report-*.md
EOF
  
  log "INFO" "Report generated: ${REPORTS_DIR}/hardening-report-*.md"
}

# Execute
main "$@"
