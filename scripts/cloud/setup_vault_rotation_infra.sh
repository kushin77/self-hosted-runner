#!/usr/bin/env bash
set -euo pipefail

# Prepares infrastructure to run Vault AppRole rotation automatically.
# This script is idempotent and performs dry-run by default. Set APPLY=1 to execute.

PROJECT=${PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "")}
GSM_PROJECT=${GSM_PROJECT:-$PROJECT}
APPLY=${APPLY:-}
BUILD_SA=${BUILD_SA:-}
TOPIC=${TOPIC:-vault-rotation-trigger}
SCHED_NAME=${SCHED_NAME:-vault-rotation-schedule}
SCHED_CRON=${SCHED_CRON:-"0 3 * * *"} # default 03:00 UTC daily

if [[ -z "$PROJECT" ]]; then
  echo "ERROR: gcloud project not configured. Set PROJECT env or run 'gcloud config set project <id>'." >&2
  exit 1
fi

echo "Project: $PROJECT"
echo "GSM project: $GSM_PROJECT"

echo "Calculating Cloud Build service account..."
if [[ -z "$BUILD_SA" ]]; then
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
  BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
fi

echo "Cloud Build SA: $BUILD_SA"

echo
if [[ -z "$APPLY" ]]; then
  echo "DRY-RUN mode (no resources will be created). To apply, set APPLY=1 in the environment and re-run."
fi

echo "--- Plan: create Pub/Sub topic, grant Secret Manager access to Build SA, and create Cloud Scheduler job to publish to topic which triggers existing Cloud Function / Cloud Build pipeline."

echo
echo "1) Create Pub/Sub topic: $TOPIC"
if [[ -n "$APPLY" ]]; then
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT" || true
else
  echo "gcloud pubsub topics create $TOPIC --project=$PROJECT"
fi

echo
echo "2) Grant Build SA access to GSM secrets: VAULT_ADDR, VAULT_TOKEN, and any vault-example-role-secret_id target"
if [[ -n "$APPLY" ]]; then
  gcloud secrets add-iam-policy-binding VAULT_ADDR --project="$GSM_PROJECT" --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor || true
  gcloud secrets add-iam-policy-binding VAULT_TOKEN --project="$GSM_PROJECT" --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor || true
  # Note: the role below should be tightened to the specific secret used to store rotated secret_id
  gcloud secrets add-iam-policy-binding vault-example-role-secret_id --project="$GSM_PROJECT" --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAdmin || true
else
  echo "gcloud secrets add-iam-policy-binding VAULT_ADDR --project=$GSM_PROJECT --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor"
  echo "gcloud secrets add-iam-policy-binding VAULT_TOKEN --project=$GSM_PROJECT --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor"
  echo "gcloud secrets add-iam-policy-binding vault-example-role-secret_id --project=$GSM_PROJECT --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAdmin"
fi

echo
echo "3) Create Cloud Scheduler job to publish a message to Pub/Sub topic '$TOPIC' on cron '$SCHED_CRON'"
if [[ -n "$APPLY" ]]; then
  gcloud scheduler jobs create pubsub "$SCHED_NAME" \
    --schedule="$SCHED_CRON" \
    --topic="$TOPIC" \
    --message-body='{"rotation":"vault","source":"automation"}' \
    --project="$PROJECT" || true
else
  echo "gcloud scheduler jobs create pubsub $SCHED_NAME --schedule='$SCHED_CRON' --topic=$TOPIC --message-body='{"rotation":"vault","source":"automation"}' --project=$PROJECT"
fi

echo
echo "4) Ensure Cloud Function or subscriber exists that listens on '$TOPIC' and triggers 'cloudbuild/run-vault-rotation.yaml'"
echo "   Existing function code expected at functions/main.py or cloudbuild trigger in repo."

echo
echo "Plan complete. To apply, export APPLY=1 and re-run this script."