#!/usr/bin/env bash
set -euo pipefail

# Sync a secret from Google Secret Manager to HashiCorp Vault KV v2
# Usage:
#   SECRET_NAME=my-secret VAULT_PATH=secret/data/my-path ./sync_gsm_to_vault.sh
# Or:
#   ./sync_gsm_to_vault.sh <secret-name> <vault-path>

if [[ $# -ge 2 ]]; then
  SECRET_NAME="$1"
  VAULT_PATH="$2"
else
  SECRET_NAME=${SECRET_NAME:-}
  VAULT_PATH=${VAULT_PATH:-}
fi

: ${VAULT_ADDR:=${VAULT_ADDR:-https://127.0.0.1:8200}}
: ${VAULT_NAMESPACE:=${VAULT_NAMESPACE:-}}
VAULT_TOKEN_FILE=${VAULT_TOKEN_FILE:-/var/run/secrets/vault/token}
VAULT_KV_MOUNT=${VAULT_KV_MOUNT:-secret}

if [ -z "$SECRET_NAME" ]; then
  echo "ERROR: SECRET_NAME is required (env or arg)"
  exit 2
fi
if [ -z "$VAULT_PATH" ]; then
  echo "ERROR: VAULT_PATH is required (env or arg, eg: secret/data/my-path)"
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found in PATH"
  exit 3
fi

# Fetch secret payload (latest version) from Secret Manager
echo "Fetching secret from Secret Manager: $SECRET_NAME"
secret_payload=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" --format='get(payload.data)' 2>/dev/null | base64 --decode || true)
if [ -z "$secret_payload" ]; then
  echo "ERROR: failed to read secret or secret is empty"
  exit 5
fi

# Determine kv path for `vault kv put` (strip kv v2 'data/' if present)
if [[ "$VAULT_PATH" == */data/* ]]; then
  kv_path=${VAULT_PATH#*/data/}
else
  kv_path=${VAULT_PATH}
fi

echo "Writing secret to Vault at ${VAULT_KV_MOUNT}/${kv_path}"

# Obtain a transient Vault token for this operation
vault_token=""
if [[ -n "${VAULT_TOKEN_FILE:-}" && -f "${VAULT_TOKEN_FILE}" ]]; then
  vault_token=$(cat "${VAULT_TOKEN_FILE}" | tr -d '\n' || true)
  echo "Using token from VAULT_TOKEN_FILE"
fi

# AppRole fallback using vault CLI (non-persistent token)
if [[ -z "$vault_token" && -n "${VAULT_ROLE_ID:-}" && -n "${VAULT_SECRET_ID:-}" ]]; then
  if command -v vault >/dev/null 2>&1; then
    # Respect VAULT_ADDR and VAULT_NAMESPACE for the vault CLI
    export VAULT_ADDR
    if [[ -n "${VAULT_NAMESPACE}" ]]; then
      export VAULT_NAMESPACE
    fi
    vault_token=$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID" 2>/dev/null || true)
    if [[ -n "$vault_token" ]]; then
      echo "Obtained transient token via AppRole login"
    fi
  fi
fi

# Fallback to VAULT_TOKEN env (discouraged)
if [[ -z "$vault_token" && -n "${VAULT_TOKEN:-}" ]]; then
  vault_token="${VAULT_TOKEN}"
  echo "Using VAULT_TOKEN from environment (discouraged)"
fi

if [[ -z "$vault_token" ]]; then
  echo "ERROR: no Vault authentication available (set VAULT_TOKEN_FILE, VAULT_ROLE_ID+VAULT_SECRET_ID, or VAULT_TOKEN)"
  exit 6
fi

# Perform kv write with transient token. Use raw payload.
# For binary data, store base64 and document retrieval accordingly.
if command -v vault >/dev/null 2>&1; then
  export VAULT_ADDR
  if [[ -n "${VAULT_NAMESPACE}" ]]; then
    export VAULT_NAMESPACE
  fi
  VAULT_TOKEN="$vault_token" vault kv put "${VAULT_KV_MOUNT}/${kv_path}" value@- <<'PAYLOAD'
$secret_payload
PAYLOAD
  rc=$?
else
  # If vault CLI is unavailable, try using the HTTP API
  write_url="${VAULT_ADDR}/v1/${VAULT_KV_MOUNT}/data/${kv_path}"
  payload_json=$(printf '{"data":{"value":"%s"}}' "$(echo "$secret_payload" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')")
  rc=1
  if command -v curl >/dev/null 2>&1; then
    resp=$(curl -s -o /dev/stderr -w "%{http_code}" --header "X-Vault-Token: $vault_token" --request POST --data "$payload_json" "$write_url" 2>/dev/null || true)
    if [[ "$resp" =~ ^2 ]]; then
      rc=0
    fi
  fi
fi

if [ $rc -eq 0 ]; then
  echo "OK: secret synced to Vault"
  exit 0
else
  echo "ERROR: failed to write secret to Vault (rc=$rc)"
  exit 7
fi
