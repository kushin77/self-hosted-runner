#!/bin/bash
# scripts/deploy/direct_deploy.sh
# Direct deployment script (no GitHub Actions, idempotent, immutable audit log)
# Deploys Cloud Run service and related infra using gcloud

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AUDIT_FILE="${REPO_ROOT}/logs/deploy-audit.jsonl"

mkdir -p "$(dirname "${AUDIT_FILE}")"

audit_entry() {
  local event="$1"
  local details="${2:-}" 
  echo "{\"timestamp\": \"${TIMESTAMP}\", \"event\": \"${event}\", \"details\": \"${details}\", \"immutable\": true}" >> "${AUDIT_FILE}"
}

log() { echo "[DEPLOY] $*"; }

# Configuration (override with env vars)
PROJECT=${GCP_PROJECT_ID:-$(gcloud config get-value project)}
SERVICE_NAME=${SERVICE_NAME:-nexusshield-portal-backend-production}
IMAGE=${IMAGE:-gcr.io/${PROJECT}/nexusshield-portal:latest}
REGION=${REGION:-us-central1}

# Verify gcloud auth is available
if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "[DEPLOY][ERROR] gcloud authentication not available or service account invalid. Run: gcloud auth login or gcloud auth activate-service-account --key-file=..." >&2
  audit_entry "deploy_failed_auth" "gcloud_auth_missing"
  exit 1
fi

# Idempotent Cloud Run deploy
log "Deploying Cloud Run service: ${SERVICE_NAME} (image: ${IMAGE})"

gcloud run deploy "${SERVICE_NAME}" \
  --image="${IMAGE}" \
  --project="${PROJECT}" \
  --region="${REGION}" \
  --platform=managed \
  --no-allow-unauthenticated \
  --memory=512Mi \
  --concurrency=80 \
  --max-instances=5 \
  --quiet || true

audit_entry "cloud_run_deploy" "service:${SERVICE_NAME}, image:${IMAGE}, region:${REGION}"
log "Cloud Run deploy completed; recording audit entry"

# Update Scheduler job for health checks (idempotent)
JOB_NAME=${HEALTH_SCHEDULER_NAME:-nexusshield-health-check}
SCHED_URI=${HEALTH_CHECK_URI:-"https://${SERVICE_NAME}-${REGION}.a.run.app/health"}
SCHED_SA=${SCHEDULER_SA:-nxs-portal-production-v2@${PROJECT}.iam.gserviceaccount.com}
BODY='{}'

if gcloud scheduler jobs describe "${JOB_NAME}" --project="${PROJECT}" --location="${REGION}" >/dev/null 2>&1; then
  log "Updating scheduler job ${JOB_NAME}"
  gcloud scheduler jobs update http "${JOB_NAME}" \
    --project="${PROJECT}" --location="${REGION}" \
    --schedule="*/5 * * * *" --uri="${SCHED_URI}" --http-method=GET \
    --oidc-service-account-email="${SCHED_SA}" --oidc-token-audience="${SCHED_URI}" --message-body="${BODY}" --quiet || true
  audit_entry "scheduler_update" "job:${JOB_NAME}, uri:${SCHED_URI}"
else
  log "Creating scheduler job ${JOB_NAME}"
  gcloud scheduler jobs create http "${JOB_NAME}" \
    --project="${PROJECT}" --location="${REGION}" \
    --schedule="*/5 * * * *" --uri="${SCHED_URI}" --http-method=GET \
    --oidc-service-account-email="${SCHED_SA}" --oidc-token-audience="${SCHED_URI}" --message-body="${BODY}" --quiet || true
  audit_entry "scheduler_create" "job:${JOB_NAME}, uri:${SCHED_URI}"
fi

log "Direct deployment finished"
exit 0
