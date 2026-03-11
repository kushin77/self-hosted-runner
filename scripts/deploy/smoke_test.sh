#!/usr/bin/env bash
set -euo pipefail

# Basic smoke test runner for frontend/backend
# Usage: smoke_test.sh --backend-url <url> --frontend-url <url> --retries 5 --sleep 3

BACKEND_URL=""
FRONTEND_URL=""
RETRIES=5
SLEEP=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend-url) BACKEND_URL="$2"; shift 2;;
    --frontend-url) FRONTEND_URL="$2"; shift 2;;
    --retries) RETRIES="$2"; shift 2;;
    --sleep) SLEEP="$2"; shift 2;;
    *) echo "Unknown arg $1"; exit 2;;
  esac
done

log(){ echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }

if [[ -z "$BACKEND_URL" && -z "$FRONTEND_URL" ]]; then
  echo "Need at least one of --backend-url or --frontend-url" >&2
  exit 2
fi

failed=0

for i in $(seq 1 $RETRIES); do
  log "Smoke attempt $i/$RETRIES"
  ok=true

  if [[ -n "$BACKEND_URL" ]]; then
    if curl -sSf "$BACKEND_URL/health" -m 5 >/dev/null 2>&1; then
      log "backend health OK"
    else
      log "backend health FAIL"
      ok=false
    fi
  fi

  if [[ -n "$FRONTEND_URL" ]]; then
    if curl -sSf "$FRONTEND_URL" -m 5 >/dev/null 2>&1; then
      log "frontend OK"
    else
      log "frontend FAIL"
      ok=false
    fi
  fi

  if $ok; then
    log "Smoke tests passed"
    exit 0
  fi

  sleep "$SLEEP"
done

log "Smoke tests failed after $RETRIES attempts"
exit 1
