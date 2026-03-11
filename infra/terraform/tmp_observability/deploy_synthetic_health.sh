#!/usr/bin/env bash
set -euo pipefail

# Deploy helper: creates Pub/Sub topic, deploys Cloud Function, and creates Cloud Scheduler job
# Usage: ./deploy_synthetic_health.sh PROJECT_ID TARGET_URL

PROJECT_ID=${1:-${PROJECT:-nexusshield-prod}}
TARGET_URL=${2:-}
SVC_NAME="synthetic-health-check"
TOPIC="synthetic-health-topic"
JOB_NAME="synthetic-health-schedule"
SCHEDULE="*/5 * * * *" # every 5 minutes; adjust as needed
SOURCE_DIR="$(pwd)/infra/functions/synthetic_health_check"
RUNTIME="python311"

if [[ -z "$PROJECT_ID" || -z "$TARGET_URL" ]]; then
  echo "Usage: $0 [PROJECT_ID] TARGET_URL"
  echo "Environment fallback: PROJECT or default 'nexusshield-prod' will be used if PROJECT_ID omitted."
  exit 2
fi

ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
if [[ "${ALLOW_USER_ACCOUNT_AUTH:-0}" != "1" && "$ACTIVE_ACCOUNT" != *"gserviceaccount.com" ]]; then
  echo "ERROR: Active gcloud account is not a service account: $ACTIVE_ACCOUNT" >&2
  echo "Set ALLOW_USER_ACCOUNT_AUTH=1 to override (not recommended), or authenticate via GSM/Vault-backed service account." >&2
  exit 3
fi

if ! gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT_ID" --quiet
fi

gcloud functions deploy "$SVC_NAME" \
  --gen2 \
  --runtime "$RUNTIME" \
  --region=us-central1 \
  --entry-point=main \
  --trigger-topic="$TOPIC" \
  --source="$SOURCE_DIR" \
  --set-env-vars "TARGET_URL=${TARGET_URL},METRIC_TYPE=custom.googleapis.com/synthetic/uptime_check" \
  --project="$PROJECT_ID" \
  --quiet || {
    echo "Cloud Function deploy failed; run with --verbosity debug to inspect." >&2
    exit 1
  }

# Create Scheduler job to publish a message to the topic
gcloud scheduler jobs create pubsub "$JOB_NAME" \
  --project="$PROJECT_ID" \
  --schedule="$SCHEDULE" \
  --topic="$TOPIC" \
  --message-body='{"run":"synthetic"}' \
  --location=us-central1 \
  --quiet || true

echo "Deployed synthetic health checker to project $PROJECT_ID. Topic=$TOPIC, Function=$SVC_NAME, Job=$JOB_NAME"
