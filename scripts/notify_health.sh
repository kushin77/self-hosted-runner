#!/bin/bash
set -e

# Simple Slack notifier helper
# Usage: notify_health.sh [webhook_url] "message"
# If `SLACK_WEBHOOK` env var is set, it will be used instead of the first arg.

WEBHOOK="${SLACK_WEBHOOK:-$1}"
MSG="${2:-Health notification from $(hostname)}"

if [ -z "$WEBHOOK" ]; then
  echo "SLACK_WEBHOOK not set; skipping notification"
  exit 0
fi

# Build payload (use jq when available for proper escaping)
if command -v jq >/dev/null 2>&1; then
  payload=$(jq -n --arg text "$MSG" '{text: $text}')
else
  payload=$(printf '{"text":"%s"}' "$MSG")
fi

curl --silent --show-error --fail -X POST -H 'Content-type: application/json' --data "$payload" "$WEBHOOK" || true
echo "Notification attempted (webhook configured)"
