#!/usr/bin/env bash
set -euo pipefail

# Helper script for host-admins to install the system-level orchestrator
# Usage (as host-admin):
#   sudo bash scripts/orchestration/run-system-install.sh

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="/var/log/orchestration"
TMP_LOG="/tmp/deploy-orchestrator-${TIMESTAMP}.log"

echo "Running system-level orchestrator installer at ${TIMESTAMP}"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires sudo/root. Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

mkdir -p "$LOG_DIR" || true

# Run the upstream installer and capture output
if bash "$ROOT_DIR/scripts/orchestration/deploy-orchestrator.sh" 2>&1 | tee "$TMP_LOG"; then
  echo "Installer completed successfully"
else
  echo "Installer failed — check $TMP_LOG for details" >&2
  exit 2
fi

echo "Reloading systemd and enabling timers"
systemctl daemon-reload
systemctl enable --now unified-orchestrator-*.timer || true

echo "Listing timers"
systemctl list-timers 'unified-orchestrator*' --no-pager || true

echo "Collecting journal for deploy service (last 200 lines)"
journalctl -u unified-orchestrator-deploy.service -n 200 --no-pager || true

# Archive logs to /var/log/orchestration if possible
if [[ -w "$LOG_DIR" ]]; then
  cp "$TMP_LOG" "$LOG_DIR/" || true
  echo "Copied log to $LOG_DIR/$(basename "$TMP_LOG")"
else
  echo "Cannot write to $LOG_DIR; leaving log at $TMP_LOG"
fi

echo "Run complete. Tail the log with: tail -n 200 $TMP_LOG"
exit 0
