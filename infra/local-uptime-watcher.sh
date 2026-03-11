#!/usr/bin/env bash
set -euo pipefail

# Local uptime watcher for prevent-releases
# - polls /health every 60s
# - writes append-only JSONL logs to /tmp/uptime-prevent-releases-*.jsonl
# - after 3 consecutive failures, creates /tmp/prevent-releases-alert.triggered
# - if GITHUB_TOKEN is set, posts a comment to issue #2620

PROJECT=${PROJECT:-nexusshield-prod}
SERVICE_URL=${SERVICE_URL:-https://prevent-releases-2tqp6t4txq-uc.a.run.app}
HEALTH_PATH=${HEALTH_PATH:-/health}
INTERVAL=${INTERVAL:-60}
FAIL_THRESHOLD=${FAIL_THRESHOLD:-3}
LOG=/tmp/uptime-prevent-releases-$(date +%Y%m%d).jsonl
ALERT_FLAG=/tmp/prevent-releases-alert.triggered
ISSUE_NUMBER=${ISSUE_NUMBER:-2620}

post_github_comment() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN not set; skipping GitHub notification"
    return 1
  fi
  local body="$1"
  curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/kushin77/self-hosted-runner/issues/${ISSUE_NUMBER}/comments \
    -d "$(jq -n --arg b "$body" '{body:$b}')" >/dev/null
}

log_event() {
  local level=$1; local msg=$2
  jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg l "$level" --arg m "$msg" '{timestamp:$t,level:$l,message:$m}' >> "$LOG"
}

fail_count=0
while true; do
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if curl -s -f -o /dev/null "${SERVICE_URL}${HEALTH_PATH}"; then
    log_event "INFO" "health OK"
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ] && [ -f "$ALERT_FLAG" ]; then
      # Recovery: remove alert flag and post recovery comment
      rm -f "$ALERT_FLAG"
      log_event "RECOVERY" "Service recovered"
      post_github_comment "Automated monitor: prevent-releases recovered at ${timestamp}" || true
    fi
    fail_count=0
  else
    fail_count=$((fail_count+1))
    log_event "ERROR" "health check failed (count=${fail_count})"
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ] && [ ! -f "$ALERT_FLAG" ]; then
      touch "$ALERT_FLAG"
      log_event "ALERT" "Alert threshold reached; flag created at ${timestamp}"
      post_github_comment "ALERT: prevent-releases failing health checks (>=${FAIL_THRESHOLD}) as of ${timestamp}. Investigation required." || true
    fi
  fi
  sleep "$INTERVAL"
done
