#!/usr/bin/env bash
set -euo pipefail
# Auto retryer for keda-smoke-test workflow. Logs attempts and comments to issue.
# Usage: ./auto-retry-keda.sh [POLL_INTERVAL_SECONDS] [MAX_ATTEMPTS]

REPO="kushin77/self-hosted-runner"
WORKFLOW="keda-smoke-test.yml"
ISSUE=342
POLL_INTERVAL=${1:-300}
MAX_ATTEMPTS=${2:-12}

LOGFILE="/tmp/keda_dispatch_attempts.log"
touch "$LOGFILE"

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  ts=$(date --iso-8601=seconds)
  echo "$ts: dispatch attempt $i" >> "$LOGFILE"
  if gh workflow run "$WORKFLOW" --repo "$REPO" -f use_real_cluster=true >> "$LOGFILE" 2>&1; then
    echo "$ts: workflow dispatch command returned success" >> "$LOGFILE"
  else
    echo "$ts: workflow dispatch command failed or returned non-zero" >> "$LOGFILE"
  fi
  tail -n 200 "$LOGFILE" > /tmp/keda_dispatch_tail.log || true
  gh issue comment "$ISSUE" --repo "$REPO" --body "Automated retry of $WORKFLOW (attempt $i at $ts). Recent output (tail 200 lines):\n\n$(sed -n '1,200p' /tmp/keda_dispatch_tail.log)" || true
  sleep "$POLL_INTERVAL"
done

echo "Completed $MAX_ATTEMPTS attempts for workflow $WORKFLOW" >> "$LOGFILE"
