#!/usr/bin/env bash
set -euo pipefail

# Emergency secret recovery: attempts retrieval across tiers
# Usage: ./scripts/emergency-secret-recovery.sh <secret-name>

SECRET_NAME=${1:?Usage: $0 <secret-name>}

log(){ echo "[recovery] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*"; }
fail(){ echo "[recovery] ERROR: $*" >&2; exit 1; }

retrieve_gcp(){
  log "Trying GCP Secret Manager"
  gcloud secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null || return 1
}

retrieve_aws(){
  log "Trying AWS Secrets Manager"
  aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region ${AWS_REGION:-us-east-1} 2>/dev/null | jq -r '.SecretString' || return 1
}

retrieve_github(){
  log "Trying GitHub Actions secrets (read-only list)"
  # gh secret view requires repo admin - attempt best-effort
  gh secret view "$SECRET_NAME" --repo kushin77/self-hosted-runner 2>/dev/null || return 1
}

retrieve_local(){
  log "Trying local backup"
  if [ -f ~/.vault/encrypted-$SECRET_NAME ]; then
    gpg --decrypt ~/.vault/encrypted-$SECRET_NAME 2>/dev/null || return 1
  else
    return 1
  fi
}

retrieve_gcp || retrieve_aws || retrieve_github || retrieve_local || fail "All tiers exhausted"
log "Secret retrieved successfully"
