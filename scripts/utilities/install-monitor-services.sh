#!/usr/bin/env bash
set -euo pipefail

# Idempotent installer for systemd unit templates in this repo.
# Run with sudo to install the services and enable+start them.

UNIT_DIR=/etc/systemd/system
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

install_unit() {
  local src="$REPO_ROOT/systemd/$1"
  local dst="$UNIT_DIR/$1"
  if [ ! -f "$src" ]; then
    echo "unit file $src not found" >&2
    return 1
  fi
  if [ -f "$dst" ]; then
    echo "$1 already installed at $dst" 
  else
    echo "Installing $1 -> $dst"
    install -m 644 "$src" "$dst"
  fi
  systemctl daemon-reload
  systemctl enable --now "$1"
}

echo "This script will attempt to install and start monitor services. Run with sudo."
install_unit 7day-monitor.service
install_unit monitor-workflows.service
install_unit monitoring-alert-triage.service
install_unit monitoring-alert-triage.timer

echo "Services installed and started (enabled). Use 'systemctl status <unit>' to verify."
