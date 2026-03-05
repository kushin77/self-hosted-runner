#!/usr/bin/env bash
set -euo pipefail

HOST=192.168.168.42
PORT=6443
CHECK_INTERVAL=30
LOG=/tmp/auto_keda_trigger.log
REPO="kushin77/self-hosted-runner"
WORKFLOW="keda-smoke-test.yml"

echo "auto-keda-watcher started at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "$LOG"

# Optional: post to Slack when triggered if SLACK_WEBHOOK is provided
post_slack() {
  if [ -n "${SLACK_WEBHOOK:-}" ]; then
    payload=$(printf '{"text":"%s"}' "$1")
    curl -sS -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
  fi
}
while true; do
  if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [INFO] Staging API $HOST:$PORT reachable — dispatching workflow" | tee -a "$LOG"
    post_slack "Staging API $HOST:$PORT reachable — dispatching KEDA smoke test workflow"
    if command -v gh >/dev/null 2>&1; then
      if gh workflow run "$WORKFLOW" -f use_real_cluster=true --repo "$REPO"; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [INFO] Dispatch requested" | tee -a "$LOG"
        post_slack "KEDA smoke test workflow dispatched (use_real_cluster=true)."
      else
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [ERROR] Failed to dispatch workflow" | tee -a "$LOG"
        post_slack "Failed to dispatch KEDA smoke test workflow against staging."
      fi
    else
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [ERROR] gh CLI not available; cannot dispatch" | tee -a "$LOG"
      post_slack "Auto-watcher cannot dispatch KEDA smoke test (gh CLI missing)."
    fi
    break
  else
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [INFO] Staging API $HOST:$PORT not reachable; sleeping $CHECK_INTERVALs" | tee -a "$LOG"
    sleep $CHECK_INTERVAL
  fi
done

echo "auto-keda-watcher finished at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "$LOG"
