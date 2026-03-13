#!/bin/bash
# Retry Slack notifications idempotently
set -e
PROJECT_ID="nexusshield-prod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/logs/cutover/notifications.log"
mkdir -p "$(dirname "$LOG")"

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG"; }

SLACK_WEBHOOK=$(gcloud secrets versions access latest --secret=slack-webhook --project="$PROJECT_ID" 2>/dev/null || true)
if [ -z "$SLACK_WEBHOOK" ] || echo "$SLACK_WEBHOOK" | grep -q "REPLACE_WITH_SLACK_WEBHOOK\|PLACEHOLDER"; then
  log "✗ Slack webhook missing or placeholder in GSM. Aborting notification retry."
  exit 1
fi

SLACK_MSG='{"text":"🚀 DNS Cutover Complete — Phase 2+3 executed. Logs: logs/cutover/execution_full_*.log"}'

if curl -s -X POST -H 'Content-type: application/json' --data "$SLACK_MSG" "$SLACK_WEBHOOK" >/dev/null 2>&1; then
  log "✓ Slack notification sent successfully"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"phase\":\"phase_3_notifications_retry\",\"status\":\"success\",\"details\":{}}" >> "$REPO_ROOT/logs/cutover/audit-trail.jsonl"
  exit 0
else
  log "✗ Slack notification delivery failed (webhook unreachable)"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"phase\":\"phase_3_notifications_retry\",\"status\":\"failed\",\"details\":{}}" >> "$REPO_ROOT/logs/cutover/audit-trail.jsonl"
  exit 2
fi
