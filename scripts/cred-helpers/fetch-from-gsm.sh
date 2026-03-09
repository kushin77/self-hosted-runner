#!/usr/bin/env bash
set -euo pipefail
# Minimal GSM fetcher helper (placeholder for real implementation)
# Usage: fetch-from-gsm.sh <credential-name>
NAME="$1"
VAR_NAME="TEST_GSM_${NAME//[^A-Za-z0-9_]/_}"
if [ -n "${!VAR_NAME-}" ]; then
  echo "${!VAR_NAME}"
  exit 0
fi
if command -v gcloud >/dev/null 2>&1; then
  # try to fetch secret from Google Secret Manager (best-effort, requires gcloud auth)
  if secret_value=$(gcloud secrets versions access latest --secret="$NAME" --format='get(payload.data)' 2>/dev/null | tr -d '\n'); then
    # gcloud returns base64; decode
    echo "$secret_value" | base64 --decode
    exit 0
  fi
fi
echo "ERROR: fetch-from-gsm: secret $NAME not found (set env $VAR_NAME for testing)" >&2
exit 2
