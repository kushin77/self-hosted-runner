#!/usr/bin/env bash
set -euo pipefail

# Installs the milestone-organizer systemd service and timer locally.
# Must be run as root.

SERVICE_SRC="$(pwd)/systemd/milestone-organizer.service"
TIMER_SRC="$(pwd)/systemd/milestone-organizer.timer"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

cp "$SERVICE_SRC" /etc/systemd/system/milestone-organizer.service
cp "$TIMER_SRC" /etc/systemd/system/milestone-organizer.timer
# Install metrics service
cp "$(pwd)/systemd/milestone-metrics.service" /etc/systemd/system/milestone-metrics.service || true
systemctl daemon-reload
systemctl enable --now milestone-metrics.service || true
systemctl start milestone-metrics.service || true
systemctl daemon-reload
systemctl enable --now milestone-organizer.timer
systemctl start milestone-organizer.service || true

echo "Installed and started milestone-organizer.service and timer. Check 'journalctl -u milestone-organizer.service' for logs." 
