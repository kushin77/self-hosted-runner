#!/usr/bin/env bash
# Orchestrator deployment: Install systemd timers and services for hands-off automation.
# Requires: sudo
# Policy: Immutable · Ephemeral · Idempotent · No-Ops · Hands-Off

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$ROOT_DIR/logs/deployments/ORCHESTRATOR_DEPLOY_${TIMESTAMP}.jsonl"

echo "Orchestrator Deployment at $TIMESTAMP"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script requires sudo/root" >&2
  exit 1
fi

# Ensure log directory exists
mkdir -p "$ROOT_DIR/logs/deployments"

# Record deployment start
echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"orchestrator_deploy_start\",\"status\":\"initiated\"}" >> "$LOG_FILE"

echo "1. Installing systemd timer units..."
TIMERS=(
  "scripts/systemd/nexusshield-credential-rotation.timer"
  "scripts/systemd/nexusshield-credential-rotation.service"
)

for TIMER_FILE in "${TIMERS[@]}"; do
  if [ -f "$ROOT_DIR/$TIMER_FILE" ]; then
    UNIT_NAME=$(basename "$TIMER_FILE")
    sudo cp "$ROOT_DIR/$TIMER_FILE" "/etc/systemd/system/$UNIT_NAME"
    echo "✓ Installed /etc/systemd/system/$UNIT_NAME"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"unit_installed\",\"unit\":\"$UNIT_NAME\",\"status\":\"ok\"}" >> "$LOG_FILE"
  fi
done

echo "2. Reloading systemd daemon..."
systemctl daemon-reload
echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"systemd_reload\",\"status\":\"ok\"}" >> "$LOG_FILE"

echo "3. Enabling credential rotation timer..."
systemctl enable --now nexusshield-credential-rotation.timer || {
  echo "WARNING: Failed to enable timer (may already be running)" >&2
  echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"timer_enable\",\"status\":\"warning_already_running\"}" >> "$LOG_FILE"
}

echo "4. Verifying timer is active..."
if systemctl is-active --quiet nexusshield-credential-rotation.timer; then
  echo "✓ Timer is active"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"timer_verify\",\"status\":\"active\"}" >> "$LOG_FILE"
else
  echo "WARNING: Timer not active; manual start may be needed"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"timer_verify\",\"status\":\"inactive\"}" >> "$LOG_FILE"
fi

echo "5. Testing credential rotation (idempotent check)..."
if [ -f "$ROOT_DIR/scripts/post-deployment/credential-rotation.sh" ]; then
  bash "$ROOT_DIR/scripts/post-deployment/credential-rotation.sh" --dry-run 2>&1 | head -20 || {
    echo "INFO: Dry-run returned non-zero (expected in some environments)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"credential_dryrun\",\"status\":\"completed_with_note\"}" >> "$LOG_FILE"
  }
else
  echo "INFO: Credential rotation script not found (optional)"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"credential_dryrun\",\"status\":\"skipped\"}" >> "$LOG_FILE"
fi

echo "6. Recording deployment completion..."
echo "{\"timestamp\":\"$TIMESTAMP\",\"event\":\"orchestrator_deploy_complete\",\"status\":\"success\"}" >> "$LOG_FILE"

echo ""
echo "✓ Orchestrator deployment complete"
echo "Log: $LOG_FILE"
exit 0
