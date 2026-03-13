#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG="$REPO_ROOT/logs/cutover/phase4.log"
PID_DIR="$REPO_ROOT/run"
PROM_URL="http://192.168.168.42:9090"
INTERVAL_SEC=60
MAX_MINUTES=1440
TARGET_UP=13
ERROR_RATE_THRESHOLD=0.001 # 0.1%

mkdir -p "$(dirname "$LOG")" "$PID_DIR"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Phase4 monitor started" >> "$LOG"

minutes=0
consecutive_ok=0
while [ $minutes -lt $MAX_MINUTES ]; do
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  up_count=$(curl -sG --max-time 10 --get --data-urlencode "query=count(up)" "$PROM_URL/api/v1/query" | jq -r '.data.result[0].value[1] // "0"') || up_count=0

  # try to compute error rate; tolerate missing metrics
  err_rate_json=$(curl -sG --max-time 10 --get --data-urlencode "query=(sum(rate(http_requests_total{status=~\"5..\"}[5m])) or vector(0)) / (sum(rate(http_requests_total[5m])) or vector(1))" "$PROM_URL/api/v1/query" ) || err_rate_json=''
  err_rate=$(echo "$err_rate_json" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0")

  echo "[$timestamp] up=$up_count err_rate=$err_rate" >> "$LOG"

  # check conditions
  ok=0
  if [ "${up_count:-0}" -ge $TARGET_UP ]; then
    # up count ok
    ok=$((ok+1))
  fi
  # compare error rate as float
  awk -v r="$err_rate" -v t="$ERROR_RATE_THRESHOLD" 'BEGIN {exit !(r+0 <= t)}'
  if [ $? -eq 0 ]; then
    ok=$((ok+1))
  fi

  if [ $ok -ge 2 ]; then
    consecutive_ok=$((consecutive_ok+1))
  else
    consecutive_ok=0
  fi

  # if we've seen sustained OK for a period (e.g., 60 checks ~ 1 hour), note it
  if [ $consecutive_ok -ge 60 ]; then
    echo "[$timestamp] Phase4: sustained healthy state observed (consecutive_ok=$consecutive_ok)" >> "$LOG"
  fi

  sleep $INTERVAL_SEC
  minutes=$((minutes + INTERVAL_SEC/60))
done

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Phase4 monitor finished (timeout)" >> "$LOG"
exit 0
