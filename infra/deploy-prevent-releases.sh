#!/usr/bin/env bash
set -euo pipefail

# Deploy the prevent-releases GitHub App scaffold to Cloud Run.
# Idempotent: safe to re-run.
# Requires: gcloud authenticated with project owner or deployer privileges.

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
SERVICE=${SERVICE:-prevent-releases}
IMAGE=${IMAGE:-us-central1-docker.pkg.dev/${PROJECT}/production-portal-docker/${SERVICE}:latest}
SA=${SA:-nxs-prevent-releases-sa@${PROJECT}.iam.gserviceaccount.com}

echo "Project: $PROJECT | Region: $REGION | Service: $SERVICE | Image: $IMAGE"

echo "1) Ensure service account exists"
if ! gcloud iam service-accounts describe "$SA" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA%%@*}" --project="$PROJECT" --display-name="Prevent releases Cloud Run SA"
fi

echo "2) Build and push container via Cloud Build"
gcloud builds submit --project="$PROJECT" --tag "$IMAGE" .

echo "3) Deploy to Cloud Run (private)"
gcloud run deploy "$SERVICE" --project="$PROJECT" --region="$REGION" --image="$IMAGE" --platform=managed --service-account="$SA" --no-allow-unauthenticated --quiet

echo "4) Create GSM placeholders for GitHub App private key and app id (idempotent)"
for s in github-app-private-key github-app-id github-app-webhook-secret; do
  if ! gcloud secrets describe "$s" --project="$PROJECT" >/dev/null 2>&1; then
    printf 'placeholder' | gcloud secrets create "$s" --data-file=- --project="$PROJECT"
  fi
  gcloud secrets add-iam-policy-binding "$s" --project="$PROJECT" --member="serviceAccount:$SA" --role="roles/secretmanager.secretAccessor" || true
done

echo "Deployed Cloud Run service: $SERVICE"
echo "Store the GitHub App private key in GSM secret 'github-app-private-key' and app id in 'github-app-id', then configure webhook URL to the Cloud Run URL."
