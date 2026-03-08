#!/usr/bin/env bash
set -euo pipefail

# Runner bootstrap script (example). Uses Vault Agent to fetch secrets and registers runner.
# Requirements: Vault Agent or Vault CLI, curl, jq

VAULT_ADDR="${VAULT_ADDR:-https://vault.example.local}"
SECRET_PATH="${SECRET_PATH:-secret/data/runners/example}"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-https://control-plane.example.local/v1/register}"

echo "Starting bootstrap"

# Fetch token from environment or instance metadata (workload identity recommended)
if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "No VAULT_TOKEN found; ensure workload identity or Vault Agent is configured"
fi

echo "Fetching runner credentials from Vault: $SECRET_PATH"
creds=$(curl -sS --header "X-Vault-Token: ${VAULT_TOKEN:-}" "$VAULT_ADDR/v1/$SECRET_PATH" || true)
if [ -z "$creds" ]; then
  echo "warning: no credentials fetched from Vault"
fi

instance_id=$(hostname)-$(cat /proc/sys/kernel/random/uuid)

echo "Registering runner with control plane: $instance_id"
curl -sS -X POST "$CONTROL_PLANE_URL" -H "Content-Type: application/json" -d "{\"instance_id\":\"$instance_id\",\"metadata\":{}}" || true

echo "Bootstrap complete"
