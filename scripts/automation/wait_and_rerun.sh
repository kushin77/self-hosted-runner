#!/usr/bin/env bash
# Idempotent watcher: find failed runs, attempt to rerun them, and summarize results
set -euo pipefail
REPO=${1:-kushin77/self-hosted-runner}
HOURS=${2:-24}
OUT_DIR=${3:-/tmp}
GH_TOKEN=${GH_TOKEN:-}
export GITHUB_TOKEN=${GH_TOKEN:-}

TS=$(date -u +%Y%m%dT%H%M%SZ)
FAILED_FILE="$OUT_DIR/failed_runs_${TS}.txt"

# Run monitor to populate failed list
scripts/automation/monitor_runs.sh "$REPO" "$HOURS" "$OUT_DIR" > /dev/null || true
# Use most recent failed file
LATEST=$(ls -1t $OUT_DIR/failed_runs_*.txt 2>/dev/null | head -n1 || true)
if [ -z "$LATEST" ]; then
  echo "No failed runs file produced; exiting"
  exit 0
fi

echo "Using failed runs file: $LATEST"

queued=0
failed=0
while read -r id; do
  [ -z "$id" ] && continue
  echo "Attempting to rerun run $id"
  if gh run rerun "$id" --repo "$REPO" 2>/tmp/rerun_${id}.err >/tmp/rerun_${id}.out; then
    echo "$id: queued" >> "$OUT_DIR/rerun_results_${TS}.txt"
    queued=$((queued+1))
  else
    echo "$id: failed-to-queue" >> "$OUT_DIR/rerun_results_${TS}.txt"
    failed=$((failed+1))
    echo "Error for $id:"; sed -n '1,120p' /tmp/rerun_${id}.err || true
  fi
done < "$LATEST"

echo "Rerun summary: queued=$queued failed_to_queue=$failed"
if [ $queued -gt 0 ]; then
  echo "Queued $queued runs for rerun. Monitoring will check artifacts on completion."
fi

# Post a short issue comment if secrets are missing or if nothing was queued
if [ $queued -eq 0 ]; then
  echo "No runs queued. If you expected reruns, ensure RUNNER_MGMT_TOKEN PAT with administration:read is configured as secret RUNNER_MGMT_TOKEN."
fi

exit 0
