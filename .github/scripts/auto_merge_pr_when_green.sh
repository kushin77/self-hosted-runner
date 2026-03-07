#!/usr/bin/env bash
# Poll PR and merge when ready (idempotent)
set -euo pipefail
REPO=${1:-kushin77/self-hosted-runner}
PR=${2:-992}
INTERVAL=${3:-30}
MAX_ATTEMPTS=${4:-120} # ~1 hour
attempt=0
while true; do
  attempt=$((attempt+1))
  if [ $attempt -gt $MAX_ATTEMPTS ]; then
    echo "Exceeded max attempts ($MAX_ATTEMPTS). Exiting."
    exit 2
  fi
  echo "Checking PR $PR (attempt $attempt)"
  data=$(gh pr view "$PR" --repo "$REPO" --json number,state,mergeable,mergeStateStatus,mergedAt --jq '.')
  state=$(echo "$data" | jq -r .state)
  mergedAt=$(echo "$data" | jq -r .mergedAt)
  mergeable=$(echo "$data" | jq -r .mergeable)
  mergeStateStatus=$(echo "$data" | jq -r .mergeStateStatus)
  echo "state=$state mergeable=$mergeable mergeStateStatus=$mergeStateStatus mergedAt=$mergedAt"
  if [ "$state" = "MERGED" ]; then
    echo "PR $PR already merged (mergedAt=$mergedAt). Exiting."
    exit 0
  fi
  if [ "$state" = "CLOSED" ]; then
    echo "PR $PR closed without merge. Exiting."
    exit 0
  fi
  # If GitHub reports mergeable or the mergeStateStatus is 'CLEAN' or 'UNKNOWN', attempt a merge
  if [ "$mergeable" = "MERGEABLE" ] || [ "$mergeStateStatus" = "CLEAN" ] || [ "$mergeStateStatus" = "UNKNOWN" ]; then
    echo "Attempting to merge PR $PR now"
    # Try to merge (idempotent) — allow failure and continue polling
    if gh pr merge "$PR" --repo "$REPO" --merge -d || true; then
      echo "Merge command executed; check status next loop"
    fi
  fi
  sleep "$INTERVAL"
done
