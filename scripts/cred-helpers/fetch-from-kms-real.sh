#!/usr/bin/env bash
set -euo pipefail

# Fetch secret from AWS Secrets Manager / KMS (wrapped)
# Usage: fetch-from-kms-real.sh <CREDENTIAL_NAME>

CREDENTIAL_NAME="${1:-}"
AWS_KMS_KEY_ID="${AWS_KMS_KEY_ID:-}"

log_info(){ echo "[INFO] $1" >&2; }
log_fail(){ echo "[FAIL] $1" >&2; }

if [ -z "$CREDENTIAL_NAME" ]; then
  log_fail "Usage: $0 CREDENTIAL_NAME"
  exit 2
fi

if [ -z "$AWS_KMS_KEY_ID" ]; then
  log_fail "AWS_KMS_KEY_ID not set, skipping KMS layer"
  exit 1
fi

log_info "Attempting KMS retrieval for $CREDENTIAL_NAME..."

# Validate AWS auth
CALLER_ID=$(aws sts get-caller-identity --output json 2>/dev/null | jq -r '.Account // empty' || echo "")
if [ -z "$CALLER_ID" ]; then
  log_fail "AWS authentication failed"
  exit 1
fi

CRED_VALUE=""
for attempt in 1 2 3; do
  SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$CREDENTIAL_NAME" --query SecretString --output text 2>/dev/null || echo "")
  if [ -n "$SECRET_JSON" ]; then
    CIPHERTEXT=$(echo "$SECRET_JSON" | jq -r '.ciphertext // empty' 2>/dev/null || echo "")
    if [ -n "$CIPHERTEXT" ]; then
      PLAINTEXT=$(aws kms decrypt --ciphertext-blob fileb://<(echo $CIPHERTEXT | base64 -d) --key-id "$AWS_KMS_KEY_ID" --query Plaintext --output text 2>/dev/null | base64 -d)
      CRED_VALUE="$PLAINTEXT"
    else
      CRED_VALUE="$SECRET_JSON"
    fi
    if [ -n "$CRED_VALUE" ]; then
      log_pass "KMS retrieval successful (attempt $attempt)"
      echo "$CRED_VALUE"
      exit 0
    fi
  fi
  if [ $attempt -lt 3 ]; then sleep $((attempt * 2)); fi
done

log_fail "KMS retrieval failed after 3 attempts"
exit 1
