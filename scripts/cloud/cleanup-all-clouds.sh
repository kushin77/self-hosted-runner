#!/usr/bin/env bash
set -euo pipefail

# Orchestrator for complete on-prem + multi-cloud cleanup and hibernation.
# Default: dry-run (no destructive actions) unless --execute is provided.

DRY_RUN=true
STRICT=false
TARGET="all"
INCLUDE_ONPREM=true
REBOOT_CHECK=false

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${REPO_ROOT}/logs/cleanup"
LOGFILE="${LOGFILE:-${LOG_DIR}/cleanup-audit-${TIMESTAMP}.jsonl}"
ERROR_FILE="${ERROR_FILE:-${LOG_DIR}/cleanup-errors-${TIMESTAMP}.jsonl}"

mkdir -p "$LOG_DIR"
export DRY_RUN LOGFILE ERROR_FILE

usage(){
  echo "Usage: $0 [--execute] [--strict] [--skip-onprem] [--reboot-check] [--cloud gcp|aws|azure|all]"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) DRY_RUN=false; shift ;;
    --strict) STRICT=true; shift ;;
    --cloud) TARGET="$2"; shift 2 ;;
    --skip-onprem) INCLUDE_ONPREM=false; shift ;;
    --reboot-check) REBOOT_CHECK=true; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

log(){
  local msg="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$msg" '{timestamp:$ts,message:$m}' >> "$LOGFILE"
  else
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$LOGFILE"
  fi
}

log_error(){
  local msg="$1"
  log "ERROR: $msg"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$msg" '{timestamp:$ts,error:$m,source:"cleanup-all-clouds"}' >> "$ERROR_FILE"
  else
    printf '%s ERROR %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$ERROR_FILE"
  fi
}

run_script(){
  local script="$1"
  if [ ! -f "$script" ]; then
    log_error "script not found: $script"
    [ "$STRICT" = true ] && exit 1
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: would run $script"
    log "DRY-RUN: would run $script"
  else
    echo "Running $script"
    log "Running $script"
    if ! bash "$script"; then
      log_error "$script failed"
      [ "$STRICT" = true ] && exit 1
    fi
  fi
}

collect_shutdown_logs(){
  log "collecting shutdown logs"
  if command -v docker >/dev/null 2>&1; then
    docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}' > "${LOG_DIR}/docker-state-${TIMESTAMP}.log" 2>/dev/null || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-units --type=service --state=running > "${LOG_DIR}/systemd-running-${TIMESTAMP}.log" 2>/dev/null || true
  fi
}

run_reboot_checks(){
  if [ "$REBOOT_CHECK" != true ]; then
    return 0
  fi
  log "running reboot checks"
  if [ "$DRY_RUN" = true ]; then
    log "dry_run reboot check requested; no reboot commands executed"
    return 0
  fi
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -b -1 --no-pager > "${LOG_DIR}/previous-boot-${TIMESTAMP}.log" 2>/dev/null || true
  fi
}

echo "Cleanup orchestrator starting (dry-run=$DRY_RUN)" 
log "cleanup_orchestrator_start dry_run=$DRY_RUN target=$TARGET strict=$STRICT include_onprem=$INCLUDE_ONPREM"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$INCLUDE_ONPREM" = true ]; then
  run_script "$SCRIPT_DIR/onprem-cleanup-complete.sh"
fi

if [[ "$TARGET" == "gcp" || "$TARGET" == "all" ]]; then
  run_script "$SCRIPT_DIR/gcp-cleanup-complete.sh"
fi

if [[ "$TARGET" == "aws" || "$TARGET" == "all" ]]; then
  run_script "$SCRIPT_DIR/aws-cleanup-complete.sh"
fi

if [[ "$TARGET" == "azure" || "$TARGET" == "all" ]]; then
  run_script "$SCRIPT_DIR/azure-cleanup-complete.sh"
fi

run_script "$SCRIPT_DIR/cleanup-archive-verify.sh"
run_script "$SCRIPT_DIR/cleanup-cost-verify.sh"
run_script "$SCRIPT_DIR/skeleton-mode-setup.sh"

collect_shutdown_logs
run_reboot_checks

log "cleanup_orchestrator_end"
echo "Cleanup orchestrator finished (dry-run=$DRY_RUN)"
