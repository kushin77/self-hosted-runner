#!/usr/bin/env bash
set -euo pipefail
# Minimal KMS/SecretsManager fetcher helper (placeholder for real implementation)
# Usage: fetch-from-kms.sh <credential-name>
NAME="$1"
VAR_NAME="TEST_KMS_${NAME//[^A-Za-z0-9_]/_}"
if [ -n "${!VAR_NAME-}" ]; then
  echo "${!VAR_NAME}"
  exit 0
fi
if command -v aws >/dev/null 2>&1; then
  if secret=$(aws secretsmanager get-secret-value --secret-id "$NAME" --query SecretString --output text 2>/dev/null || true); then
    if [ -n "$secret" ]; then
      echo "$secret"
      exit 0
    fi
  fi
fi
echo "ERROR: fetch-from-kms: secret $NAME not found (set env $VAR_NAME for testing or configure AWS CLI)" >&2
exit 2
