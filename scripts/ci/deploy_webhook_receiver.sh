#!/usr/bin/env bash
set -euo pipefail
PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
SERVICE=${SERVICE:-cb-webhook-receiver}
BUCKET=${BUCKET:-nexusshield-prod-webhook-sources}
IMAGE=gcr.io/${PROJECT}/${SERVICE}:latest

# Build and push image
gcloud builds submit --tag ${IMAGE} --project=${PROJECT}

# Ensure GCS bucket exists
if ! gsutil ls -b gs://${BUCKET} >/dev/null 2>&1; then
  gsutil mb -p ${PROJECT} -l ${REGION} gs://${BUCKET}
fi

# Deploy Cloud Run
gcloud run deploy ${SERVICE} \
  --image ${IMAGE} \
  --project ${PROJECT} --region ${REGION} \
  --allow-unauthenticated \
  --set-env-vars PROJECT=${PROJECT},GCS_BUCKET=${BUCKET},REPO_OWNER=${REPO_OWNER:-kushin77},REPO_NAME=${REPO_NAME:-self-hosted-runner} \
  --platform managed

URL=$(gcloud run services describe ${SERVICE} --platform managed --region ${REGION} --project ${PROJECT} --format='value(status.url)')

echo "Deployed ${SERVICE} -> ${URL}"

echo "Set secret WEBHOOK_SECRET and GITHUB_TOKEN in Cloud Run via Cloud Console or use gcloud secrets to attach them."

echo "When ready, create a GitHub webhook pointing to ${URL} (POST /) with content-type application/json and secret matching WEBHOOK_SECRET."
