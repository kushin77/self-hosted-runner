#!/usr/bin/env bash
set -euo pipefail

# Poll for a repository secret and trigger the Phase-3 production deploy workflow when present.
# Usage: wait-and-trigger-phase3.sh [timeout-seconds] [interval-seconds]

REPO="kushin77/self-hosted-runner"
SECRET_NAME="GCP_SERVICE_ACCOUNT_KEY"
WORKFLOW_PATH=".github/workflows/phase3-production-deploy.yml"
REF="main"

TIMEOUT_SECONDS=${1:-1800}
INTERVAL_SECONDS=${2:-10}

END=$((SECONDS+TIMEOUT_SECONDS))
LOGFILE="/tmp/wait-and-trigger-phase3.log"

echo "[wait-and-trigger] Starting; timeout=${TIMEOUT_SECONDS}s, interval=${INTERVAL_SECONDS}s" | tee -a "$LOGFILE"

while [ $SECONDS -lt $END ]; do
  echo "[wait-and-trigger] Checking for secret $SECRET_NAME..." | tee -a "$LOGFILE"
  if gh secret list --repo "$REPO" | grep -q "^$SECRET_NAME\b"; then
    echo "[wait-and-trigger] Secret found. Triggering Phase-3 workflow." | tee -a "$LOGFILE"
    gh workflow run "$WORKFLOW_PATH" --ref "$REF" --repo "$REPO"
    echo "[wait-and-trigger] Trigger requested; exiting." | tee -a "$LOGFILE"
    exit 0
  fi
  sleep "$INTERVAL_SECONDS"
done

echo "[wait-and-trigger] Timeout reached without secret present." | tee -a "$LOGFILE"
exit 2
