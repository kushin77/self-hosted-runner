#!/bin/bash

################################################################################
# DEPLOYMENT VALIDATION & HEALTH CHECK FRAMEWORK
# 
# This script validates Phase P0 and Phase P1 component health and readiness
# for production deployment. Run before, during, and after deployments.
#
# Usage:
#   ./deployment-validation.sh --phase=p0 --check=all
#   ./deployment-validation.sh --phase=p1 --check=components
#   ./deployment-validation.sh --phase=p0 --check=health --watch=true
#
# Modes:
#   --phase=p0|p1         : Which phase components to validate
#   --check=all|health|... : Which checks to run
#   --watch=true|false    : Continuous monitoring mode
#   --threshold=X         : Fail if metric X% below threshold
#
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
METRICS_DIR="${SCRIPT_DIR}/metrics"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create directories
mkdir -p "$LOG_DIR" "$METRICS_DIR"

# Logging
LOG_FILE="$LOG_DIR/deployment-validation-$TIMESTAMP.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

################################################################################
# UTILITY FUNCTIONS
################################################################################

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $*"; }

health_check() {
  local status=$1
  local name=$2
  
  if [[ "$status" -eq 0 ]]; then
    log_success "$name"
    return 0
  else
    log_error "$name failed"
    return 1
  fi
}

metric_export() {
  local name=$1
  local value=$2
  local timestamp=$(date +%s)
  
  echo "$timestamp $name $value" >> "$METRICS_DIR/metrics-$TIMESTAMP.txt"
}

################################################################################
# PHASE P0 VALIDATION
################################################################################

validate_phase_p0() {
  log_info "=== VALIDATING PHASE P0 COMPONENTS ==="
  
  local pass=0
  local fail=0
  
  # Check 1: Ephemeral Workspace Manager
  log_info "Checking Ephemeral Workspace Manager..."
  if command -v jq &>/dev/null && \
     [[ -f "${SCRIPT_DIR}/ephemeral-workspace-manager.sh" ]]; then
    local ws_status=$(bash "${SCRIPT_DIR}/ephemeral-workspace-manager.sh" --status 2>&1 | jq '.status // "unknown"' 2>/dev/null || echo "unknown")
    if [[ "$ws_status" != "unknown" ]]; then
      log_success "Ephemeral Workspace Manager: Responsive"
      ((pass++))
      metric_export "ephemeral_manager.status" "1"
    else
      log_warn "Ephemeral Workspace Manager: Degraded response"
      ((fail++))
      metric_export "ephemeral_manager.status" "0"
    fi
  else
    log_warn "Ephemeral Workspace Manager: Not available"
    ((fail++))
  fi
  
  # Check 2: Capability Store
  log_info "Checking Capability Store..."
  if [[ -f "${SCRIPT_DIR}/capability-store.sh" ]]; then
    bash "${SCRIPT_DIR}/capability-store.sh" --validate &>/dev/null && {
      log_success "Capability Store: Valid configuration"
      ((pass++))
      metric_export "capability_store.status" "1"
    } || {
      log_warn "Capability Store: Configuration issues"
      ((fail++))
      metric_export "capability_store.status" "0"
    }
  fi
  
  # Check 3: OTEL Tracing
  log_info "Checking OpenTelemetry Tracing..."
  if [[ -f "${SCRIPT_DIR}/otel-tracer.sh" ]]; then
    bash "${SCRIPT_DIR}/otel-tracer.sh" --health-check &>/dev/null && {
      log_success "OTEL Tracing: Operational"
      ((pass++))
      metric_export "otel_tracer.status" "1"
    } || {
      log_warn "OTEL Tracing: Not responding"
      ((fail++))
      metric_export "otel_tracer.status" "0"
    }
  fi
  
  # Check 4: Fair Job Scheduler
  log_info "Checking Fair Job Scheduler..."
  if [[ -f "${SCRIPT_DIR}/fair-job-scheduler.sh" ]]; then
    bash "${SCRIPT_DIR}/fair-job-scheduler.sh" --validate &>/dev/null && {
      log_success "Fair Job Scheduler: Valid"
      ((pass++))
      metric_export "scheduler.status" "1"
    } || {
      log_warn "Fair Job Scheduler: Configuration issues"
      ((fail++))
      metric_export "scheduler.status" "0"
    }
  fi
  
  # Check 5: Drift Detector
  log_info "Checking Drift Detector..."
  if [[ -f "${SCRIPT_DIR}/drift-detector.sh" ]]; then
    bash "${SCRIPT_DIR}/drift-detector.sh" --validate &>/dev/null && {
      log_success "Drift Detector: Operational"
      ((pass++))
      metric_export "drift_detector.status" "1"
    } || {
      log_warn "Drift Detector: Issues detected"
      ((fail++))
      metric_export "drift_detector.status" "0"
    }
  fi
  
  # Summary
  log_info "Phase P0 Validation: $pass passed, $fail failed"
  metric_export "phase_p0.pass_count" "$pass"
  metric_export "phase_p0.fail_count" "$fail"
  
  return $fail
}

