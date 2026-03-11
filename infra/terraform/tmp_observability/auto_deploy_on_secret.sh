#!/usr/bin/env bash
set -euo pipefail

# Auto-deploy helper: polls Secret Manager for a service-account key secret
# and runs the GSM-based deploy helper when available.
# Usage: ./auto_deploy_on_secret.sh [PROJECT] [SECRET_NAME] [TARGET_URL]

PROJECT=${1:-${PROJECT:-nexusshield-prod}}
SECRET_NAME=${2:-deploy-sa-key}
TARGET_URL=${3:-https://nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app/health}
POLL_INTERVAL=${POLL_INTERVAL:-15} # seconds

echo "Auto-deploy watcher starting. Project=$PROJECT Secret=$SECRET_NAME"

while true; do
  if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Secret $SECRET_NAME found in project $PROJECT — attempting GSM-based deploy"
    # Call existing deploy helper (it handles temp key and activation)
    bash infra/terraform/tmp_observability/deploy_with_gsm.sh "$PROJECT" "$SECRET_NAME"

    echo "Deploy helper finished. Verifying function existence..."
    if gcloud functions describe synthetic-health-check --project="$PROJECT" --region=us-central1 >/dev/null 2>&1; then
      echo "Synthetic health-check function present. Deployment complete.";
      exit 0
    else
      echo "Warning: function not found after deploy. Will retry after ${POLL_INTERVAL}s.";
    fi
  else
    echo "Secret $SECRET_NAME not present yet. Sleeping ${POLL_INTERVAL}s..."
  fi
  sleep "$POLL_INTERVAL"
done
