#!/bin/bash
# vault-handoff.sh - Automate Vault AppRole creation and environment file
# Usage: ./vault-handoff.sh [--vault-addr https://...]
# Requires: vault CLI (for automation), VAULT_TOKEN or other auth

set -euo pipefail

# default address
VAULT_ADDR_ARG="${VAULT_ADDR_ARG:-${VAULT_ADDR:-http://127.0.0.1:8200}}"

# parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-addr)
      shift
      VAULT_ADDR_ARG="$1"
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

export VAULT_ADDR="$VAULT_ADDR_ARG"

echo "[INFO] Using Vault address: $VAULT_ADDR"

if ! command -v vault >/dev/null 2>&1; then
  echo "[ERROR] vault CLI not installed"
  exit 1
fi

# enable approle auth backend if not already
echo "[INFO] Enabling AppRole auth backend (if necessary)"
if ! vault auth list | grep -q approle; then
  vault auth enable approle
fi

# create or update role
echo "[INFO] Creating/updating AppRole 'provisioner-worker'"
vault write auth/approle/role/provisioner-worker \
    policies=provisioner-worker \
    token_ttl=1h || true

# fetch role_id
ROLE_ID=$(vault read -field=role_id auth/approle/role/provisioner-worker/role-id)
# generate new secret_id
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/provisioner-worker/secret-id)

# write environment file
ENV_FILE="/tmp/vault-env.sh"
cat <<EOF > "$ENV_FILE"
export VAULT_ADDR="$VAULT_ADDR"
export VAULT_ROLE_ID="$ROLE_ID"
export VAULT_SECRET_ID="$SECRET_ID"
EOF
chmod 600 "$ENV_FILE"

echo "[✓] Vault environment file created: $ENV_FILE"
echo "You may now source it in deployment scripts or hand off to operations."
