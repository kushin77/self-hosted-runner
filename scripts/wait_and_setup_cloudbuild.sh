#!/usr/bin/env bash
# scripts/wait_and_setup_cloudbuild.sh
# Poll for Cloud Build GitHub connection and run setup script once available

set -euo pipefail
PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
POLL_INTERVAL=${POLL_INTERVAL:-30}
TIMEOUT=${TIMEOUT:-900} # 15 minutes
LOGFILE=${LOGFILE:-logs/wait_and_setup.log}

mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[WAIT] $(date +'%H:%M:%S') Starting wait-and-setup for Cloud Build connection (project=$PROJECT, region=$REGION)"

elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
  echo "[WAIT] $(date +'%H:%M:%S') Checking for connections... (elapsed=${elapsed}s)"
  conns=$(gcloud builds connections list --project="$PROJECT" --region="$REGION" --format=json 2>/dev/null || echo "[]")
  count=$(echo "$conns" | jq 'length')
  if [ "$count" -gt 0 ]; then
    echo "[WAIT] $(date +'%H:%M:%S') Found $count connection(s). Running setup script..."
    bash scripts/setup-cloudbuild-triggers.sh || {
      echo "[WAIT] $(date +'%H:%M:%S') setup script failed; check logs"
      exit 1
    }
    echo "[WAIT] $(date +'%H:%M:%S') Completed setup"
    exit 0
  fi
  echo "[WAIT] $(date +'%H:%M:%S') No connections yet. Sleeping ${POLL_INTERVAL}s..."
  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
done

echo "[WAIT] $(date +'%H:%M:%S') Timeout reached (${TIMEOUT}s). Exiting."
exit 2
