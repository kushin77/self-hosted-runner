#!/usr/bin/env bash
##
## Update Checker Daemon
## Periodically checks for runner and platform updates.
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-3600}"  # 1 hour
REPO="${REPO:-$(git -C ${RUNNER_HOME} config --get remote.origin.url)}"
LOG_FILE="/var/log/runner-update-check.log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

check_runner_updates() {
  log "Checking for runner updates..."
  
  INSTALLED=$(${RUNNER_HOME}/bin/Runner.Listener --version 2>/dev/null | head -1)
  LATEST=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name[1:]')
  
  if [ "${INSTALLED}" != "${LATEST}" ]; then
    log "Update available: ${INSTALLED} -> v${LATEST}"
    return 0
  fi
  
  return 1
}

check_platform_updates() {
  log "Checking for platform updates..."
  
  if ! git -C "${RUNNER_HOME}" fetch origin >/dev/null 2>&1; then
    log "Failed to fetch from origin"
    return 1
  fi
  
  LOCAL_COMMIT=$(git -C "${RUNNER_HOME}" rev-parse HEAD)
  REMOTE_COMMIT=$(git -C "${RUNNER_HOME}" rev-parse origin/main)
  
  if [ "${LOCAL_COMMIT}" != "${REMOTE_COMMIT}" ]; then
    log "Platform update available"
    log "  Local:  ${LOCAL_COMMIT:0:8}"
    log "  Remote: ${REMOTE_COMMIT:0:8}"
    return 0
  fi
  
  return 1
}

apply_updates() {
  log "Applying updates..."
  
  # Gracefully stop runner
  if systemctl is-active --quiet actions-runner; then
    log "Stopping runner..."
    systemctl stop actions-runner
    sleep 5
  fi
  
  # Update platform repo
  log "Pulling platform updates..."
  if ! git -C "${RUNNER_HOME}" pull origin main; then
    log "Failed to pull platform updates, rolling back"
    git -C "${RUNNER_HOME}" reset --hard
    git -C "${RUNNER_HOME}" checkout main
  fi
  
  # Update runner binary
  if check_runner_updates; then
    log "Updating runner binary..."
    "${RUNNER_HOME}/../runner/update-runner.sh" || {
      log "Runner update failed"
      return 1
    }
  fi
  
  # Restart runner
  log "Restarting runner..."
  systemctl start actions-runner
  
  log "✓ Updates applied successfully"
}

should_apply_updates() {
  # Don't apply updates during busy hours (9-5 UTC)
  local hour=$(date -u +%H)
  if [ "${hour}" -ge 9 ] && [ "${hour}" -le 17 ]; then
    log "Skipping updates during business hours"
    return 1
  fi
  
  # Check if any jobs are running
  if pgrep -f "Runner.Listener" >/dev/null; then
    # Wait for job to complete (max 30 minutes)
    for i in {1..90}; do
      if ! pgrep -f "Runner.Listener" >/dev/null; then
        sleep 30
        return 0
      fi
      sleep 20
    done
    log "Job still running after 30min, deferring update"
    return 1
  fi
  
  return 0
}

main_loop() {
  while true; do
    log "Update check cycle..."
    
    if check_runner_updates || check_platform_updates; then
      if should_apply_updates; then
        apply_updates
      fi
    else
      log "No updates available"
    fi
    
    log "Next check in ${UPDATE_INTERVAL}s"
    sleep "${UPDATE_INTERVAL}"
  done
}

main_loop
