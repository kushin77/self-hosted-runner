#!/usr/bin/env bash
set -euo pipefail

# Operator helper: install the agent's deploy public key onto a remote host.
# Usage: ./scripts/automation/legacy/install_deploy_key.sh user@host

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 user@host"
  exit 2
fi

TARGET="$1"
PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+vqHubKjpwPpBHIeFFmuFiNaAaw2yHvjFd4yFDZHkt deploy-key-automated-20260306'

echo "Installing deploy public key to $TARGET..."

# Ensure .ssh exists and append the key safely
ssh "$TARGET" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && grep -qxF \"$PUBKEY\" ~/.ssh/authorized_keys || echo \"$PUBKEY\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

echo "Public key installed (or already present) on $TARGET."

echo "You can now reply on Issue #787 and I'll re-dispatch the legacy-node-cleanup workflow." 
