#!/usr/bin/env bash
set -euo pipefail

# Orchestrator for complete multi-cloud cleanup and hibernation
# Default: dry-run (no destructive actions) unless --execute provided

DRY_RUN=true
LOGFILE="/var/log/cleanup-audit.jsonl"

usage(){
  echo "Usage: $0 [--execute] [--cloud gcp|aws|azure|all]"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) DRY_RUN=false; shift ;;
    --cloud) TARGET="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

TARGET=${TARGET:-all}

log(){
  local msg="$1"
  command -v jq >/dev/null 2>&1 || { echo "jq required for logging" >&2; exit 1; }
  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$msg" '{timestamp:$ts,message:$m}' >> "$LOGFILE"
}

run_script(){
  local script="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: would run $script"
    log "DRY-RUN: would run $script"
  else
    echo "Running $script"
    log "Running $script"
    bash "$script" || { log "ERROR: $script failed"; exit 1; }
  fi
}

echo "Cleanup orchestrator starting (dry-run=$DRY_RUN)" 
log "cleanup_orchestrator_start dry_run=$DRY_RUN target=$TARGET"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

log "cleanup_orchestrator_end"
echo "Cleanup orchestrator finished (dry-run=$DRY_RUN)"
