#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/logs/stabilization-monitor"
mkdir -p "$OUT_DIR"

TIMESTAMP_FN() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log_summary() {
  local ts=$(TIMESTAMP_FN)
  # Count events per epic
  local e2=$(grep -c "\"phase\":\"epic2" "$REPO_ROOT/logs/epic-2-migration"/*.jsonl 2>/dev/null || true)
  local e3=$(grep -c "\"phase\":\"epic3" "$REPO_ROOT/logs/epic-3-aws-migration"/*.jsonl 2>/dev/null || true)
  local e4=$(grep -c "\"phase\":\"epic4" "$REPO_ROOT/logs/epic-4-azure-migration"/*.jsonl 2>/dev/null || true)
  local e5=$(grep -c "\"phase\":\"epic5" "$REPO_ROOT/logs/epic-5-cloudflare"/*.jsonl 2>/dev/null || true)

  # Detect any failure keywords in recent logs (last 100 lines)
  local failures=0
  failures=$((failures + $(tail -n 100 "$REPO_ROOT/logs/epic-2-migration"/*.jsonl 2>/dev/null | grep -c '"status":"failure"' || true)))
  failures=$((failures + $(tail -n 100 "$REPO_ROOT/logs/epic-3-aws-migration"/*.jsonl 2>/dev/null | grep -c '"status":"failure"' || true)))
  failures=$((failures + $(tail -n 100 "$REPO_ROOT/logs/epic-4-azure-migration"/*.jsonl 2>/dev/null | grep -c '"status":"failure"' || true)))
  failures=$((failures + $(tail -n 100 "$REPO_ROOT/logs/epic-5-cloudflare"/*.jsonl 2>/dev/null | grep -c '"status":"failure"' || true)))

  local summary="{\"timestamp\":\"${ts}\",\"epic2_events\":${e2},\"epic3_events\":${e3},\"epic4_events\":${e4},\"epic5_events\":${e5},\"recent_failures\":${failures}}"
  echo "$summary" >> "$OUT_DIR/stabilization-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
}

echo "Starting local stabilization monitor (writes to $OUT_DIR). Ctrl-C to stop." >&2

# Run until killed; sleep interval 300s (~5min). Will perform 288 iterations (~24 hours) if uninterrupted.
for i in $(seq 1 288); do
  log_summary
  sleep 300
done

echo "Local stabilization monitor completed 24h run." >&2
