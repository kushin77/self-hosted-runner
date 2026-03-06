#!/usr/bin/env bash
set -euo pipefail

# Installs systemd service and timer for the maintenance script (requires sudo)
SERVICE_SRC="$(pwd)/scripts/maintenance/vscode-cleanup.service"
TIMER_SRC="$(pwd)/scripts/maintenance/vscode-cleanup.timer"
SERVICE_DST=/etc/systemd/system/vscode-cleanup.service
TIMER_DST=/etc/systemd/system/vscode-cleanup.timer

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer requires sudo. Re-run as root or with sudo." >&2
  exit 2
fi

cp "$SERVICE_SRC" "$SERVICE_DST"
cp "$TIMER_SRC" "$TIMER_DST"

systemctl daemon-reload
systemctl enable --now vscode-cleanup.timer
systemctl start vscode-cleanup.service || true

echo "Installed and started vscode-cleanup.timer. Check status with: systemctl status vscode-cleanup.timer" 
