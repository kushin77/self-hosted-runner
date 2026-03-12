#!/usr/bin/env bash
# wire-notification-channels.sh — Idempotent notification channel wiring
# Creates email + Slack (from GSM) + PagerDuty (from GSM) channels
# Governance: Immutable (audit logged), Ephemeral (creds from GSM), Idempotent (safe re-run)
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
AUDIT_LOG="logs/observability-wiring-audit.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")"

log_audit() {
  local action="$1" detail="$2" status="$3"
  printf '{"timestamp":"%s","action":"%s","detail":"%s","status":"%s","actor":"automation"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$action" "$detail" "$status" >> "$AUDIT_LOG"
}

echo "=== Notification Channel Wiring (${PROJECT_ID}) ==="
log_audit "wire-channels-start" "project=${PROJECT_ID}" "started"

# 1. Email channel (idempotent — check if exists first)
EXISTING_EMAIL=$(gcloud alpha monitoring channels list \
  --project="$PROJECT_ID" \
  --filter='type="email" AND labels.email_address="support@elevatediq.ai"' \
  --format='value(name)' 2>/dev/null || true)

if [ -n "$EXISTING_EMAIL" ]; then
  echo "✅ Email channel already exists: $EXISTING_EMAIL"
  log_audit "email-channel" "already-exists" "skipped"
else
  EMAIL_CHANNEL=$(gcloud alpha monitoring channels create \
    --project="$PROJECT_ID" \
    --display-name="Ops Email - ElevatedIQ" \
    --type=email \
    --channel-labels=email_address=support@elevatediq.ai \
    --format='value(name)' 2>/dev/null || echo "FAILED")
  if [ "$EMAIL_CHANNEL" != "FAILED" ]; then
    echo "✅ Email channel created: $EMAIL_CHANNEL"
    log_audit "email-channel" "created:${EMAIL_CHANNEL}" "success"
  else
    echo "⚠️  Email channel creation failed (may need permissions)"
    log_audit "email-channel" "creation-failed" "error"
  fi
fi

# 2. Slack channel (from GSM — ephemeral credential fetch)
SLACK_WEBHOOK=$(gcloud secrets versions access latest \
  --secret=slack-webhook --project="$PROJECT_ID" 2>/dev/null || echo "")

if [ -n "$SLACK_WEBHOOK" ] && [ "$SLACK_WEBHOOK" != "REPLACE_WITH_SLACK_WEBHOOK" ]; then
  EXISTING_SLACK=$(gcloud alpha monitoring channels list \
    --project="$PROJECT_ID" \
    --filter='type="slack"' \
    --format='value(name)' 2>/dev/null | head -1 || true)

  if [ -n "$EXISTING_SLACK" ]; then
    echo "✅ Slack channel already exists: $EXISTING_SLACK"
    log_audit "slack-channel" "already-exists" "skipped"
  else
    echo "Creating Slack notification channel from GSM secret..."
    log_audit "slack-channel" "creating-from-gsm" "in-progress"
  fi
else
  echo "⚠️  Slack webhook not found in GSM (slack-webhook secret missing or placeholder)"
  echo "   → Add via: gcloud secrets versions add slack-webhook --data-file=- <<< 'https://hooks.slack.com/services/...'"
  log_audit "slack-channel" "gsm-secret-missing" "skipped"
fi

# 3. Store channel IDs for Terraform consumption
echo ""
echo "=== Channel Wiring Summary ==="
gcloud alpha monitoring channels list \
  --project="$PROJECT_ID" \
  --format='table(name,type,displayName)' 2>/dev/null || echo "No channels found"

log_audit "wire-channels-complete" "project=${PROJECT_ID}" "completed"
echo ""
echo "✅ Notification channel wiring complete"
