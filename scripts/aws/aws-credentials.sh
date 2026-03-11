#!/usr/bin/env bash
set -euo pipefail

# Runtime AWS credential fetcher: GSM -> Vault -> environment
# Exports AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY

PROJECT="nexusshield-prod"

fetch_from_gsm(){
  local k="$1"
  gcloud secrets versions access latest --secret="$k" --project="$PROJECT" 2>/dev/null || true
}

fetch_from_vault(){
  local path="$1"
  vault kv get -field=access_key_id "$path" 2>/dev/null || true
}

AWS_ACCESS_KEY_ID=REDACTED"
AWS_SECRET_ACCESS_KEY=""

AWS_ACCESS_KEY_ID=REDACTED
AWS_SECRET_ACCESS_KEY=$(fetch_from_gsm aws-secret-access-key || true)

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  # try Vault
  if command -v vault >/dev/null 2>&1; then
    AWS_ACCESS_KEY_ID=REDACTED
    AWS_SECRET_ACCESS_KEY=$(vault kv get -field=secret_access_key secret/aws/epic6 2>/dev/null || true)
  fi
fi

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  echo "AWS credentials exported to environment"
else
  echo "No AWS credentials found in GSM or Vault" >&2
  exit 1
fi
