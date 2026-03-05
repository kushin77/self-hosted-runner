#!/usr/bin/env bash
set -euo pipefail

# Installs the trigger-plan watcher as a systemd service.
# Requires sudo privileges.

SERVICE_SRC="$(pwd)/scripts/automation/trigger-plan-when-secrets.service"
SCRIPT_SRC="$(pwd)/scripts/automation/trigger-plan-when-secrets.sh"

if [ "$EUID" -ne 0 ]; then
  echo "This installer must be run as root: sudo $0" >&2
  exit 1
fi

echo "Installing trigger-plan script to /usr/local/bin"
install -m 0755 "$SCRIPT_SRC" /usr/local/bin/trigger-plan-when-secrets.sh

echo "Installing systemd unit to /etc/systemd/system"
install -m 0644 "$SERVICE_SRC" /etc/systemd/system/trigger-plan-when-secrets.service

echo "Reloading systemd and enabling service"
systemctl daemon-reload
systemctl enable --now trigger-plan-when-secrets.service

echo "Service installed and started. Check status with: systemctl status trigger-plan-when-secrets.service"
