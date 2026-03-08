#!/usr/bin/env bash
set -euo pipefail

# Usage: vault_store_webhook.sh <slack_webhook_url>
# Requires: `vault` CLI installed and authenticated (VAULT_ADDR and VAULT_TOKEN or prior `vault login`).

WEBHOOK="${1:-}" 
if [ -z "$WEBHOOK" ]; then
  echo "Usage: $0 <SLACK_WEBHOOK_URL>"
  exit 2
fi

if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not found; please install and authenticate first"
  exit 2
fi

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "VAULT_ADDR is not set. Export VAULT_ADDR before running, e.g.:"
  echo "  export VAULT_ADDR=https://vault.example.local:8200"
  exit 2
fi

echo "Writing Slack webhook to Vault at path: secret/data/ci/webhooks"
# Use KV v2 path write with JSON payload when possible
vault kv put secret/ci/webhooks webhook="$WEBHOOK"

echo "Stored Slack webhook in Vault (secret/ci/webhooks)."
echo "You can verify with: vault kv get -field=webhook secret/ci/webhooks"