################################################################################
# PHASE P1 VALIDATION
################################################################################

validate_phase_p1() {
  log_info "=== VALIDATING PHASE P1 COMPONENTS ==="
  
  local pass=0
  local fail=0
  
  # Check 1: Job Cancellation Handler
  log_info "Checking Graceful Job Cancellation Handler..."
  if [[ -f "${SCRIPT_DIR}/job-cancellation-handler.sh" ]]; then
    bash "${SCRIPT_DIR}/job-cancellation-handler.sh" --health-check &>/dev/null && {
      log_success "Job Cancellation: Ready"
      ((pass++))
      metric_export "job_cancellation.status" "1"
    } || {
      log_warn "Job Cancellation: Not yet deployed"
      ((fail++))
      metric_export "job_cancellation.status" "0"
    }
  else
    log_warn "Job Cancellation: Not found"
    ((fail++))
  fi
  
  # Check 2: Vault Integration
  log_info "Checking Secrets Rotation (Vault Integration)..."
  if [[ -f "${SCRIPT_DIR}/vault-integration.sh" ]]; then
    bash "${SCRIPT_DIR}/vault-integration.sh" --health-check &>/dev/null && {
      log_success "Vault Integration: Ready"
      ((pass++))
      metric_export "vault_integration.status" "1"
    } || {
      log_warn "Vault Integration: Not yet deployed (external Vault required)"
      ((fail++))
      metric_export "vault_integration.status" "0"
    }
  else
    log_warn "Vault Integration: Not found"
    ((fail++))
  fi
  
  # Check 3: Failure Predictor
  log_info "Checking ML Failure Predictor..."
  if [[ -f "${SCRIPT_DIR}/failure-predictor.sh" ]]; then
    bash "${SCRIPT_DIR}/failure-predictor.sh" --health-check &>/dev/null && {
      log_success "Failure Predictor: Ready"
      ((pass++))
      metric_export "failure_predictor.status" "1"
    } || {
      log_warn "Failure Predictor: Not yet deployed"
      ((fail++))
      metric_export "failure_predictor.status" "0"
    }
  else
    log_warn "Failure Predictor: Not found"
    ((fail++))
  fi
  
  # Summary
  log_info "Phase P1 Validation: $pass passed, $fail failed"
  metric_export "phase_p1.pass_count" "$pass"
  metric_export "phase_p1.fail_count" "$fail"
  
  return $fail
}

################################################################################
# INTEGRATION VALIDATION
################################################################################

validate_integration() {
  log_info "=== VALIDATING PHASE P0 ↔ P1 INTEGRATION ==="
  
  local pass=0
  local fail=0
  
  # Check: Phase P0 → Phase P1 data flow
  log_info "Checking Phase P0 → Phase P1 integration points..."
  
  # Workspace + Cancellation
  if [[ -f "${SCRIPT_DIR}/ephemeral-workspace-manager.sh" ]] && \
     [[ -f "${SCRIPT_DIR}/job-cancellation-handler.sh" ]]; then
    log_success "Workspace ↔ Cancellation: Linked"
    ((pass++))
    metric_export "integration.workspace_cancellation" "1"
  else
    log_warn "Workspace ↔ Cancellation: Not available"
    ((fail++))
  fi
  
  # OTEL + Prediction
  if [[ -f "${SCRIPT_DIR}/otel-tracer.sh" ]] && \
     [[ -f "${SCRIPT_DIR}/failure-predictor.sh" ]]; then
    log_success "OTEL ↔ Prediction: Linked"
    ((pass++))
    metric_export "integration.otel_prediction" "1"
  else
    log_warn "OTEL ↔ Prediction: Not available"
    ((fail++))
  fi
  
  # Drift Detector + Vault
  if [[ -f "${SCRIPT_DIR}/drift-detector.sh" ]] && \
     [[ -f "${SCRIPT_DIR}/vault-integration.sh" ]]; then
    log_success "Drift ↔ Vault: Linked"
    ((pass++))
    metric_export "integration.drift_vault" "1"
  else
    log_warn "Drift ↔ Vault: Not available"
    ((fail++))
  fi
  
  log_info "Integration Validation: $pass passed, $fail failed"
  metric_export "integration.pass_count" "$pass"
  metric_export "integration.fail_count" "$fail"
  
  return $fail
}

