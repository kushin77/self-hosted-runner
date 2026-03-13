#!/bin/bash
set -euo pipefail

# Poller for cutover: monitors cutover log and Grafana, sends Slack alerts on errors
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs/cutover"
POLL_LOG="$LOG_DIR/poller.log"
CUTOVER_LOG="$LOG_DIR/execution_$(ls -1t $LOG_DIR/execution_*.log 2>/dev/null | head -1 2>/dev/null || echo '')"
POLL_INTERVAL=${POLL_INTERVAL:-30}
GRAFANA_URL=${GRAFANA_URL:-http://192.168.168.42:3000}
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
STATE_DIR="$PROJECT_ROOT/.poller_state"
mkdir -p "$LOG_DIR" "$STATE_DIR"
ALERT_HASH_FILE="$STATE_DIR/last_alert_hash"

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$POLL_LOG"; }

send_slack() {
  local msg="$1"
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"$msg\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
  fi
}

compute_hash() {
  sha256sum | awk '{print $1}'
}

while true; do
  CUTOVER_LOG_FILE=$(ls -1t "$LOG_DIR"/execution_*.log 2>/dev/null | head -1 || true)
  if [ -z "$CUTOVER_LOG_FILE" ]; then
    log "No cutover log found yet"
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Check recent log lines for errors
  recent_lines=$(tail -n 200 "$CUTOVER_LOG_FILE" 2>/dev/null || true)
  error_matches=$(echo "$recent_lines" | egrep -i "\b(error|failed|fail|exception|traceback|critical)\b" || true)

  if [ -n "$error_matches" ]; then
    # Hash recent matches to avoid duplicate alerts
    echo "$error_matches" | compute_hash > "$STATE_DIR/recent_hash"
    recent_hash=$(cat "$STATE_DIR/recent_hash")
    last_alert_hash=$(cat "$ALERT_HASH_FILE" 2>/dev/null || echo "")
    if [ "$recent_hash" != "$last_alert_hash" ]; then
      log "ALERT: New error patterns detected in cutover log"
      echo "$error_matches" | sed -n '1,30p' >> "$POLL_LOG"
      send_slack "Cutover poller detected errors:\n\n$(echo "$error_matches" | sed -n '1,20p')"
      echo "$recent_hash" > "$ALERT_HASH_FILE"
    else
      log "Errors detected but already alerted (no duplicate alert)"
    fi
  else
    log "No error patterns in recent cutover log"
  fi

  # Check Grafana status
  grafana_code=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL" || echo "000")
  if [ "$grafana_code" != "200" ]; then
    log "ALERT: Grafana not healthy (HTTP $grafana_code)"
    send_slack "Cutover poller: Grafana health check returned HTTP $grafana_code (expected 200)"
  else
    log "Grafana OK (HTTP 200)"
  fi

  sleep "$POLL_INTERVAL"
done
