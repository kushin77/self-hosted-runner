#!/bin/bash
set -e

# Simple Slack notifier helper
# Usage: notify_health.sh [webhook_url] "message"
# If SLACK_WEBHOOK env var is set, it will be used instead of first arg.

WEBHOOK="${SLACK_WEBHOOK:-$1}"
MSG="$2"

if [ -z "$WEBHOOK" ]; then
  echo "SLACK_WEBHOOK not set; skipping notification"
  exit 0
fi

if [ -z "$MSG" ]; then
  MSG="Health notification from $(hostname)"
fi

payload=$(printf '{"text":"%s"}' "${MSG}")
curl --silent --show-error --fail -X POST -H 'Content-type: application/json' --data "$payload" "$WEBHOOK" || true
echo "Sent notification to Slack (webhook configured)"
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
