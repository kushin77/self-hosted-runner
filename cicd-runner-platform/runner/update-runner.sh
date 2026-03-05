#!/usr/bin/env bash
##
## Self-Update Runner
## Checks for updates and applies them automatically.
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"
UPDATE_CHECK_INTERVAL="${UPDATE_CHECK_INTERVAL:-3600}"  # 1 hour

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

get_installed_version() {
  "${RUNNER_HOME}/bin/Runner.Listener" --version 2>/dev/null | head -1 || echo "unknown"
}

get_latest_version() {
  curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name[1:]'
}

perform_update() {
  log "Stopping runner for update..."
  
  # Graceful shutdown
  if systemctl is-active --quiet actions-runner; then
    systemctl stop actions-runner
    sleep 5
  fi
  
  log "Downloading update..."
  NEW_VERSION=$(get_latest_version)
  FILENAME="actions-runner-linux-x64-v${NEW_VERSION}.tar.gz"
  DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${NEW_VERSION}/${FILENAME}"
  
  cd "${RUNNER_HOME}"
  curl -L -o "${FILENAME}" "${DOWNLOAD_URL}" || {
    log "Failed to download update"
    return 1
  }
  
  # Backup current version
  BACKUP_DIR="/var/backups/runner-${OLD_VERSION}-$(date +%s)"
  mkdir -p "${BACKUP_DIR}"
  cp -r "${RUNNER_HOME}"/* "${BACKUP_DIR}/"
  
  log "Extracting update..."
  tar xzf "${FILENAME}"
  rm "${FILENAME}"
  
  chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"
  
  log "Restarting runner..."
  systemctl start actions-runner
  
  log "✓ Runner updated to ${NEW_VERSION}"
  log "  Backup available at: ${BACKUP_DIR}"
}

rollback() {
  log "Rolling back to previous version..."
  LATEST_BACKUP=$(ls -td /var/backups/runner-* 2>/dev/null | head -1)
  
  if [ -z "${LATEST_BACKUP}" ]; then
    log "No backup available for rollback"
    return 1
  fi
  
  systemctl stop actions-runner 2>/dev/null || true
  
  rm -rf "${RUNNER_HOME:?}"/*
  cp -r "${LATEST_BACKUP}"/* "${RUNNER_HOME}/"
  
  systemctl start actions-runner
  log "✓ Rolled back from ${LATEST_BACKUP}"
}

monitor_health() {
  # Wait for runner to stabilize after update
  sleep 10
  
  if ! "${RUNNER_HOME}/bin/Runner.Listener" --version &>/dev/null; then
    log "Health check failed, initiating rollback..."
    rollback
    return 1
  fi
  
  log "✓ Health check passed"
  return 0
}

main() {
  OLD_VERSION=$(get_installed_version)
  NEW_VERSION=$(get_latest_version)
  
  log "Current version: ${OLD_VERSION}"
  log "Latest version:  ${NEW_VERSION}"
  
  if [ "${OLD_VERSION}" == "${NEW_VERSION}" ]; then
    log "Already on latest version"
    return 0
  fi
  
  log "Update available! Performing update..."
  perform_update || return 1
  monitor_health || return 1
  
  log "✓ Update completed successfully"
}

main "$@"
