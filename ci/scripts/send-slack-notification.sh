#!/usr/bin/env bash
set -euo pipefail

# ci/scripts/send-slack-notification.sh
# Usage: send-slack-notification.sh <webhook-url> <message>

WEBHOOK=${1:-${SLACK_WEBHOOK:-}}
MSG=${2:-}

if [[ -z "$WEBHOOK" ]]; then
  echo "SLACK webhook not set; skipping notification"
  exit 0
fi

if [[ -z "$MSG" ]]; then
  echo "No message provided; skipping"
  exit 0
fi

payload=$(jq -n --arg text "$MSG" '{text: $text}')

curl -sS -X POST -H 'Content-type: application/json' --data "$payload" "$WEBHOOK"

echo "Notification sent"
