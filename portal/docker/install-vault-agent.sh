#!/usr/bin/env bash
set -euo pipefail

# Example install script for Vault Agent systemd unit (adapt for your environment).
# Usage: sudo ./install-vault-agent.sh

VAULT_BIN=${VAULT_BIN:-/usr/local/bin/vault}
UNIT_PATH=/etc/systemd/system/vault-agent-portal.service

if [[ ! -x "$VAULT_BIN" ]]; then
  echo "Vault binary not found at $VAULT_BIN. Install Vault CLI first." >&2
  exit 1
fi

echo "Installing vault agent systemd unit to $UNIT_PATH"
sudo cp ./vault-agent.service "$UNIT_PATH"
sudo systemctl daemon-reload
sudo systemctl enable --now vault-agent-portal.service
echo "Vault Agent service enabled and started. Check with: sudo journalctl -u vault-agent-portal -f"
