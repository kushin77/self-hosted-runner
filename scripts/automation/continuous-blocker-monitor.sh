#!/usr/bin/env bash
set -euo pipefail

# Continuous blocker monitor: runs ops-blocker-automation.sh every N seconds
# Idempotent: uses a PID file to avoid duplicate runners

WORKDIR="$(cd "$(dirname "$0")/../.." && pwd)"
PIDFILE="$WORKDIR/.continuous_blocker_monitor.pid"
RUNNER="$WORKDIR/scripts/automation/ops-blocker-automation.sh"
INTERVAL=${INTERVAL:-300} # seconds
MAX_ITER=${MAX_ITER:-288} # default 24h (288 * 5min)

if [ -f "$PIDFILE" ]; then
  EXISTPID=$(cat "$PIDFILE" 2>/dev/null || echo "")
  if [ -n "$EXISTPID" ] && kill -0 "$EXISTPID" 2>/dev/null; then
    echo "Monitor already running (pid $EXISTPID). Exiting." >&2
    exit 0
  else
    echo "Stale PID file found, removing." >&2
    rm -f "$PIDFILE" || true
  fi
fi

echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"; exit' INT TERM EXIT

echo "Starting continuous blocker monitor: interval=${INTERVAL}s, max_iter=${MAX_ITER}"

i=0
while [ $i -lt "$MAX_ITER" ]; do
  i=$((i+1))
  echo "[monitor] iteration $i: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -x "$RUNNER" ]; then
    # run verifier then full run
    "$RUNNER" --verify-only || true
    "$RUNNER" || true
  else
    echo "Runner not found: $RUNNER" >&2
  fi

  # quick check for all prerequisites to exit early
  CLUSTER_OK=1
  OIDC_OK=1
  AWS_OK=1
  timeout 5 bash -c "echo >/dev/tcp/192.168.168.42/6443" 2>/dev/null || CLUSTER_OK=0
  gh secret list --json name --jq '.[].name' 2>/dev/null | grep -q AWS_OIDC_ROLE_ARN || OIDC_OK=0
  gh secret list --json name --jq '.[].name' 2>/dev/null | grep -q AWS_ROLE_TO_ASSUME || AWS_OK=0

  if [ "$CLUSTER_OK" -eq 1 ] && [ "$OIDC_OK" -eq 1 ] && [ "$AWS_OK" -eq 1 ]; then
    echo "[monitor] all prerequisites met; exiting monitor." >&2
    gh issue comment 231 --body "Automated monitor: all prerequisites detected; Phase P4 dispatch should have been requested." || true
    rm -f "$PIDFILE" || true
    exit 0
  fi

  sleep "$INTERVAL"
done

echo "Monitor max iterations reached; exiting." >&2
rm -f "$PIDFILE" || true
exit 0
