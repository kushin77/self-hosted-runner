#!/bin/bash
set -e

# Example helper: fetch secrets from Vault using vault CLI and export as env vars
# Requires: vault CLI installed and authenticated (e.g., via OIDC or token)
# Usage: ./scripts/fetch_vault_secrets.sh

if ! command -v vault >/dev/null; then
  echo "vault CLI not found; skipping Vault fetch"
  exit 0
fi

# Require VAULT_ADDR
VAULT_ADDR=${VAULT_ADDR:-}
if [[ -z "$VAULT_ADDR" ]]; then
  echo "VAULT_ADDR not set; skipping Vault fetch"
  exit 0
fi

# If no VAULT_TOKEN, try AppRole login via env or /run/secrets
if [[ -z "${VAULT_TOKEN:-}" ]]; then
  ROLE_ID="${VAULT_ROLE_ID:-}"
  SECRET_ID="${VAULT_SECRET_ID:-}"
  if [[ -z "$ROLE_ID" && -f "/run/secrets/vault_role_id" ]]; then
    ROLE_ID=$(cat /run/secrets/vault_role_id)
  fi
  if [[ -z "$SECRET_ID" && -f "/run/secrets/vault_secret_id" ]]; then
    SECRET_ID=$(cat /run/secrets/vault_secret_id)
  fi

  if [[ -n "$ROLE_ID" && -n "$SECRET_ID" ]]; then
    echo "Attempting Vault AppRole login..."
    resp=$(curl -sS --request POST --data "{\"role_id\": \"${ROLE_ID}\", \"secret_id\": \"${SECRET_ID}\"}" "${VAULT_ADDR%/}/v1/auth/approle/login" || true)
    VAULT_TOKEN=$(echo "$resp" | sed -n 's/.*"client_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)
    if [[ -n "${VAULT_TOKEN:-}" ]]; then
      export VAULT_TOKEN
      echo "AppRole login successful; VAULT_TOKEN exported for this session."
    else
      echo "AppRole login did not return a token; continuing without VAULT_TOKEN."
    fi
  else
    echo "No VAULT_TOKEN and no AppRole credentials found; skipping AppRole login."
  fi
fi

# Paths are examples - adjust to your Vault layout
GHCR_PATH="secret/data/ci/ghcr"
HOOK_PATH="secret/data/ci/webhooks"
PUSHG_PATH="secret/data/ci/pushgateway"

set +e
GHCR_PAT=$(vault kv get -field=token "$GHCR_PATH" 2>/dev/null)
SLACK_WEBHOOK=$(vault kv get -field=webhook "$HOOK_PATH" 2>/dev/null)
PUSHGATEWAY_URL=$(vault kv get -field=url "$PUSHG_PATH" 2>/dev/null)
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
