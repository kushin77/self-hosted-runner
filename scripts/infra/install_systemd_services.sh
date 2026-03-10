#!/usr/bin/env bash
set -euo pipefail

# Installer for systemd units and timers (idempotent)
# Usage: sudo ./scripts/infra/install_systemd_services.sh

UNIT_DIR=/etc/systemd/system
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)

install_unit() {
  local src="$REPO_ROOT/$1"
  local dest="$UNIT_DIR/$(basename "$1")"
  echo "Installing $src -> $dest"
  install -m 644 "$src" "$dest"
}

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root: sudo $0" >&2
  exit 1
fi

install_unit scripts/systemd/vault_sync.service
install_unit scripts/systemd/vault_sync.timer
install_unit scripts/systemd/cleanup_ephemeral.service
install_unit scripts/systemd/cleanup_ephemeral.timer

systemctl daemon-reload
systemctl enable --now vault_sync.timer || true
systemctl enable --now cleanup_ephemeral.timer || true

echo "Systemd services and timers installed and enabled. Edit unit Environment= values or drop-in files in /etc/systemd/system to configure secrets and project settings." 
