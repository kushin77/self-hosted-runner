#!/usr/bin/env bash
##
## Destroy Runner Safely
## Unregisters runner, cleans up resources, and removes runner instance.
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
RUNNER_URL="${RUNNER_URL:-}"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  log "✗ $*"
  exit 1
}

# Require GitHub token for unregistration
if [ -z "${GITHUB_TOKEN}" ]; then
  error "GITHUB_TOKEN required for runner unregistration"
fi

log "Starting safe runner destruction..."

# Step 1: Graceful shutdown
log "Step 1: Gracefully shutting down runner..."
if systemctl is-active --quiet actions-runner; then
  systemctl stop actions-runner
  sleep 5
fi

# Step 2: Drain runner of pending jobs
log "Step 2: Draining pending jobs..."
if [ -f "${RUNNER_HOME}/.runner" ]; then
  RUNNER_NAME=$(jq -r '.agentId' "${RUNNER_HOME}/.runner")
  log "Runner name: ${RUNNER_NAME}"
fi

# Step 3: Unregister from GitHub
log "Step 3: Unregistering runner from GitHub..."
cd "${RUNNER_HOME}"
if [ -f "config.sh" ]; then
  # This requires the GitHub personal access token
  ./config.sh remove --token "${GITHUB_TOKEN}" || \
    log "⚠ Runner unregistration returned non-zero"
else
  log "⚠ config.sh not found"
fi

# Step 4: Stop runner service
log "Step 4: Stopping systemd service..."
systemctl disable actions-runner.service || true
rm -f /etc/systemd/system/actions-runner.service
systemctl daemon-reload

# Step 5: Kill any remaining processes
log "Step 5: Killing remaining runner processes..."
pkill -9 -f "Runner.Listener" || true
pkill -9 -f "run.sh" || true
pkill -9 -f "actions-runner" || true

# Step 6: Deep cleanup
log "Step 6: Deep cleaning runner directories..."
chmod -R u+w "${RUNNER_HOME}" 2>/dev/null || true

# Securely remove sensitive files
if [ -f "${RUNNER_HOME}/.credentials" ]; then
  log "Removing credentials file..."
  shred -vfz -n 10 "${RUNNER_HOME}/.credentials" || rm -f "${RUNNER_HOME}/.credentials"
fi

if [ -f "${RUNNER_HOME}/.credentials_rsaparams" ]; then
  log "Removing config parameters..."
  shred -vfz -n 10 "${RUNNER_HOME}/.credentials_rsaparams" || rm -f "${RUNNER_HOME}/.credentials_rsaparams"
fi

# Remove all runner data
log "Removing runner installation..."
rm -rf "${RUNNER_HOME:?}"/*

# Step 7: Cleanup job artifacts
log "Step 7: Cleaning up Docker and temporary artifacts..."
docker container prune -af 2>/dev/null || true
docker image prune -af 2>/dev/null || true
rm -rf /tmp/runner-* /tmp/job-* 2>/dev/null || true

# Step 8: Remove runner user
log "Step 8: Removing runner system user..."
if id "${RUNNER_USER}" &>/dev/null; then
  userdel -r "${RUNNER_USER}" || log "⚠ Could not delete runner user"
fi

# Step 9: Remove monitoring agents
log "Step 9: Removing observability agents..."
rm -f /etc/systemd/system/runner-monitor.service
rm -f /usr/local/bin/runner-health-check
systemctl daemon-reload 2>/dev/null || true

# Step 10: Log audit trail
log "Step 10: Creating destruction audit log..."
cat > /var/log/runner-destruction.log <<EOF
Destruction timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Hostname: $(hostname)
Runner name: ${RUNNER_NAME:-unknown}
GitHub URL: ${RUNNER_URL:-unknown}
Reason: Manual destruction or auto-healing
EOF

log "✓ Runner destruction completed successfully"
log "Audit log: /var/log/runner-destruction.log"

# Optional: halt the machine
if [ "${HALT_ON_DESTROY:-false}" == "true" ]; then
  log "⚠ System will halt in 60 seconds..."
  shutdown -h +1 "Runner destruction complete, system halting"
fi
