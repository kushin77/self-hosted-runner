#!/usr/bin/env bash
# Creates Cloud Build triggers. Requires Cloud Build GitHub connection to exist.
set -euo pipefail
PROJECT=${PROJECT:-nexusshield-prod}
REPO="kushin77/self-hosted-runner"
# Create policy-check trigger
gcloud beta builds triggers create github \
  --name="policy-check-trigger" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild/policy-check.yaml" \
  --project="$PROJECT"
# Create direct-deploy trigger
gcloud beta builds triggers create github \
  --name="direct-deploy-trigger" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild/direct-deploy.yaml" \
  --project="$PROJECT"
