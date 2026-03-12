#!/usr/bin/env bash
# scripts/smoke_test.sh
# health & readiness checks for canary/production deployment

set -euo pipefail

CANARY_URL="${1:-http://localhost:8080}"
TIMEOUT=30
RETRIES=5
RETRY_DELAY=5

log() { echo "[SMOKE] $(date +'%H:%M:%S') $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

log "Starting smoke tests for: $CANARY_URL"

# Test 1: Health check endpoint
log "Test 1/5: Health check endpoint..."
for i in $(seq 1 $RETRIES); do
  if curl -sf \
    --max-time "$TIMEOUT" \
    --connect-timeout 5 \
    "${CANARY_URL}/health" &>/dev/null; then
    log "✅ Health check passed"
    break
  fi
  
  if [ "$i" -lt "$RETRIES" ]; then
    log "   Retry $i/$RETRIES in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
  else
    error "Health check failed after $RETRIES retries"
  fi
done

# Test 2: Readiness check endpoint
log "Test 2/5: Readiness check endpoint..."
if curl -sf --max-time "$TIMEOUT" --connect-timeout 5 "${CANARY_URL}/ready" &>/dev/null; then
  log "✅ Readiness check passed"
else
  error "Readiness check failed"
fi

# Test 3: API status endpoint
log "Test 3/5: API status endpoint..."
if curl -sf --max-time "$TIMEOUT" --connect-timeout 5 "${CANARY_URL}/api/v1/status" &>/dev/null; then
  log "✅ API status passed"
else
  error "API status check failed"
fi

# Test 4: Response time < 2s
log "Test 4/5: Response time SLA (< 2s)..."
response_time=$(curl -s --max-time "$TIMEOUT" --connect-timeout 5 -w '%{time_total}' -o /dev/null "${CANARY_URL}/health" 2>/dev/null || echo "999")
if (( $(echo "$response_time < 2.0" | bc -l 2>/dev/null || echo 0) )); then
  log "✅ Response time SLA passed (${response_time}s)"
else
  log "⚠️  Response time exceeded SLA: ${response_time}s (warning, not critical)"
fi

# Test 5: No error responses
log "Test 5/5: Error rate check..."
http_code=$(curl -s --max-time "$TIMEOUT" --connect-timeout 5 -o /dev/null -w '%{http_code}' "${CANARY_URL}/health" 2>/dev/null || echo "000")
if [[ "$http_code" =~ ^[2][0-9]{2}$ ]]; then
  log "✅ HTTP status code passed ($http_code)"
else
  error "HTTP error: $http_code (expected 2xx)"
fi

log ""
log "============================================"
log "✅ All smoke tests passed!"
log "============================================"
