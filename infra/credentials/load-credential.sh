#!/bin/bash
# Load credential from multi-layer sources (GSM → Vault → KMS-Env → Local)
# Usage: source load-credential.sh "credential-name"
# Returns: Credential value to stdout

set -euo pipefail

CREDENTIAL_NAME="${1:?ERROR: Missing credential name}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
VAULT_ADDR="${VAULT_ADDR:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Layer 1: Google Secret Manager (Primary)
load_from_gsm() {
  if command -v gcloud >/dev/null 2>&1 && [ -n "$GCP_PROJECT_ID" ]; then
    if CRED=$(gcloud secrets versions access latest \
      --secret="$CREDENTIAL_NAME" \
      --project="$GCP_PROJECT_ID" \
      --quiet 2>/dev/null); then
      [ -n "$CRED" ] && echo "$CRED" && return 0
    fi
  fi
  return 1
}

# Layer 2: HashiCorp Vault (Secondary)
load_from_vault() {
  if [ -n "$VAULT_ADDR" ] && command -v vault >/dev/null 2>&1; then
    if CRED=$(vault kv get -field=value "secret/$CREDENTIAL_NAME" 2>/dev/null); then
      [ -n "$CRED" ] && echo "$CRED" && return 0
    fi
  fi
  return 1
}

# Layer 3: AWS KMS-Encrypted Environment Variables (Tertiary)
load_from_kms_env() {
  KMS_ENV_VAR_NAME="${CREDENTIAL_NAME^^}_ENCRYPTED"
  ENCRYPTED_VALUE="${!KMS_ENV_VAR_NAME:-}"
  
  if [ -n "$ENCRYPTED_VALUE" ] && command -v aws >/dev/null 2>&1; then
    if CRED=$(echo "$ENCRYPTED_VALUE" | base64 -d 2>/dev/null | \
      aws kms decrypt \
        --ciphertext-blob fileb:///dev/stdin \
        --region "$AWS_REGION" \
        --query 'Plaintext' \
        --output text 2>/dev/null | base64 -d); then
      [ -n "$CRED" ] && echo "$CRED" && return 0
    fi
  fi
  return 1
}

# Layer 4: Local Emergency Keys (Emergency Only)
load_from_local_key() {
  LOCAL_KEY_PATH=".credentials/${CREDENTIAL_NAME}.key"
  if [ -f "$LOCAL_KEY_PATH" ]; then
    if CRED=$(cat "$LOCAL_KEY_PATH" 2>/dev/null); then
      [ -n "$CRED" ] && echo "$CRED" && return 0
    fi
  fi
  return 1
}

# Try each layer in order
if load_from_gsm; then
  exit 0
elif load_from_vault; then
  exit 0
elif load_from_kms_env; then
  exit 0
elif load_from_local_key; then
  exit 0
else
  echo "ERROR: No credential found for '$CREDENTIAL_NAME'" >&2
  echo "  Tried: GSM → Vault → KMS-Env → Local Key" >&2
  exit 1
fi