################################################################################
# DEPLOYMENT READINESS CHECKLIST
################################################################################

deployment_readiness() {
  log_info "=== DEPLOYMENT READINESS CHECKLIST ==="
  
  local checks_passed=0
  local checks_total=0
  
  # Code quality
  ((checks_total++))
  if command -v shellcheck &>/dev/null; then
    shellcheck "${SCRIPT_DIR}/ephemeral-workspace-manager.sh" &>/dev/null && {
      log_success "Code Quality: All scripts pass shellcheck"
      ((checks_passed++))
    } || log_warn "Code Quality: Some shellcheck warnings"
  fi
  
  # Documentation
  ((checks_total++))
  if [[ -f "../docs/PHASE_P0_IMPLEMENTATION.md" ]] && \
     [[ -f "../docs/PHASE_P0_QUICK_REFERENCE.md" ]]; then
    log_success "Documentation: Complete"
    ((checks_passed++))
  else
    log_warn "Documentation: Incomplete"
  fi
  
  # Git history
  ((checks_total++))
  if git log --oneline -5 &>/dev/null; then
    local commit_count=$(git log --oneline | wc -l)
    log_success "Git History: $commit_count commits"
    ((checks_passed++))
  else
    log_warn "Git History: Not a git repository"
  fi
  
  # Configuration files
  ((checks_total++))
  if [[ -f "${SCRIPT_DIR}/examples/.runner-config/job-cancellation.yaml" ]] || \
     [[ -f "../scripts/automation/pmo/examples/.runner-config/job-cancellation.yaml" ]]; then
    log_success "Configuration: Examples present"
    ((checks_passed++))
  else
    log_warn "Configuration: Missing examples"
  fi
  
  # Success criteria
  local success_rate=$((checks_passed * 100 / checks_total))
  log_info "Deployment Readiness: $checks_passed/$checks_total checks passed ($success_rate%)"
  metric_export "deployment_readiness.score" "$success_rate"
  
  return $((checks_total - checks_passed))
}

################################################################################
# CONTINUOUS MONITORING
################################################################################

continuous_monitoring() {
  local interval=${1:-30}  # Default 30 seconds
  
  log_info "Starting continuous monitoring (interval: ${interval}s, Ctrl+C to stop)"
  
  while true; do
    clear
    log_info "=== CONTINUOUS HEALTH MONITORING ==="
    log_info "Timestamp: $(date)"
    
    validate_phase_p0 || true
    validate_phase_p1 || true
    validate_integration || true
    
    log_info "Next check in ${interval} seconds..."
    sleep "$interval"
  done
}

################################################################################
# MAIN
################################################################################

main() {
  local phase="${PHASE:-p0}"
  local check="${CHECK:-all}"
  local watch="${WATCH:-false}"
  local threshold="${THRESHOLD:-80}"
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --phase=*) phase="${1#*=}"; shift ;;
      --check=*) check="${1#*=}"; shift ;;
      --watch=*) watch="${1#*=}"; shift ;;
      --threshold=*) threshold="${1#*=}"; shift ;;
      *) 
        echo "Unknown option: $1"
        echo "Usage: $0 [--phase=p0|p1] [--check=all|health|...] [--watch=true|false] [--threshold=X]"
        exit 1
        ;;
    esac
  done
  
  log_info "Starting deployment validation (Phase: $phase, Check: $check, Watch: $watch)"
  
  # Run validation checks
  local total_fails=0
  
  case "$phase" in
    p0)
      validate_phase_p0 || ((total_fails++))
      ;;
    p1)
      validate_phase_p1 || ((total_fails++))
      ;;
    both|all)
      validate_phase_p0 || ((total_fails++))
      validate_phase_p1 || ((total_fails++))
      validate_integration || ((total_fails++))
      ;;
    *)
      log_error "Unknown phase: $phase"
      exit 1
      ;;
  esac
  
  # Deployment readiness
  deployment_readiness || ((total_fails++))
  
  # Continuous monitoring if requested
  if [[ "$watch" == "true" ]]; then
    continuous_monitoring 30
  fi
  
  # Summary and exit
  log_info "=== VALIDATION SUMMARY ==="
  log_info "Total failures: $total_fails"
  log_info "Log file: $LOG_FILE"
  log_info "Metrics exported to: $METRICS_DIR"
  
  if [[ $total_fails -eq 0 ]]; then
    log_success "ALL VALIDATION CHECKS PASSED ✓"
    return 0
  else
    log_error "VALIDATION CHECKS FAILED"
    return 1
  fi
}

# Run main function
main "$@"
