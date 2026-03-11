#!/usr/bin/env bash
set -euo pipefail

# Wrapper for nightly verify-rotation job with Slack alerting
ROOT_DIR="/home/akushnir/self-hosted-runner"
SCRIPT="$ROOT_DIR/scripts/tests/verify-rotation.sh"
LOG_BUCKET="gs://nexusshield-ops-logs/verify-rotation"
LOG_FILE="$ROOT_DIR/ops/internal_runner/verify-rotation-$(date +%F).log"

export PROJECT=${PROJECT:-nexusshield-prod}

# Optionally fetch Slack webhook from GSM for alerting
SLACK_WEBHOOK_SECRET=${SLACK_WEBHOOK_SECRET:-slack-webhook-ops-alerts}
SLACK_WEBHOOK=""
if gcloud secrets versions access latest --secret="$SLACK_WEBHOOK_SECRET" --project="$PROJECT" >/dev/null 2>&1; then
  SLACK_WEBHOOK=$(gcloud secrets versions access latest --secret="$SLACK_WEBHOOK_SECRET" --project="$PROJECT" 2>/dev/null || true)
fi

send_alert() {
  local message="$1"
  if [ -n "$SLACK_WEBHOOK" ]; then
    curl -X POST "$SLACK_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"[NexusShield] $message\"}" \
      >/dev/null 2>&1 || true
  fi
}

echo "[run-verify-rotation] starting at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$LOG_FILE"

# Run verification script
"$SCRIPT" >> "$LOG_FILE" 2>&1 || {
  echo "[run-verify-rotation] verify script failed" >> "$LOG_FILE"
  FAIL_MSG="verify-rotation job failed at $(date -u +'%Y-%m-%dT%H:%M:%SZ'). See: $LOG_BUCKET/verify-rotation-$(date +%F).log"
  send_alert "$FAIL_MSG"
  gsutil cp "$LOG_FILE" "$LOG_BUCKET/" || true
  exit 2
}

# Upload log
gsutil cp "$LOG_FILE" "$LOG_BUCKET/" || true

echo "[run-verify-rotation] completed at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$LOG_FILE"
