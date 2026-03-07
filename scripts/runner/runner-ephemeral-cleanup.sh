#!/usr/bin/env bash
set -euo pipefail

# scripts/runner/runner-ephemeral-cleanup.sh
# Purpose: Enforce ephemeral/immutable behavior by wiping runner state on restart
# Ensures the runner starts in a clean, reproducible state every time

RUNNER_HOME="${RUNNER_HOME:-.}"
WORK_DIR="${WORK_DIR:-$RUNNER_HOME/_work}"
TEMP_DIRS=("$WORK_DIR" "/tmp/runner-*" "/var/tmp/runner-*")

log_info() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [ephemeral-cleanup] $*" >&2
}

log_error() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [ephemeral-cleanup] ERROR: $*" >&2
}

# Idempotent cleanup: only remove if exists
cleanup_work_directory() {
  if [ -d "$WORK_DIR" ]; then
    log_info "Removing work directory: $WORK_DIR"
    rm -rf "$WORK_DIR" || log_error "Failed to remove $WORK_DIR (may require elevated privileges)"
  else
    log_info "Work directory already clean: $WORK_DIR"
  fi
}

# Cleanup temporary artifacts
cleanup_temp_artifacts() {
  log_info "Cleaning temporary runner artifacts"
  for pattern in "${TEMP_DIRS[@]}"; do
    # Use find with -delete for safe recursive removal
    if [ -e "${pattern%%-*}" ] 2>/dev/null; then
      find "${pattern%%-*}" -name "runner-*" -type d -prune -exec rm -rf {} + 2>/dev/null || true
    fi
  done
}

# Purge cache if configured
cleanup_cache() {
  CACHE_DIR="${CACHE_DIR:-}"
  if [ -n "$CACHE_DIR" ] && [ -d "$CACHE_DIR" ]; then
    log_info "Purging cache directory: $CACHE_DIR"
    rm -rf "$CACHE_DIR" || log_error "Failed to purge cache"
  fi
}

# Verify immutability: ensure no runner state remains
verify_ephemeral_state() {
  log_info "Verifying ephemeral state (no leftover runner artifacts)"
  
  LEFTOVER_FILES=$(find "$RUNNER_HOME" -name "*.state" -o -name "*.lock" 2>/dev/null | wc -l)
  if [ "$LEFTOVER_FILES" -gt 0 ]; then
    log_error "Found $LEFTOVER_FILES leftover state files; cleanup may be incomplete"
    return 1
  fi
  
  log_info "✓ Ephemeral state verified: runner is ready for clean restart"
  return 0
}

# Main execution
main() {
  log_info "=== Ephemeral Runner Cleanup START ==="
  log_info "Runner home: $RUNNER_HOME"
  
  cleanup_work_directory
  cleanup_temp_artifacts
  cleanup_cache
  
  if verify_ephemeral_state; then
    log_info "=== Ephemeral Runner Cleanup SUCCESS ==="
    return 0
  else
    log_error "=== Ephemeral Runner Cleanup INCOMPLETE ==="
    return 1
  fi
}

main "$@"
