#!/usr/bin/env bash
set -euo pipefail

# Minimal GSM -> Vault sync helper.
# Requires: gcloud, vault CLI configured (VAULT_ADDR, VAULT_TOKEN)
# Usage: SECRET_NAME=my-secret VAULT_PATH=secret/my-secret ./sync_gsm_to_vault.sh

SECRET_NAME=${SECRET_NAME:-}
VAULT_PATH=${VAULT_PATH:-}

if [ -z "$SECRET_NAME" ]; then
  echo "ERROR: SECRET_NAME environment variable is required (Secret Manager secret name)."
  exit 2
fi
if [ -z "$VAULT_PATH" ]; then
  echo "ERROR: VAULT_PATH environment variable is required (eg: secret/data/my-path)."
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found in PATH"
  exit 3
fi
if ! command -v vault >/dev/null 2>&1; then
  echo "ERROR: vault CLI not found in PATH"
  exit 4
fi

# Fetch secret payload (latest version) from Secret Manager
echo "Fetching secret from Secret Manager: $SECRET_NAME"
secret_payload=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" --format='get(payload.data)' 2>/dev/null | base64 --decode || true)
if [ -z "$secret_payload" ]; then
  echo "ERROR: failed to read secret or secret is empty"
  exit 5
fi

# Write to Vault KV (v2) at provided path. Prefer ephemeral auth:
# - If VAULT_TOKEN_MOUNT_PATH is present, read token from that file (vault-agent sink).
# - Else if VAULT_TOKEN_FILE is present (legacy), read token from that file.
# - Else if VAULT_ROLE_ID and VAULT_SECRET_ID are provided, perform AppRole login for this run.
# - Falling back to VAULT_TOKEN env is discouraged but supported for operators.
# If VAULT_PATH is a kv v2 path like 'secret/data/my-path', use `vault kv put secret/my-path value=...`
# Allow operator-supplied VAULT_KV_MOUNT to override (default 'secret')
VAULT_KV_MOUNT=${VAULT_KV_MOUNT:-secret}

# Determine kv target path
# If VAULT_PATH contains 'data/' (kv v2), strip 'data/' for vault cli `kv put` usage
sanitize_path=${VAULT_PATH#*/}
if [[ "$VAULT_PATH" == */data/* ]]; then
  kv_path=${VAULT_PATH#*/data/}
else
  kv_path=${VAULT_PATH}
fi

echo "Writing secret to Vault at ${VAULT_KV_MOUNT}/${kv_path}"

# Obtain a transient Vault token for this operation
vault_tok=""
if [[ -n "${VAULT_TOKEN_MOUNT_PATH:-}" && -f "${VAULT_TOKEN_MOUNT_PATH}" ]]; then
  vault_tok=$(cat "$VAULT_TOKEN_MOUNT_PATH" | tr -d '\n' || true)
elif [[ -n "${VAULT_TOKEN_FILE:-}" && -f "${VAULT_TOKEN_FILE}" ]]; then
  vault_tok=$(cat "$VAULT_TOKEN_FILE" | tr -d '\n' || true)
elif [[ -n "${VAULT_ROLE_ID:-}" && -n "${VAULT_SECRET_ID:-}" ]]; then
  # Use AppRole login to get a one-time token (non-persistent)
  vault_tok=$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID" 2>/dev/null || true)
fi

# Fallback to VAULT_TOKEN env (discouraged)
if [[ -z "$vault_tok" && -n "${VAULT_TOKEN:-}" ]]; then
  vault_tok="${VAULT_TOKEN}"
fi

if [[ -z "$vault_tok" ]]; then
  echo "ERROR: no Vault authentication available (set VAULT_TOKEN_MOUNT_PATH, VAULT_TOKEN_FILE, VAULT_ROLE_ID+VAULT_SECRET_ID, or VAULT_TOKEN)"
  exit 6
fi

# Perform kv write with transient token
VAULT_TOKEN="$vault_tok" vault kv put "${VAULT_KV_MOUNT}/${kv_path}" value="$(echo "$secret_payload" | base64 -w0)" >/dev/null 2>&1
rc=$?

if [ $rc -eq 0 ]; then
  echo "OK: secret synced to Vault"
  exit 0
else
  echo "ERROR: failed to write secret to Vault (rc=$rc)"
  exit 7
fi
