#!/usr/bin/env bash
set -euo pipefail

# provision-github-token-to-gsm.sh
# Idempotently create or update a GSM secret containing a GitHub token.
# Usage (safe, non-echoing):
#  GCP_PROJECT=my-gcp-project GITHUB_TOKEN_VALUE="ghp_..." \
#    ./provision-github-token-to-gsm.sh github-token
#
SECRET_NAME=${1:-${GITHUB_TOKEN_SECRET_NAME:-github-token}}
GCP_PROJECT=${GCP_PROJECT:-${GSM_PROJECT:-}}

if [ -z "$GCP_PROJECT" ]; then
  echo "Set GCP_PROJECT or GSM_PROJECT env var to target project" >&2
  exit 2
fi

if [ -z "${GITHUB_TOKEN_VALUE:-}" ]; then
  echo "Set GITHUB_TOKEN_VALUE environment variable with the token (do not pass token as arg)" >&2
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI required" >&2
  exit 2
fi

# Check if secret exists
if gcloud secrets describe "$SECRET_NAME" --project="$GCP_PROJECT" >/dev/null 2>&1; then
  echo "Secret $SECRET_NAME exists in project $GCP_PROJECT — adding new version (idempotent)"
  printf '%s' "$GITHUB_TOKEN_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$GCP_PROJECT" >/dev/null
  echo "Added new version to $SECRET_NAME"
else
  echo "Creating secret $SECRET_NAME in project $GCP_PROJECT"
  gcloud secrets create "$SECRET_NAME" --replication-policy="automatic" --project="$GCP_PROJECT" >/dev/null
  printf '%s' "$GITHUB_TOKEN_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$GCP_PROJECT" >/dev/null
  echo "Secret $SECRET_NAME created and first version added"
fi

echo "Grant access to a service account that runs the orchestrator (example):"
echo "  gcloud secrets add-iam-policy-binding $SECRET_NAME --project=$GCP_PROJECT --member='serviceAccount:ORCHESTRATOR_SA@${GCP_PROJECT}.iam.gserviceaccount.com' --role='roles/secretmanager.secretAccessor'"

echo "Provisioning complete (token not printed)."
