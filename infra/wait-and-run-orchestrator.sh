#!/usr/bin/env bash
set -euo pipefail

# Poll for deployer SA key in GSM and, when present, activate it and run orchestrator.
# Run on the runner host (or CI host) with gcloud installed.

PROJECT=${PROJECT:-nexusshield-prod}
SECRET_NAME=${SECRET_NAME:-deployer-sa-key}
CHECK_INTERVAL=${CHECK_INTERVAL:-10}
MAX_RETRIES=${MAX_RETRIES:-60}
TMP_KEY=/tmp/deployer-sa-key.json

echo "Waiting for secret '$SECRET_NAME' in project $PROJECT..."
count=0
while true; do
  if gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" >"$TMP_KEY" 2>/dev/null; then
    echo "Deployer key retrieved to $TMP_KEY"
    chmod 600 "$TMP_KEY"
    echo "Activating deployer SA..."
    gcloud auth activate-service-account --key-file="$TMP_KEY" --project="$PROJECT"
    echo "Running orchestrator..."
    bash infra/deploy-prevent-releases.sh
    exit 0
  fi
  count=$((count+1))
  if [ "$count" -ge "$MAX_RETRIES" ]; then
    echo "Timeout waiting for secret $SECRET_NAME after $((MAX_RETRIES * CHECK_INTERVAL))s"
    exit 2
  fi
  sleep "$CHECK_INTERVAL"
done
