#!/usr/bin/env bash
set -euo pipefail

REPO="kushin77/self-hosted-runner"
LOG=/tmp/dispatch_retry.log
MAX_ATTEMPTS=${MAX_ATTEMPTS:-30}
SLEEP_BASE=${SLEEP_BASE:-30}

echo "Starting dispatch retry loop for $REPO" | tee -a "$LOG"
i=0
while [ "$i" -lt "$MAX_ATTEMPTS" ]; do
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$TS] Attempt $((i+1))/${MAX_ATTEMPTS}: trying to dispatch security-audit.yml" | tee -a "$LOG"

  set +e
  OUT=$(gh workflow run security-audit.yml --repo "$REPO" --ref main 2>&1)
  RC=$?
  set -e

  if [ $RC -eq 0 ]; then
    echo "[$TS] Dispatch succeeded: $OUT" | tee -a "$LOG"
    # Try to trigger remediation wrapper too (best-effort)
    gh workflow run security-findings-remediation.yml --repo "$REPO" --ref main 2>&1 || true
    echo "Completed: dispatch succeeded" | tee -a "$LOG"
    exit 0
  fi

  echo "[$TS] Dispatch failed (rc=$RC): $OUT" | tee -a "$LOG"

  # If we see HTTP 422, attempt a noop touch to force re-registration
  if echo "$OUT" | grep -qi "HTTP 422\|does not have 'workflow_dispatch'"; then
    echo "[$TS] Detected 422 parse/registration error; touching reregister marker and pushing to main" | tee -a "$LOG"
    echo "reregister: $TS" >> .github/workflows/.reregister || true
    git add .github/workflows/.reregister || true
    git commit -m "chore: reregister workflows ($TS)" || true
    git push origin main || true
    echo "[$TS] noop commit pushed (may re-register workflows)" | tee -a "$LOG"
  fi

  # Exponential backoff sleep
  SLEEP=$((SLEEP_BASE * (i+1)))
  echo "[$TS] Sleeping ${SLEEP}s before next attempt" | tee -a "$LOG"
  sleep "$SLEEP"
  i=$((i+1))
done

echo "Reached max attempts ($MAX_ATTEMPTS) without successful dispatch. See $LOG" | tee -a "$LOG"
exit 2
