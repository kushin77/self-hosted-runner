#!/usr/bin/env bash
# Monitor recent failed runs and list their IDs
set -euo pipefail
REPO=${1:-kushin77/self-hosted-runner}
HOURS=${2:-24}
OUT_DIR=${3:-/tmp}
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$OUT_DIR/failed_runs_${TS}.txt"
: > "$OUT"

# Fetch workflow runs (first 200)
runs_json=$(gh api -X GET "/repos/${REPO}/actions/runs?per_page=200" || true)
if [ -z "$runs_json" ]; then
  echo "Failed to fetch runs or no data returned"
  exit 0
fi

# Parse for failures in last $HOURS hours
cutoff=$(date -u -d "${HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ)

echo "$runs_json" | jq -r --arg cutoff "$cutoff" '.workflow_runs[] | select(.conclusion=="failure") | select(.created_at >= $cutoff) | .id' | sort -u > "$OUT"

count=$(wc -l < "$OUT" | tr -d ' ')
if [ "$count" -eq 0 ]; then
  echo "No failed runs in the last ${HOURS}h"
else
  echo "Found $count failed run(s) in last ${HOURS}h. List:"
  cat "$OUT"
fi

echo "$OUT"
