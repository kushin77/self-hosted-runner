#!/usr/bin/env bash
set -euo pipefail

# Fetch short-lived AWS credentials from GSM → Vault → KMS with failover pattern.
# Returns env vars: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN

fetch_from_gsm() {
  if command -v gcloud &> /dev/null; then
    echo "Attempting to fetch credentials from Google Secret Manager..." >&2
    if secret=$(gcloud secrets versions access latest --secret="aws-chaos-credentials" 2>/dev/null); then
      echo "$secret"
      return 0
    fi
  fi
  return 1
}

fetch_from_vault() {
  if [ -z "${VAULT_ADDR:-}" ]; then
    return 1
  fi
  if command -v vault &> /dev/null; then
    echo "Attempting to fetch credentials from HashiCorp Vault..." >&2
    vault_token="${VAULT_TOKEN:-}"
    [ -n "$vault_token" ] || vault_token=$(cat ~/.vault-token 2>/dev/null) || return 1
    if secret=$(VAULT_TOKEN="$vault_token" vault kv get -field=credentials secret/aws/chaos 2>/dev/null); then
      echo "$secret"
      return 0
    fi
  fi
  return 1
}

fetch_from_kms() {
  if [ -z "${AWS_REGION:-}" ]; then
    return 1
  fi
  if command -v aws &> /dev/null; then
    echo "Attempting to fetch credentials from AWS KMS..." >&2
    if secret=$(aws kms decrypt --ciphertext-blob fileb:///etc/secrets/aws-credentials.kms --region "$AWS_REGION" --query 'Plaintext' --output text 2>/dev/null | base64 -d); then
      echo "$secret"
      return 0
    fi
  fi
  return 1
}

# Try each method in order
credentials=""
if ! credentials=$(fetch_from_gsm 2>/dev/null); then
  if ! credentials=$(fetch_from_vault 2>/dev/null); then
    if ! credentials=$(fetch_from_kms 2>/dev/null); then
      echo "ERROR: Could not fetch credentials from GSM, Vault, or KMS." >&2
      exit 1
    fi
  fi
fi

# Export credentials (format: ACCESS_KEY:SECRET_KEY:SESSION_TOKEN or ACCESS_KEY:SECRET_KEY)
IFS=':' read -r access_key secret_key session_token <<< "$credentials" || {
  IFS=':' read -r access_key secret_key <<< "$credentials"
  session_token=""
}

export AWS_ACCESS_KEY_ID="$access_key"
export AWS_SECRET_ACCESS_KEY="$secret_key"
[ -z "$session_token" ] || export AWS_SESSION_TOKEN="$session_token"

echo "Credentials loaded from GSM/Vault/KMS successfully." >&2
exit 0
