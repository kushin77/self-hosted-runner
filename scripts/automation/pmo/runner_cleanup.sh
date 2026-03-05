#!/bin/bash

################################################################################
# GitHub Actions Runner Cleanup Script
#
# Periodically removes stale/hung runner processes and cleans up workspaces
# to ensure optimal resource utilization.
#
# Usage:
#   ./runner_cleanup.sh [--dry-run] [--force]
################################################################################

set -euo pipefail

REPO_DIR="${RUNNER_DIR:-/home/ubuntu/actions-runner}"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
LOG_DIR="/var/log/runner-cleanup"
TIMESTAMP=$(date +%s)

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$TIMESTAMP.log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Find and cleanup stale runner processes
cleanup_stale_processes() {
  log "Checking for stale runner processes..."
  
  local stale_count=0
  while IFS= read -r pid; do
    if [[ -z "$pid" ]]; then continue; fi
    
    local elapsed=$((TIMESTAMP - $(stat -c %Y /proc/$pid 2>/dev/null || echo $TIMESTAMP)))
    if [[ $elapsed -gt 3600 ]]; then  # > 1 hour
      log "Found stale process: PID $pid (age: ${elapsed}s)"
      if [[ "$DRY_RUN" == "false" ]]; then
        kill -9 "$pid" 2>/dev/null || true
        log "  Killed PID $pid"
      fi
      ((stale_count++))
    fi
  done < <(pgrep -f "actions-runner" 2>/dev/null || true)
  
  log "Stale processes found: $stale_count"
}

# Clean up abandoned workspaces
cleanup_workspaces() {
  log "Cleaning up abandoned workspaces..."
  
  if [[ ! -d "$REPO_DIR/_work" ]]; then
    log "No work directory found"
    return 0
  fi
  
  local cleaned=0
  find "$REPO_DIR/_work" -maxdepth 1 -type d -mtime +7 2>/dev/null | while read -r workspace; do
    log "Removing abandoned workspace: $workspace"
    if [[ "$DRY_RUN" == "false" ]]; then
      rm -rf "$workspace" 2>/dev/null || true  
      ((cleaned++)) || true
    fi
  done
  
  log "Workspaces cleaned: $cleaned"
}

# Fix permissions
fix_permissions() {
  log "Fixing workspace permissions..."
  
  if [[ "$DRY_RUN" == "false" ]]; then
    chown -R ubuntu:ubuntu "$REPO_DIR" 2>/dev/null || true
    chmod -R u+rw "$REPO_DIR" 2>/dev/null || true
  fi
  
  log "Permissions fixed"
}

# Main
main() {
  log "Runner cleanup started (DRY_RUN=$DRY_RUN, FORCE=$FORCE)"
  
  cleanup_stale_processes
  cleanup_workspaces
  fix_permissions
  
  log "Runner cleanup completed"
  
  # Rotate logs older than 7 days
  find "$LOG_DIR" -name "cleanup-*.log" -mtime +7 -delete 2>/dev/null || true
}

main "$@"
