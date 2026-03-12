#!/usr/bin/env bash
set -euo pipefail

# provision-slack-webhook-to-gsm.sh
# Idempotently create or update a Google Secret Manager secret containing a Slack webhook URL.
# Usage (safe, non-echoing):
#  GCP_PROJECT=my-gcp-project SLACK_WEBHOOK_VALUE="https://hooks.slack.com/..." \
#    ./provision-slack-webhook-to-gsm.sh slack-webhook

SECRET_NAME=${1:-${SLACK_SECRET_NAME:-slack-webhook}}
GCP_PROJECT=${GCP_PROJECT:-${GSM_PROJECT:-}}

if [ -z "$GCP_PROJECT" ]; then
  echo "Set GCP_PROJECT or GSM_PROJECT env var to target project" >&2
  exit 2
fi

if [ -z "${SLACK_WEBHOOK_VALUE:-}" ]; then
  echo "Set SLACK_WEBHOOK_VALUE environment variable with the webhook URL (do not pass token as arg)" >&2
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI required" >&2
  exit 2
fi

# Check if secret exists
if gcloud secrets describe "$SECRET_NAME" --project="$GCP_PROJECT" >/dev/null 2>&1; then
  echo "Secret $SECRET_NAME exists in project $GCP_PROJECT — adding new version (idempotent)"
  printf '%s' "$SLACK_WEBHOOK_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$GCP_PROJECT" >/dev/null
  echo "Added new version to $SECRET_NAME"
else
  echo "Creating secret $SECRET_NAME in project $GCP_PROJECT"
  gcloud secrets create "$SECRET_NAME" --replication-policy="automatic" --project="$GCP_PROJECT" >/dev/null
  printf '%s' "$SLACK_WEBHOOK_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$GCP_PROJECT" >/dev/null
  echo "Secret $SECRET_NAME created and first version added"
fi

echo "Grant access to service accounts that need to read the secret (example):"
echo "  gcloud secrets add-iam-policy-binding $SECRET_NAME --project=$GCP_PROJECT --member='serviceAccount:terraform-sa@${GCP_PROJECT}.iam.gserviceaccount.com' --role='roles/secretmanager.secretAccessor'"
echo "Provisioning complete (webhook not printed)."
