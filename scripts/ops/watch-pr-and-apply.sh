#!/usr/bin/env bash
set -euo pipefail

PR=${1:-2653}
POLL_SEC=${2:-60}
TIMEOUT_SEC=${3:-86400} # default 24h
LOGDIR="logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/pr-${PR}-watch-$(date -u +%Y%m%dT%H%M%SZ).log"

echo "Starting PR watch for #$PR" | tee -a "$LOGFILE"
START=$(date +%s)
while true; do
  now=$(date +%s)
  elapsed=$((now-START))
  if [ $elapsed -ge $TIMEOUT_SEC ]; then
    echo "Timeout reached after $elapsed seconds; exiting" | tee -a "$LOGFILE"
    exit 2
  fi
  merged=$(gh pr view "$PR" --json merged --jq .merged 2>/dev/null || echo "false")
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PR #$PR merged? $merged" | tee -a "$LOGFILE"
  if [ "$merged" = "true" ]; then
    echo "PR #$PR merged — running retry apply" | tee -a "$LOGFILE"
    bash scripts/ops/retry-kubectl-apply.sh  ops 120 30 2>&1 | tee -a "$LOGFILE" || true
    echo "Apply attempt(s) completed; exiting" | tee -a "$LOGFILE"
    exit 0
  fi
  sleep "$POLL_SEC"
done
