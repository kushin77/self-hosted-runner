#!/usr/bin/env bash
set -euo pipefail

# Watcher for post_24h_analysis.sh
# - waits until the runner wakes (parses sleep seconds from /tmp/post24h.log)
# - after wake, monitors for report generation and posts a GitHub comment via repo CLI

LOG="/tmp/post24h.log"
REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/reports"
ISSUE_NUM=${ISSUE_NUM:-2479}
REPO_OWNER=${REPO_OWNER:-kushin77}
REPO_NAME=${REPO_NAME:-self-hosted-runner}

sleep_and_wait() {
  if [ ! -f "$LOG" ]; then
    echo "[watcher] log $LOG not found; waiting 60s"
    sleep 60
    return 1
  fi
  # parse Sleeping N seconds
  local line
  line=$(grep -m1 "Sleeping [0-9]\+ seconds" "$LOG" || true)
  if [ -z "$line" ]; then
    echo "[watcher] no sleeping line yet; tailing log until present"
    # wait for pattern
    while ! grep -m1 "Sleeping [0-9]\+ seconds" "$LOG" >/dev/null 2>&1; do
      sleep 10
    done
    line=$(grep -m1 "Sleeping [0-9]\+ seconds" "$LOG" || true)
  fi
  local secs
  secs=$(echo "$line" | sed -n 's/.*Sleeping \([0-9]\+\) seconds.*/\1/p')
  if [ -z "$secs" ]; then
    echo "[watcher] could not parse sleep seconds; exiting"
    return 2
  fi
  echo "[watcher] sleeping for $secs seconds (+30s buffer)"
  sleep $((secs + 30))
  return 0
}

notify_issue() {
  local msg="$1"
  # Try using gh if available, else echo
  if command -v gh >/dev/null 2>&1; then
    gh issue comment "$ISSUE_NUM" -R "$REPO_OWNER/$REPO_NAME" -b "$msg" || true
  else
    echo "[watcher] would post to issue #$ISSUE_NUM: $msg"
  fi
}

main() {
  echo "[watcher] started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  notify_issue "Post-24h watcher started on runner; will notify this issue when aggregation completes."

  if ! sleep_and_wait; then
    echo "[watcher] initial wait failed; exiting"
    exit 1
  fi

  echo "[watcher] wakeup window passed; monitoring reports dir for new FINAL_STABILITY_REPORT_*.md"

  # wait up to 30 minutes for report generation
  local deadline=$(( $(date +%s) + 1800 ))
  while [ $(date +%s) -lt $deadline ]; do
    latest=$(ls -1t "$REPORT_DIR"/FINAL_STABILITY_REPORT_*.md 2>/dev/null | head -1 || true)
    if [ -n "$latest" ]; then
      echo "[watcher] found report: $latest"
      notify_issue "Post-24h aggregation completed. Final stability report generated: $(basename "$latest"). See commit history for immutable record."
      exit 0
    fi
    # also watch log for 'Wrote' output
    if grep -m1 "Wrote /" "$LOG" >/dev/null 2>&1; then
      echo "[watcher] aggregator wrote report (detected in log)"
      notify_issue "Post-24h aggregation completed (detected in runner log). Check reports folder for final report."
      exit 0
    fi
    sleep 10
  done

  echo "[watcher] timeout waiting for report; notifying issue"
  notify_issue "Post-24h aggregation did not produce a final report within 30 minutes of wakeup. Please investigate."
  exit 2
}

main "$@"
