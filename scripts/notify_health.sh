#!/bin/bash
# Simple health notification script. Use by passing message as first arg.
# Requires SLACK_WEBHOOK env var or set in environment/secret store.
set -e
MSG=${1:-"Runner health event"}
if [ -z "$SLACK_WEBHOOK" ]; then
  echo "SLACK_WEBHOOK not set — skipping Slack notification"
  exit 0
fi
payload=$(jq -n --arg text "$MSG" '{text: $text}')
curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK" >/dev/null || true
