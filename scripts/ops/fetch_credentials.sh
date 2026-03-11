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

# Optional: fetch SSH private key for on-prem access (stored as plain PEM in secret)
fetch_ssh_from_gsm() {
  if command -v gcloud &> /dev/null; then
    if ssh_secret=$(gcloud secrets versions access latest --secret="onprem_ssh_key" 2>/dev/null); then
      echo "$ssh_secret"
      return 0
    fi
  fi
  return 1
}

fetch_ssh_from_vault() {
  if [ -z "${VAULT_ADDR:-}" ]; then
    return 1
  fi
  if command -v vault &> /dev/null; then
    vault_token="${VAULT_TOKEN:-}"
    [ -n "$vault_token" ] || vault_token=$(cat ~/.vault-token 2>/dev/null) || return 1
    if ssh_secret=$(VAULT_TOKEN="$vault_token" vault kv get -field=ssh_key secret/ssh/onprem 2>/dev/null); then
      echo "$ssh_secret"
      return 0
    fi
  fi
  return 1
}

fetch_ssh_from_kms() {
  if [ -z "${AWS_REGION:-}" ]; then
    return 1
  fi
  if command -v aws &> /dev/null; then
    if ssh_secret=$(aws kms decrypt --ciphertext-blob fileb:///etc/secrets/onprem_ssh.kms --region "$AWS_REGION" --query 'Plaintext' --output text 2>/dev/null | base64 -d); then
      echo "$ssh_secret"
      return 0
    fi
  fi
  return 1
}

# Try to fetch SSH key; write to secure temp file and export SSH_KEY_PATH
SSH_KEY_PATH=""
ssh_priv_key=""
if ssh_priv_key=$(fetch_ssh_from_gsm 2>/dev/null) || ssh_priv_key=$(fetch_ssh_from_vault 2>/dev/null) || ssh_priv_key=$(fetch_ssh_from_kms 2>/dev/null); then
  SSH_KEY_PATH="$(mktemp -u /tmp/onprem_ssh_key_XXXXXX)"
  umask 077
  printf "%s\n" "$ssh_priv_key" > "$SSH_KEY_PATH"
  chmod 600 "$SSH_KEY_PATH"
  export SSH_KEY_PATH
  echo "SSH key written to $SSH_KEY_PATH" >&2
else
  # No SSH key available; that's fine, remote SSH will be skipped by callers
  echo "No on-prem SSH key available from GSM/Vault/KMS" >&2
fi
# NOTE: No exit here — this file is designed to be sourced by other scripts
