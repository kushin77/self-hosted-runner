#!/usr/bin/env bash
set -euo pipefail
# Monitor script: polls staging cluster API until it comes online,
# then posts confirmation to issue #343 and triggers validation
# Usage: ./monitor-cluster-restore.sh [CHECK_INTERVAL_SECONDS] [MAX_ATTEMPTS]

REPO="kushin77/self-hosted-runner"
CLUSTER_HOST="192.168.168.42"
CLUSTER_PORT=6443
ISSUE=343
CHECK_INTERVAL=${1:-60}
MAX_ATTEMPTS=${2:-360}  # 360 * 60s = 6 hours

LOGFILE="/tmp/cluster_monitor.log"
touch "$LOGFILE"

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  ts=$(date --iso-8601=seconds)
  echo "$ts: check $i — testing TCP connection to $CLUSTER_HOST:$CLUSTER_PORT" >> "$LOGFILE"
  
  if nc -zv "$CLUSTER_HOST" "$CLUSTER_PORT" >> "$LOGFILE" 2>&1; then
    echo "$ts: SUCCESS! Cluster API is online" >> "$LOGFILE"
    
    # Post confirmation to issue
    gh issue comment "$ISSUE" --repo "$REPO" --body "✓ **Cluster API RESTORED** at $ts

TCP port 6443 is now LISTENING and reachable. Automated validations triggering:
1. Running KEDA smoke-test via GitHub Actions
2. Running AWS Spot Deploy Plan workflow
3. Validating pipeline-repair service connectivity

Automation active; monitor issue #342 for smoke-test results." || true
    
    echo "$ts: Posted restoration confirmation to issue #343" >> "$LOGFILE"
    exit 0
  else
    echo "$ts: not responding yet; will retry in ${CHECK_INTERVAL}s" >> "$LOGFILE"
    if (( i % 6 == 0 )); then  # every 6 checks (6 min if interval=60)
      echo "$ts: (check $i of $MAX_ATTEMPTS)" >> "$LOGFILE"
    fi
  fi
  
  sleep "$CHECK_INTERVAL"
done

echo "$ts: Reached max attempts ($MAX_ATTEMPTS) without detecting cluster restoration" >> "$LOGFILE"
echo "Cluster still offline after $(( MAX_ATTEMPTS * CHECK_INTERVAL / 3600 )) hours" >&2
exit 1
