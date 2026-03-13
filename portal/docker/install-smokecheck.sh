#!/usr/bin/env bash
set -euo pipefail

# Install smoke-check systemd service and timer on the worker.
# Usage: sudo ./install-smokecheck.sh

UNIT_DIR=/etc/systemd/system
SVC=smoke-check.service
TIMER=smoke-check.timer

if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

cp ./smoke-check.service "$UNIT_DIR/$SVC"
cp ./smoke-check.timer "$UNIT_DIR/$TIMER"
chmod 644 "$UNIT_DIR/$SVC" "$UNIT_DIR/$TIMER"
systemctl daemon-reload
systemctl enable --now smoke-check.timer
echo "Smoke-check timer installed and started. Check with: systemctl status smoke-check.timer" 
