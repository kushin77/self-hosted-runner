#!/usr/bin/env bash
set -euo pipefail

# Notify on validator failure via Slack webhook stored in GSM
GSM_PROJECT="nexusshield-prod"
SLACK_SECRET="slack-webhook"
WEBHOOK=$(gcloud secrets versions access latest --secret="$SLACK_SECRET" --project="$GSM_PROJECT" 2>/dev/null || true)
if [ -z "$WEBHOOK" ]; then
  echo "No slack webhook configured in GSM ($SLACK_SECRET)" >&2
  exit 1
fi

PAYLOAD=$(jq -n --arg txt "$1" '{text:$txt}')
curl -sS -X POST -H "Content-type: application/json" --data "$PAYLOAD" "$WEBHOOK" >/dev/null 2>&1 || true
