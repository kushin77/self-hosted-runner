#!/usr/bin/env bash
# Self-Hosted Daemon Scheduler for Credential Management
# Purpose: Replace GitHub Actions workflows with local daemon-based scheduling
# Runs continuously and executes credential rotation + health checks on schedule
# 
# Guarantees: Immutable, Ephemeral, Idempotent, No-ops, Hands-off

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_LOG="${REPO_ROOT}/logs/daemon-scheduler.log"
DAEMON_PID_FILE="${REPO_ROOT}/.daemon.pid"
STATE_DIR="${REPO_ROOT}/.daemon-state"
LOCK_FILE="${STATE_DIR}/.scheduler.lock"

# Ensure directories exist
mkdir -p "${REPO_ROOT}/logs" "${STATE_DIR}"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${DAEMON_LOG}"
}

# Cleanup function
cleanup() {
    log "INFO" "Daemon shutting down gracefully..."
    if [ -f "${DAEMON_PID_FILE}" ]; then
        rm -f "${DAEMON_PID_FILE}"
    fi
    if [ -f "${LOCK_FILE}" ]; then
        rm -f "${LOCK_FILE}"
    fi
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGTERM SIGINT

# Check if already running
if [ -f "${DAEMON_PID_FILE}" ]; then
    OLD_PID=$(cat "${DAEMON_PID_FILE}")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "WARN" "Daemon already running with PID $OLD_PID"
        exit 1
    else
        log "INFO" "Removing stale PID file"
        rm -f "${DAEMON_PID_FILE}"
    fi
fi

# Write our PID
echo $$ > "${DAEMON_PID_FILE}"

log "INFO" "Self-hosted daemon scheduler starting (PID: $$)"
log "INFO" "Repository root: ${REPO_ROOT}"

# Track next execution times
LAST_ROTATION=$(date +%s)
LAST_HEALTH_CHECK=$(date +%s)
ROTATION_INTERVAL=$((15 * 60))  # 15 minutes
HEALTH_CHECK_INTERVAL=$((60 * 60))  # 1 hour

log "INFO" "Rotation interval: ${ROTATION_INTERVAL}s (every 15 min)"
log "INFO" "Health check interval: ${HEALTH_CHECK_INTERVAL}s (every 1 hour)"

# Main loop
while true; do
    NOW=$(date +%s)
    
    # Check if credential rotation is due
    if [ $((NOW - LAST_ROTATION)) -ge ${ROTATION_INTERVAL} ]; then
        log "INFO" "Running credential rotation..."
        
        # Execute with idempotency check
        if [ -f "${LOCK_FILE}" ]; then
            log "WARN" "Rotation already in progress, skipping..."
        else
            (
                flock -n 200 || exit 1
                
                if bash "${REPO_ROOT}/scripts/auto-credential-rotation.sh" rotate; then
                    log "INFO" "✓ Credential rotation completed successfully"
                else
                    log "ERROR" "✗ Credential rotation failed"
                fi
                
            ) 200>"${LOCK_FILE}" || log "WARN" "Could not acquire lock for rotation"
        fi
        
        LAST_ROTATION=${NOW}
    fi
    
    # Check if health check is due
    if [ $((NOW - LAST_HEALTH_CHECK)) -ge ${HEALTH_CHECK_INTERVAL} ]; then
        log "INFO" "Running credential health check..."
        
        if bash "${REPO_ROOT}/scripts/credential-monitoring.sh" all > /tmp/health-check-$$.log 2>&1; then
            log "INFO" "✓ Health check passed"
            cat /tmp/health-check-$$.log | tail -5 | xargs -I {} log "INFO" "  {}"
        else
            log "ERROR" "✗ Health check failed - escalating"
            cat /tmp/health-check-$$.log | tail -5 | xargs -I {} log "ERROR" "  {}"
            # TODO: Escalation logic (GitHub issue, Slack alert, etc.)
        fi
        
        rm -f /tmp/health-check-$$.log
        LAST_HEALTH_CHECK=${NOW}
    fi
    
    # Sleep for 30 seconds before next check (responsive but not CPU-hungry)
    sleep 30
done
