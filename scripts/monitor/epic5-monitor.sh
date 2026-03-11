#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="logs/epic-5-monitor"
mkdir -p "$LOG_DIR"
OUT="$LOG_DIR/epic5-monitor.log"

echo "$(date -u +%FT%TZ) STARTING EPIC-5 MONITOR" >> "$OUT"
trap 'echo "$(date -u +%FT%TZ) STOPPING EPIC-5 MONITOR" >> "$OUT"; exit 0' SIGINT SIGTERM

while true; do
  ts=$(date -u +%FT%TZ)
  echo "$ts: checking epic-5 logs and health" >> "$OUT"

  # Tail EPIC-5 cloudflare logs for success/completion markers
  tail -n 200 logs/epic-5-cloudflare/cloudflare-setup-*.jsonl 2>/dev/null \
    | grep -i -E "complete|success" | tail -n 20 >> "$OUT" || true

  # Tail other EPIC-5 logs if present
  tail -n 200 logs/epic-5-*/epic-5-*.jsonl 2>/dev/null | grep -i -E "complete|success" | tail -n 20 >> "$OUT" || true

  # Optional HTTP health check if FRONTEND env provided
  if [ -n "${FRONTEND:-}" ]; then
    status=$(curl -sS -m 5 -o /dev/null -w "%{http_code}" "$FRONTEND" 2>/dev/null || echo "000")
    echo "$ts: FRONTEND HTTP $status" >> "$OUT"
  fi

  # Rotate log lightly
  if [ -f "$OUT" ] && [ $(stat -c%s "$OUT") -gt $((1024*200)) ]; then
    mv "$OUT" "$LOG_DIR/epic5-monitor-$(date -u +%FT%TZ).log" || true
    echo "$(date -u +%FT%TZ) rotated monitor log" > "$OUT"
  fi

  sleep 60
done
