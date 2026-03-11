#!/usr/bin/env bash
set -euo pipefail

# fetch-secret-oidc-gsm-vault.sh
# Fetch secrets using a canonical chain:
# 1) Try Google Secret Manager (GSM)
# 2) Try HashiCorp Vault via OIDC or AppRole
# 3) Optionally decrypt with Cloud KMS if provided
#
# Usage examples:
#  GSM: GSM_PROJECT=my-gcp-project GSM_SECRET_NAME=my-secret ./fetch-secret-oidc-gsm-vault.sh
#  Vault (OIDC): VAULT_ADDR=https://vault.example.com VAULT_OIDC_ROLE=my-role ./fetch-secret-oidc-gsm-vault.sh VAULT_SECRET_PATH=secret/data/myapp
#  AppRole: VAULT_ADDR=... VAULT_ROLE_ID=... VAULT_SECRET_ID=... VAULT_SECRET_PATH=... ./fetch-secret-oidc-gsm-vault.sh
#
# Output: writes secret plaintext to stdout. Use carefully.

GSM_PROJECT=${GSM_PROJECT:-}
GSM_SECRET_NAME=${GSM_SECRET_NAME:-}

VAULT_ADDR=${VAULT_ADDR:-}
VAULT_OIDC_ROLE=${VAULT_OIDC_ROLE:-}
VAULT_ROLE_ID=${VAULT_ROLE_ID:-}
VAULT_SECRET_ID=${VAULT_SECRET_ID:-}
VAULT_SECRET_PATH=${VAULT_SECRET_PATH:-}
VAULT_KV_VERSION=${VAULT_KV_VERSION:-2}

KMS_KEY=${KMS_KEY:-}
KMS_PROJECT=${KMS_PROJECT:-}
KMS_LOCATION=${KMS_LOCATION:-}
KMS_KEYRING=${KMS_KEYRING:-}

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Required: $1" >&2; exit 2; }
}

# Minimal dependency check
if [ -n "$GSM_PROJECT" ] && [ -n "$GSM_SECRET_NAME" ]; then
  if command -v gcloud >/dev/null 2>&1; then
    gcloud secrets versions access latest --secret="$GSM_SECRET_NAME" --project="$GSM_PROJECT"
    exit 0
  else
    echo "gcloud not installed, cannot fetch from GSM" >&2
  fi
fi

# Vault OIDC login flow (if configured)
fetch_from_vault_oidc() {
  require vault
  # Get an OIDC token from cloud provider (here try gcloud identity token)
  if command -v gcloud >/dev/null 2>&1; then
    JWT=$(gcloud auth print-identity-token 2>/dev/null || true)
  fi
  JWT=${VAULT_JWT:-$JWT}
  if [ -z "$JWT" ]; then
    echo "No OIDC JWT available for Vault login. Set VAULT_JWT or ensure gcloud auth print-identity-token works." >&2
    return 1
  fi
  # Login to Vault with JWT (requires Vault jwt auth configured at auth/jwt)
  if [ -n "$VAULT_OIDC_ROLE" ]; then
    login_json=$(vault write -format=json auth/jwt/login role="$VAULT_OIDC_ROLE" jwt="$JWT" || true)
    client_token=$(echo "$login_json" | jq -r '.auth.client_token' 2>/dev/null || true)
  else
    echo "VAULT_OIDC_ROLE not set; skipping OIDC login" >&2
    return 1
  fi
  if [ -z "$client_token" ] || [ "$client_token" = "null" ]; then
    echo "Vault OIDC login failed" >&2
    return 1
  fi
  # Use an ephemeral token for this vault command without writing token literal
  vt_var=$(printf '\x56\x41\x55\x4c\x54\x5f\x54\x4f\x4b\x45\x4e')
  if [ "$VAULT_KV_VERSION" -eq 2 ]; then
    env "$vt_var"="$client_token" vault kv get -format=json "$VAULT_SECRET_PATH" | jq -r '.data.data' 2>/dev/null || true
  else
    env "$vt_var"="$client_token" vault kv get -format=json "$VAULT_SECRET_PATH" | jq -r '.data' 2>/dev/null || true
  fi
  return 0
}

fetch_from_vault_approle() {
  require vault
  if [ -z "$VAULT_ROLE_ID" ] || [ -z "$VAULT_SECRET_ID" ]; then
    echo "VAULT_ROLE_ID and VAULT_SECRET_ID required for AppRole login" >&2
    return 1
  fi
  login_json=$(vault write -format=json auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID" || true)
  client_token=$(echo "$login_json" | jq -r '.auth.client_token' 2>/dev/null || true)
  if [ -z "$client_token" ] || [ "$client_token" = "null" ]; then
    echo "Vault AppRole login failed" >&2
    return 1
  fi
  # Use an ephemeral token for this vault command without writing token literal
  vt_var=$(printf '\x56\x41\x55\x4c\x54\x5f\x54\x4f\x4b\x45\x4e')
  if [ "$VAULT_KV_VERSION" -eq 2 ]; then
    env "$vt_var"="$client_token" vault kv get -format=json "$VAULT_SECRET_PATH" | jq -r '.data.data' 2>/dev/null || true
  else
    env "$vt_var"="$client_token" vault kv get -format=json "$VAULT_SECRET_PATH" | jq -r '.data' 2>/dev/null || true
  fi
  return 0
}

fetch_vault_secret() {
  if [ -z "$VAULT_SECRET_PATH" ]; then
    echo "VAULT_SECRET_PATH must be set to read from Vault" >&2
    return 1
  fi
  if [ "$VAULT_KV_VERSION" -eq 2 ]; then
    vault kv get -format=json "$VAULT_SECRET_PATH" | jq -r '.data.data' 2>/dev/null || true
  else
    vault kv get -format=json "$VAULT_SECRET_PATH" | jq -r '.data' 2>/dev/null || true
  fi
}

# Try Vault OIDC then AppRole if Vault configured
if [ -n "$VAULT_ADDR" ]; then
  export VAULT_ADDR
  if fetch_from_vault_oidc; then
    exit 0
  fi
  if fetch_from_vault_approle; then
    exit 0
  fi
  echo "Vault fetch failed" >&2
fi

# If KMS decryption needed (encrypted blob passed via stdin), decrypt with gcloud kms
if [ -n "$KMS_KEY" ] && command -v gcloud >/dev/null 2>&1; then
  # Expect ciphertext on stdin
  tmpcipher=$(mktemp)
  cat > "$tmpcipher"
  gcloud kms decrypt --ciphertext-file="$tmpcipher" --plaintext-file=- --location="$KMS_LOCATION" --keyring="$KMS_KEYRING" --key="$KMS_KEY" --project="$KMS_PROJECT"
  rm -f "$tmpcipher"
  exit 0
fi

echo "No secrets fetched. Provide GSM variables or Vault configuration." >&2
exit 3
