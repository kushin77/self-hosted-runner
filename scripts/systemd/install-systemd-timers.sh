#!/usr/bin/env bash
set -euo pipefail

# Auto-elevate to root if not already running as root
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "$@"
  else
    echo "This script requires root privileges and sudo is not available." >&2
    exit 2
  fi
fi

# Install systemd service/timer files system-wide
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
SRC_DIR="${REPO_ROOT}/scripts/systemd"

echo "Installing systemd unit and timer files from ${SRC_DIR} to /etc/systemd/system/"
for f in "${SRC_DIR}"/*.service "${SRC_DIR}"/*.timer; do
  [ -e "$f" ] || continue
  echo "  -> copying $(basename "$f")"
  install -m 644 "$f" /etc/systemd/system/ || true
done

systemctl daemon-reload

echo "Enabling and starting timers"
for t in nexusshield-*.timer; do
  if systemctl enable --now "$t"; then
    echo "  Enabled/started $t"
  else
    echo "  Failed to enable $t" >&2
  fi
done

echo "All done. Use 'systemctl list-timers' to verify." 

exit 0
