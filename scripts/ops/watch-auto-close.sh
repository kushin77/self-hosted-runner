#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLL_LOG="$REPO_ROOT/logs/cutover/poller.log"
OUT_LOG="$REPO_ROOT/logs/cutover/auto-close-watch.log"
PID_DIR="$REPO_ROOT/run"

mkdir -p "$(dirname "$OUT_LOG")" "$PID_DIR"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Auto-close watcher started" >> "$OUT_LOG"

tail -F "$POLL_LOG" | while read -r line; do
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $line" >> "$OUT_LOG"
  if echo "$line" | grep -q -E "DNS propagation observed|Closing Issue #1"; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Auto-close event detected: $line" >> "$OUT_LOG"
    # capture latest git commit for audit
    (cd "$REPO_ROOT" && git log -1 --pretty=format:'%h %ad %s' --date=iso) >> "$OUT_LOG" 2>/dev/null || true
    # touch a marker file for other automation
    touch "$REPO_ROOT/logs/cutover/auto-close.marker"
    exit 0
  fi
done
