#!/bin/bash
# Watch GSM for slack-webhook secret and run retry-notifications.sh when available
set -e
PROJECT_ID="nexusshield-prod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG="$REPO_ROOT/logs/cutover/auto-retry-notifications.log"
mkdir -p "$(dirname "$LOG")"

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG"; }

log "Auto-retry watcher started (checking slack-webhook every 30s)"
while true; do
  SLACK_WEBHOOK=$(gcloud secrets versions access latest --secret=slack-webhook --project="$PROJECT_ID" 2>/dev/null || true)
  if [ -n "$SLACK_WEBHOOK" ] && ! echo "$SLACK_WEBHOOK" | grep -q "REPLACE_WITH_SLACK_WEBHOOK\|PLACEHOLDER"; then
    log "✓ Valid slack-webhook found in GSM; attempting retry-notifications.sh"
    if bash "$REPO_ROOT/scripts/ops/retry-notifications.sh"; then
      log "✓ Notifications retried successfully; watcher exiting"
      exit 0
    else
      log "⚠ Notification retry failed; will retry in 30s"
    fi
  else
    log "Token not ready (missing/placeholder). Waiting..."
  fi
  sleep 30
done
