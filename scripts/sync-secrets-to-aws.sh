#!/usr/bin/env bash
set -euo pipefail

# Sync secrets from GCP Secret Manager to AWS Secrets Manager
# Usage: ./scripts/sync-secrets-to-aws.sh

GCP_PROJECT_ID=${GCP_PROJECT_ID:?Missing GCP_PROJECT_ID}
AWS_REGION=${AWS_REGION:-us-east-1}

SECRETS=(
  "runner-mgmt-token"
  "deploy-ssh-key"
  "docker-hub-pat"
)

log(){ echo "[sync] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*"; }
fail(){ echo "[sync] ERROR: $*" >&2; exit 1; }

for SECRET in "${SECRETS[@]}"; do
  log "Retrieving $SECRET from GCP Secret Manager"
  SECRET_VALUE=$(gcloud secrets versions access latest --secret="$SECRET" --project="$GCP_PROJECT_ID" 2>/dev/null) || fail "failed to read $SECRET from GSM"
  if [ -z "$SECRET_VALUE" ]; then
    fail "empty value for $SECRET"
  fi

  log "Updating AWS Secrets Manager: $SECRET"
  aws secretsmanager update-secret --secret-id "$SECRET" --secret-string "$SECRET_VALUE" --region "$AWS_REGION" || \
    aws secretsmanager create-secret --name "$SECRET" --secret-string "$SECRET_VALUE" --region "$AWS_REGION" || fail "aws update/create failed for $SECRET"

  log "Updating GitHub backup secret: AWS_BACKUP_$SECRET (best-effort)"
  gh secret set "AWS_BACKUP_$SECRET" --repo kushin77/self-hosted-runner --body "$SECRET_VALUE" || log "skipping GitHub backup for $SECRET"
  log "Synchronized $SECRET"
done

log "Running health check"
bash scripts/check-secret-health.sh || fail "health check failed"
log "Sync complete"
