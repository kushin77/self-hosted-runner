#!/usr/bin/env bash
##
## Clean Runner Workspace
## Removes all job artifacts and temporary files after job completion.
## Implements: "Never trust the workspace after a job completes."
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

cleanup_workspace() {
  log "Cleaning runner workspace: ${RUNNER_HOME}"
  
  # Remove job directories
  if [ -d "${RUNNER_HOME}/_work" ]; then
    log "Removing job data..."
    find "${RUNNER_HOME}/_work" -type f -delete
    find "${RUNNER_HOME}/_work" -type d -empty -delete
  fi
  
  # Remove temporary directories
  log "Removing temporary files..."
  rm -rf /tmp/job-* /tmp/runner-* 2>/dev/null || true
  
  # Clean Docker containers and images (job artifacts)
  log "Cleaning Docker artifacts..."
  docker container prune -f --filter "label=job=*" || true
  
  # Wipe environment variables (secrets may be leaked)
  log "Wiping job-specific environment..."
  unset $(env | grep -E "^(RUNNER_|WORKFLOW_|GITHUB_)" | cut -d= -f1) || true
  
  # Clear bash history
  history -c
  cat /dev/null > ~/.bash_history
  
  # Clear shell history files
  rm -f ~/.bash_history ~/.zsh_history ~/.history 2>/dev/null || true
  
  # Securely wipe free space (optional, can be slow)
  log "Securely wiping free space..."
  if [ "${SECURE_WIPE:-false}" == "true" ]; then
    # Use dd with /dev/zero to overwrite free space
    dd if=/dev/zero of="${RUNNER_HOME}/.wipe" bs=1M count=1000 2>/dev/null || true
    rm -f "${RUNNER_HOME}/.wipe"
  fi
}

disable_swap() {
  log "Disabling swap for security..."
  sudo swapoff -a 2>/dev/null || log "Swap already off"
}

reset_network() {
  log "Resetting network state..."
  sudo ip route flush cache 2>/dev/null || true
  sudo iptables -F 2>/dev/null || true
}

verify_clean() {
  log "Verifying workspace cleanliness..."
  
  # Check for any remaining job artifacts
  if find "${RUNNER_HOME}/_work" -type f 2>/dev/null | grep -q .; then
    log "⚠ Warning: Found remaining files in _work"
    return 1
  fi
  
  # Check for environment variables
  if env | grep -q "^RUNNER_"; then
    log "⚠ Warning: Sensitive environment variables still set"
    return 1
  fi
  
  log "✓ Workspace verification passed"
  return 0
}

main() {
  log "Starting workspace cleanup..."
  
  cleanup_workspace
  disable_swap
  reset_network
  verify_clean
  
  log "✓ Workspace cleanup completed"
}

main "$@"
