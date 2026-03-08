#!/bin/bash
# Decrypt secrets from AWS KMS using OIDC AssumeRoleWithWebIdentity
# Usage: fetch-kms-secrets.sh <kms-key-id> <encrypted-data> [--plain]

set -euo pipefail

KMS_KEY_ID="${1:-}"
ENCRYPTED_DATA="${2:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "$KMS_KEY_ID" || -z "$ENCRYPTED_DATA" ]]; then
    echo "Usage: $0 <kms-key-id> <base64-encrypted-data>"
    exit 1
fi

# Authenticate using OIDC token from GitHub (assumed via AssumeRoleWithWebIdentity)
# AWS credentials should already be in environment from STS assume role

# Decrypt secret using AWS KMS
aws kms decrypt \
    --key-id "$KMS_KEY_ID" \
    --ciphertext-blob "fileb://<(echo -n '$ENCRYPTED_DATA' | base64 -d)" \
    --region "$AWS_REGION" \
    --query 'Plaintext' \
    --output text | base64 -d

