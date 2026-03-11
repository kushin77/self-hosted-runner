#!/bin/bash

set -euo pipefail

# User-level Azure CLI installer (no sudo)
# Attempts to install azure-cli via pip into $HOME/.local
# Not guaranteed to work for all environments but useful when sudo is not available.

echo "Attempting user-local Azure CLI install (pip)"

python3 -m pip install --upgrade --user pip setuptools wheel
python3 -m pip install --user azure-cli

export PATH="$HOME/.local/bin:$PATH"

if command -v az &>/dev/null; then
  echo "az installed: $(az version --output json | jq -r .azureCliVersion)"
  echo "You may need to export PATH in your shell config: export PATH=\"$HOME/.local/bin:$PATH\""
  exit 0
else
  echo "User-local install failed or 'az' not in PATH. Try Option A (sudo installation) or fix apt sources." >&2
  exit 1
fi
