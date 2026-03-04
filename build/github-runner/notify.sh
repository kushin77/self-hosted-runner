#!/usr/bin/env bash
set -euo pipefail

# notify.sh - Simple webhook notifier used by runner-watchdog
# Environment variables supported:
# - WATCHDOG_WEBHOOK_URL : full webhook URL (Slack Incoming Webhook or other)
# - WATCHDOG_ALERT_CHANNEL : optional channel (Slack)
# - WATCHDOG_ALERT_USERNAME : optional username
# - WATCHDOG_ALERT_ICON_EMOJI : optional emoji

send_alert() {
  local title="$1"
  local body="$2"

  if [[ -z "${WATCHDOG_WEBHOOK_URL:-}" ]]; then
    echo "[notify] WATCHDOG_WEBHOOK_URL not set; skipping alert: $title" >&2
    return 0
  fi

  # Prepare payload for Slack incoming webhook (common case)
  local payload
  payload=$(jq -n --arg text "$title\n$body" '{text: $text}') || true

  # Fallback to curl raw post if jq not available
  if command -v jq >/dev/null 2>&1; then
    curl -sSf -X POST -H 'Content-Type: application/json' --data "$payload" "$WATCHDOG_WEBHOOK_URL" >/dev/null || echo "[notify] webhook post failed" >&2
  else
    printf '{"text":"%s\n%s"}' "$title" "$body" | curl -sSf -X POST -H 'Content-Type: application/json' --data @- "$WATCHDOG_WEBHOOK_URL" >/dev/null || echo "[notify] webhook post failed" >&2
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # invoked directly for quick test
  send_alert "[test] Watchdog notification" "This is a test notification from runner-watchdog"
fi
