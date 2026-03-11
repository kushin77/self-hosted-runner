#!/usr/bin/env bash
set -euo pipefail

# Deploy script that reads a service account key from Secret Manager (GSM)
# and uses it to authenticate non-interactively, then runs the synthetic deploy.
# Usage: ./deploy_with_gsm.sh PROJECT_ID SECRET_NAME

PROJECT_ID=${1:-${PROJECT:-nexusshield-prod}}
SECRET_NAME=${2:-deploy-sa-key}
TMP_KEY_FILE=$(mktemp /tmp/sa-key-XXXX.json)

if [[ -z "$PROJECT_ID" || -z "$SECRET_NAME" ]]; then
  echo "Usage: $0 [PROJECT_ID] [SECRET_NAME]" >&2
  exit 2
fi

echo "Using project: $PROJECT_ID"

if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "ERROR: Secret '$SECRET_NAME' not found in project $PROJECT_ID."
  echo "Create it with: gcloud secrets versions add $SECRET_NAME --data-file=/path/to/sa-key.json --project=$PROJECT_ID"
  rm -f "$TMP_KEY_FILE"
  exit 3
fi

echo "Fetching secret versions from Secret Manager: $SECRET_NAME in project $PROJECT_ID"
gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT_ID" > "$TMP_KEY_FILE"

echo "Activating service account from key file"
gcloud auth activate-service-account --key-file="$TMP_KEY_FILE" --project="$PROJECT_ID"

echo "Running synthetic health deploy helper"
bash infra/terraform/tmp_observability/deploy_synthetic_health.sh "$PROJECT_ID" "https://nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app/health"

rm -f "$TMP_KEY_FILE"
echo "Deploy finished (idempotent)." 
