#!/usr/bin/env bash
set -euo pipefail

# Retrieve secret using multi-tier fallback for runtime consumption
# Usage: ./scripts/retrieve-secret.sh <secret-name>

SECRET_NAME=${1:?Usage: $0 <secret-name>}

log(){ echo "[retrieve] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*"; }

if gcloud secrets versions access latest --secret="$SECRET_NAME" --project="${GCP_PROJECT_ID:-}" 2>/dev/null; then
  log "Using GCP Secret Manager"
  gcloud secrets versions access latest --secret="$SECRET_NAME" --project="${GCP_PROJECT_ID:-}"
  exit 0
fi

if aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region ${AWS_REGION:-us-east-1} 2>/dev/null; then
  log "Using AWS Secrets Manager"
  aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region ${AWS_REGION:-us-east-1} | jq -r '.SecretString'
  exit 0
fi

if [ -n "${!SECRET_NAME-}" ]; then
  log "Using GitHub Actions secret env fallback"
  echo "${!SECRET_NAME}"
  exit 0
fi

if [ -f ~/.vault/encrypted-$SECRET_NAME ]; then
  log "Using local encrypted backup"
  gpg --decrypt ~/.vault/encrypted-$SECRET_NAME
  exit 0
fi

log "Secret not found in any tier"
exit 2
