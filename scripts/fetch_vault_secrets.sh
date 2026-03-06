#!/bin/bash
set -e

# Example helper: fetch secrets from Vault using vault CLI and export as env vars
# Requires: vault CLI installed and authenticated (e.g., via OIDC or token)
# Usage: ./scripts/fetch_vault_secrets.sh

if ! command -v vault >/dev/null; then
  echo "vault CLI not found; skipping Vault fetch"
  exit 0
fi

# Paths are examples - adjust to your Vault layout
GHCR_PATH="secret/data/ci/ghcr"
HOOK_PATH="secret/data/ci/webhooks"
PUSHG_PATH="secret/data/ci/pushgateway"

set +e
GHCR_PAT=$(vault kv get -field=token $GHCR_PATH 2>/dev/null)
SLACK_WEBHOOK=$(vault kv get -field=webhook $HOOK_PATH 2>/dev/null)
PUSHGATEWAY_URL=$(vault kv get -field=url $PUSHG_PATH 2>/dev/null)
set -e

if [ -n "$GHCR_PAT" ]; then
  export GHCR_PAT
  echo "Fetched GHCR_PAT from Vault"
fi
if [ -n "$SLACK_WEBHOOK" ]; then
  export SLACK_WEBHOOK
  echo "Fetched SLACK_WEBHOOK from Vault"
fi
if [ -n "$PUSHGATEWAY_URL" ]; then
  export PUSHGATEWAY_URL
  echo "Fetched PUSHGATEWAY_URL from Vault"
fi
