#!/bin/bash
################################################################################
# Master CI/CD Orchestration Script
# Coordinates all validation, testing, security scanning, and deployment steps
# Fully automated, idempotent, hands-off - NO GitHub Actions
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs/ci"
MASTER_LOG="${LOG_DIR}/orchestration.jsonl"
CI_SCRIPT_DIR="$SCRIPT_DIR/ci"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)
BUILD_ID="${BUILD_ID:-local-$(date +%s)}"

mkdir -p "$LOG_DIR"

log_orchestration() {
  local status="$1"
  local event="$2"
  echo "{\"timestamp\":\"${TIMESTAMP}\",\"build_id\":\"${BUILD_ID}\",\"hostname\":\"${HOSTNAME}\",\"event\":\"${event}\",\"status\":\"${status}\"}" >> "$MASTER_LOG"
  
  case "$status" in
    start) echo "🚀 $event" ;;
    success) echo "✅ $event" ;;
    failure) echo "❌ $event" >&2 ;;
  esac
}

main() {
  local command="${1:-all}"
  local start_time=$(date +%s)
  
  echo ""
  echo "╔════════════════════════════════════════════════════╗"
  echo "║       NexusShield CI/CD Orchestration             ║"
  echo "║      NO GitHub Actions - Direct Execution         ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo ""
  
  log_orchestration "start" "PIPELINE_START_$command"
  
  case "$command" in
    validate)
      "$CI_SCRIPT_DIR/validate.sh" || exit 1
      ;;
    test)
      "$CI_SCRIPT_DIR/test.sh" --coverage || exit 1
      ;;
    security)
      "$CI_SCRIPT_DIR/security-scan.sh" || exit 1
      ;;
    all)
      "$CI_SCRIPT_DIR/validate.sh" || exit 1
      "$CI_SCRIPT_DIR/test.sh" --coverage || exit 1
      "$CI_SCRIPT_DIR/security-scan.sh" || exit 1
      ;;
    *)
      echo "Usage: $0 {validate|test|security|all}"
      exit 1
      ;;
  esac
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  echo ""
  log_orchestration "success" "PIPELINE_COMPLETE_${command}"
  echo "✅ Pipeline completed in ${duration}s"
  echo ""
}

main "$@"
