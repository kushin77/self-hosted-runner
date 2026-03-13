#!/usr/bin/env bash
set -euo pipefail

# alert-on-failure.sh
# Sends a POST to ALERT_WEBHOOK if set. Falls back to syslog.
# Implements simple deduplication and escalation: only send an external alert
# after ALERT_THRESHOLD consecutive failures. Uses a cooldown period to avoid
# repeated paging.

MESSAGE=${1:-"Service failure on $(hostname)"}
ALERT_WEBHOOK=${ALERT_WEBHOOK:-}
ALERT_THRESHOLD=${ALERT_THRESHOLD:-3}
ALERT_COOLDOWN_SECONDS=${ALERT_COOLDOWN_SECONDS:-3600}
COUNTER_DIR=${COUNTER_DIR:-$HOME/.cache/portal}
COUNTER_FILE="$COUNTER_DIR/alert_count"
LAST_ALERT_FILE="$COUNTER_DIR/last_alert_ts"

mkdir -p "$COUNTER_DIR"

# read current counter
count=0
if [[ -f "$COUNTER_FILE" ]]; then
  count=$(cat "$COUNTER_FILE" || echo 0)
fi
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

# check cooldown
now=$(date +%s)
last_alert=0
if [[ -f "$LAST_ALERT_FILE" ]]; then
  last_alert=$(cat "$LAST_ALERT_FILE" || echo 0)
fi

if (( count >= ALERT_THRESHOLD )); then
  # if last alert is within cooldown, skip sending but reset counter
  if (( now - last_alert < ALERT_COOLDOWN_SECONDS )); then
    logger -t portal-smoke-check "Alert threshold reached but in cooldown; skipping external alert. (${count} failures)"
    # reset counter to avoid repeated increments
    echo 0 > "$COUNTER_FILE"
    exit 0
  fi

  if [[ -n "$ALERT_WEBHOOK" ]]; then
    if curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"text\": \"${MESSAGE}\"}" "$ALERT_WEBHOOK"; then
      logger -t portal-smoke-check "Sent alert to webhook after ${count} consecutive failures"
      echo "$now" > "$LAST_ALERT_FILE"
      echo 0 > "$COUNTER_FILE"
      exit 0
    else
      logger -t portal-smoke-check "Failed to send alert to webhook; will retry later"
      # do not reset counter so next run may escalate again
      exit 1
    fi
  else
    logger -t portal-smoke-check "${MESSAGE} (no webhook configured)"
    echo "$now" > "$LAST_ALERT_FILE"
    echo 0 > "$COUNTER_FILE"
    exit 0
  fi
else
  logger -t portal-smoke-check "Smoke-check failure recorded (${count}/${ALERT_THRESHOLD})"
  exit 0
fi
