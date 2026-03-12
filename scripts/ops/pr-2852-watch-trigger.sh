#!/usr/bin/env bash
set -euo pipefail

REPO="kushin77/self-hosted-runner"
PR=2852
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pr-2852-watch-$(date -u +%Y%m%dT%H%M%SZ).log"

echo "Starting PR watcher for $REPO #$PR" | tee -a "$LOG_FILE"

action_on_merge(){
  echo "PR $PR merged — triggering Cloud Build" | tee -a "$LOG_FILE"
  PROJECT_ID="${PROJECT_ID:-}"
  if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
  fi
  if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: GCP project ID not found. Set PROJECT_ID env or run 'gcloud config set project'." | tee -a "$LOG_FILE"
    return 1
  fi
  echo "Using GCP project: $PROJECT_ID" | tee -a "$LOG_FILE"
  echo "Submitting Cloud Build..." | tee -a "$LOG_FILE"
  gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml --substitutions=PROJECT_ID="$PROJECT_ID",_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main 2>&1 | tee -a "$LOG_FILE"
}

while true; do
  state=$(gh pr view "$PR" --repo "$REPO" --json state -q .state 2>/dev/null || true)
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PR state: ${state:-UNKNOWN}" | tee -a "$LOG_FILE"
  if [ "$state" = "MERGED" ]; then
    action_on_merge || true
    echo "Watcher finished (PR merged)" | tee -a "$LOG_FILE"
    exit 0
  fi
  if [ "$state" = "CLOSED" ]; then
    echo "PR closed without merge; exiting." | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 30
done
