#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(dirname "$0")/systemd"
if [ ! -d "$SRC_DIR" ]; then
  echo "systemd unit source not found: $SRC_DIR" >&2
  exit 1
fi

echo "Installing rotate_audit systemd units..."
sudo cp "$SRC_DIR/rotate_audit.service" /etc/systemd/system/rotate_audit.service
sudo cp "$SRC_DIR/rotate_audit.timer" /etc/systemd/system/rotate_audit.timer
sudo systemctl daemon-reload
sudo systemctl enable --now rotate_audit.timer
echo "rotate_audit.timer enabled and started."

echo "To verify: sudo systemctl list-timers --all | grep rotate_audit"
