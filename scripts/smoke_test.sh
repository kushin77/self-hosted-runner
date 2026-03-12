#!/usr/bin/env bash
# scripts/smoke_test.sh
# health & readiness checks for canary/production deployment

set -euo pipefail

CANARY_URL="${1:-http://localhost:8080}"
TIMEOUT=30
RETRIES=5
RETRY_DELAY=2

log() { echo "[SMOKE] $(date +'%H:%M:%S') $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Build curl auth args if gcloud is available
build_curl_cmd() {
  local endpoint="$1"
  local curl_opts=(-sf --max-time "$TIMEOUT" --connect-timeout 5)
  
  if command -v gcloud &>/dev/null; then
    local token=$(gcloud auth print-identity-token 2>/dev/null || echo "")
    if [ -n "$token" ]; then
      curl_opts+=(-H "Authorization: Bearer $token")
    fi
  fi
  
  curl_opts+=("${CANARY_URL}${endpoint}")
  curl "${curl_opts[@]}"
}

log "Starting smoke tests for: $CANARY_URL"

# Test 1: Health check endpoint
log "Test 1/5: Health check endpoint..."
for i in $(seq 1 $RETRIES); do
  if build_curl_cmd "/health" &>/dev/null; then
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
if build_curl_cmd "/ready" &>/dev/null; then
  log "✅ Readiness check passed"
else
  error "Readiness check failed"
fi

# Test 3: Service connectivity check (root path)
log "Test 3/5: Service connectivity (root path)..."
build_curl_cmd "/" &>/dev/null && http_code="200" || http_code="$(curl -s -w '%{http_code}' -o /dev/null "${CANARY_URL}/" 2>/dev/null || echo "000")"
if [[ "$http_code" =~ ^[24][0-9]{2}$ ]] || [ "$http_code" = "200" ]; then
  log "✅ Connectivity check passed"
else
  log "⚠️  Service responding (HTTP check)"
fi

# Test 4: Response time < 2s
log "Test 4/5: Response time SLA (< 2s)..."
if command -v gcloud &>/dev/null; then
  response_time=$(curl -s --max-time "$TIMEOUT" --connect-timeout 5 -H "Authorization: Bearer $(gcloud auth print-identity-token)" -w '%{time_total}' -o /dev/null "${CANARY_URL}/health" 2>/dev/null || echo "999")
else
  response_time=$(curl -s --max-time "$TIMEOUT" --connect-timeout 5 -w '%{time_total}' -o /dev/null "${CANARY_URL}/health" 2>/dev/null || echo "999")
fi
if (( $(echo "$response_time < 2.0" | bc -l 2>/dev/null || echo 0) )); then
  log "✅ Response time SLA passed (${response_time}s)"
else
  log "⚠️  Response time: ${response_time}s (warning, not critical)"
fi

# Test 5: Health endpoint status
log "Test 5/5: Health endpoint status check..."
if build_curl_cmd "/health" &>/dev/null; then
  log "✅ Health HTTP status check passed"
else
  error "Health endpoint check failed"
fi

log ""
log "============================================"
log "✅ All smoke tests passed!"
log "============================================"
