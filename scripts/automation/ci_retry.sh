#!/usr/bin/env bash
set -euo pipefail
# Simple retry wrapper with exponential backoff.
# Usage: ci_retry.sh <max_attempts> <initial_delay_seconds> -- <command> [args...]

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <max_attempts> <initial_delay_seconds> -- <command> [args...]" >&2
  exit 2
fi

MAX_ATTEMPTS="$1"
DELAY="$2"
shift 2

if [ "$1" != "--" ]; then
  echo "Missing -- separator" >&2
  exit 2
fi
shift 1

ATTEMPT=1
CMD=("$@")
while true; do
  echo "[ci-retry] Attempt #$ATTEMPT: ${CMD[*]}"
  if "${CMD[@]}"; then
    echo "[ci-retry] Command succeeded"
    exit 0
  fi
  if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    echo "[ci-retry] Reached max attempts ($MAX_ATTEMPTS). Failing." >&2
    exit 1
  fi
  SLEEP=$DELAY
  echo "[ci-retry] Command failed; sleeping ${SLEEP}s before retry" >&2
  sleep "$SLEEP"
  ATTEMPT=$((ATTEMPT+1))
  DELAY=$((DELAY*2))
done
