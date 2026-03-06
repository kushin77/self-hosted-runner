#!/bin/bash
set -e

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)/systemd"
UNIT="actions-runner-health.service"
TIMER="actions-runner-health.timer"

if [ "$EUID" -ne 0 ]; then
  echo "This installer requires sudo; will prompt for credentials."
fi

sudo cp "$SRC_DIR/$UNIT" /etc/systemd/system/$UNIT
sudo cp "$SRC_DIR/$TIMER" /etc/systemd/system/$TIMER
sudo systemctl daemon-reload
sudo systemctl enable --now $TIMER
sudo systemctl start $TIMER || true

echo "Installed and enabled $TIMER"
