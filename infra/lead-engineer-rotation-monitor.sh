#!/bin/bash
# ===================================================================
# LEAD ENGINEER: Simple key rotation status monitor (no permission issues)
# ===================================================================
# Purpose: Monitors deployment status and waits for owner to complete
#          key rotation. Non-blocking, idempotent, runs indefinitely.
# ===================================================================

set -u

PROJECT_ID="nexusshield-prod"
SERVICE_NAME="prevent-releases"
AUDIT_LOG="/tmp/lead-engineer-rotation-monitor-$(date +%Y%m%d-%H%M%S).jsonl"
POLL_INTERVAL=30

log() {
  local msg="$1"
  local level="${2:-INFO}"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "{\"ts\":\"$ts\",\"level\":\"$level\",\"msg\":\"$msg\"}" | tee -a "$AUDIT_LOG"
}

log "Lead engineer rotation monitor started (PID: $$)" "INFO"
log "Project: $PROJECT_ID | Service: $SERVICE_NAME" "INFO"
log "Polling interval: ${POLL_INTERVAL}s" "INFO"
log "Audit log: $AUDIT_LOG" "INFO"

# Initial status check
log "Initial status check..." "INFO"
if gcloud run services describe "$SERVICE_NAME" --project="$PROJECT_ID" --region=us-central1 \
  --format="value(status.url)" &>/dev/null; then
  SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --project="$PROJECT_ID" --region=us-central1 \
    --format="value(status.url)" 2>/dev/null || echo "")
  log "✅ Service is live: $SERVICE_URL" "INFO"
else
  log "⚠️ Service status check failed (may need authentication)" "WARN"
fi

# Monitor loop
ITERATION=0
MAX_ITERATIONS=720  # ~6 hours at 30s interval

log "Starting monitoring loop..." "INFO"

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ((ITERATION++))
  
  # Simple health check: can we reach the service?
  if [[ -n "${SERVICE_URL:-}" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health" 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
      log "✅ Service health: 200 OK" "INFO"
    elif [[ "$HTTP_CODE" == "000" ]]; then
      log "⏳ Service health: unreachable (may be cold start)" "WARN"
    else
      log "⚠️ Service health: HTTP $HTTP_CODE" "WARN"
    fi
  fi
  
  # Check if owner has run the rotation script (marker file)
  if [[ -f /tmp/owner-complete-rotation.marker ]]; then
    log "🔔 OWNER MARKER DETECTED: Key rotation likely completed by owner" "WARN"
    log "Lead engineer should verify new key version in Secret Manager" "INFO"
    log "Instruction: run 'gcloud secrets versions list deployer-sa-key --project=$PROJECT_ID'" "INFO"
  fi
  
  # Poll for status updates
  sleep "$POLL_INTERVAL"
done

log "⏹️  Monitor reached max iterations (6 hours). Exiting gracefully." "INFO"
