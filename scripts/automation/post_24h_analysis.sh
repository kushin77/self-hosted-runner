#!/usr/bin/env bash
set -euo pipefail
# post_24h_analysis.sh - wait until 24h after first stabilization sample, then aggregate

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$ROOT/logs/stabilization-monitor"
PY="$ROOT/scripts/automation/aggregate_stabilization.py"

if [ ! -d "$LOG_DIR" ]; then
  echo "No stabilization logs directory: $LOG_DIR" >&2
  exit 1
fi

first_file=$(ls -1 "$LOG_DIR"/stabilization-*.jsonl 2>/dev/null | head -1 || true)
if [ -z "$first_file" ]; then
  echo "No stabilization sample files found; exiting" >&2
  exit 1
fi

# Extract timestamp from filename: stabilization-YYYYMMDDTHHMMSSZ.jsonl
fname=$(basename "$first_file")
ts=${fname#stabilization-}
ts=${ts%.jsonl}

# Parse into epoch
target_epoch=$(date -u -d "$ts" +%s 2>/dev/null || date -u -j -f "%Y%m%dT%H%M%SZ" "$ts" +%s)
target_epoch=$((target_epoch + 24*3600))
now_epoch=$(date -u +%s)
sleep_seconds=$((target_epoch - now_epoch))

if [ $sleep_seconds -le 0 ]; then
  echo "24h window already passed; running aggregation now"
else
  echo "Sleeping $sleep_seconds seconds until 24h window completes ($(date -u -d "@$target_epoch"))"
  sleep $sleep_seconds
fi

echo "Running aggregation..."
python3 "$PY"

# Commit generated report(s)
cd "$ROOT"
git add reports/FINAL_STABILITY_REPORT_*.md || true
if git diff --staged --quiet; then
  echo "No report changes to commit"
else
  git commit -m "Post-24h stability report: auto-generated" || true
fi

echo "Post-24h analysis complete"
