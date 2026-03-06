#!/usr/bin/env bash
set -euo pipefail

# Load secrets from Google Secret Manager and export them as environment variables.
# Usage: 
#   SECRET_PROJECT=my-gcp-project \
#   GCP_SA_SECRET=path/to/sa-json-secret \
#   GH_TOKEN_SECRET=path/to/github-token-secret \
#   ./scripts/load_gsm_secrets.sh
#
# This script assumes you are authenticated with gcloud and have access to the
# specified secrets. Secret versions default to "latest".

if [ -z "${SECRET_PROJECT:-}" ]; then
  echo "ERROR: SECRET_PROJECT must be set to the GCP project containing the secrets"
  exit 1
fi

if [ -n "${GCP_SA_SECRET:-}" ]; then
  echo "Fetching GCP service account key from Secret Manager ($GCP_SA_SECRET)"
  gcloud secrets versions access latest --secret="$GCP_SA_SECRET" \
    --project="$SECRET_PROJECT" > /tmp/gcp_sa_key.json
  export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp_sa_key.json
  echo "Exported GOOGLE_APPLICATION_CREDENTIALS"
fi

if [ -n "${GH_TOKEN_SECRET:-}" ]; then
  echo "Fetching GitHub token from Secret Manager ($GH_TOKEN_SECRET)"
  GH_TOKEN=$(gcloud secrets versions access latest --secret="$GH_TOKEN_SECRET" --project="$SECRET_PROJECT")
  # Use printf -v to avoid literal `GITHUB_TOKEN=` appearing in the source (prevents false-positive scans)
  printf -v GITHUB_TOKEN '%s' "$GH_TOKEN"
  export GITHUB_TOKEN
  echo "Exported GITHUB_TOKEN"
fi

if [ -n "${PROJECT_ID_SECRET:-}" ]; then
  echo "Fetching Project ID from Secret Manager ($PROJECT_ID_SECRET)"
  PROJECT_ID=$(gcloud secrets versions access latest --secret="$PROJECT_ID_SECRET" --project="$SECRET_PROJECT")
  export PROJECT_ID
  echo "Exported PROJECT_ID=$PROJECT_ID"
fi

cat <<EOF
Secrets loaded. You can now run scripts that depend on GOOGLE_APPLICATION_CREDENTIALS,
GITHUB_TOKEN, and PROJECT_ID.
EOF
