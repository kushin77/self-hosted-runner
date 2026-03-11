#!/bin/bash
# ===================================================================
# LEAD ENGINEER: Auto-detect and activate new deployer key versions
# ===================================================================
# Purpose: Polls for new deployer-sa-key versions and activates them.
#          Runs in background. Idempotent. Returns immediately.
# ===================================================================

set -euo pipefail

PROJECT_ID="nexusshield-prod"
SECRET_NAME="deployer-sa-key"
STATE_FILE="/tmp/deployer-key-detector-state.txt"
AUDIT_LOG="/tmp/deployer-key-auto-activation-$(date +%Y%m%d-%H%M%S).jsonl"
POLL_INTERVAL=15  # Poll every 15 seconds
MAX_ITERATIONS=1440  # ~6 hours (1440 * 15s = 21600s)

log_audit() {
  local msg="$1"
  local level="${2:-INFO}"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "{\"ts\":\"$ts\",\"level\":\"$level\",\"msg\":\"$msg\"}" | tee -a "$AUDIT_LOG"
}

log_audit "Auto-detect key rotation script started (PID: $$)" "INFO"

# Initialize state: capture current version
if [[ ! -f "$STATE_FILE" ]]; then
  # Try to get current version; if we can't, that's OK
  CURRENT_VERSION=$(gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" \
    --format="value(name)" --limit=1 2>/dev/null || echo "")
  
  if [[ -z "$CURRENT_VERSION" ]]; then
    log_audit "Could not determine current key version (deployer may lack permissions). Will detect new versions when added." "WARN"
    CURRENT_VERSION="none"
  fi
  
  echo "$CURRENT_VERSION" > "$STATE_FILE"
  log_audit "Initial key version: $CURRENT_VERSION" "INFO"
fi

LAST_KNOWN_VERSION=$(cat "$STATE_FILE")
log_audit "Starting polling loop (interval: ${POLL_INTERVAL}s, max: ${MAX_ITERATIONS} iterations)" "INFO"

ITERATION=0
while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ((ITERATION++))
  
  # Try to get latest version (may fail if deployer lacks permissions)
  LATEST_VERSION=$(gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" \
    --format="value(name)" --limit=1 2>/dev/null || echo "")
  
  if [[ -z "$LATEST_VERSION" ]]; then
    # Permissions issue; try accessing as current user to see if owner has already set it
    LATEST_VERSION=$(gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" \
      --format="value(name)" --limit=1 2>&1 | grep -oP '(?<=created_at: ).*' || true)
  fi
  
  if [[ -n "$LATEST_VERSION" && "$LATEST_VERSION" != "$LAST_KNOWN_VERSION" && "$LATEST_VERSION" != "none" ]]; then
    log_audit "🆕 NEW VERSION DETECTED: $LATEST_VERSION (was: $LAST_KNOWN_VERSION)" "WARN"
    
    # Try to download and activate the new key
    TEMP_KEY="/tmp/deployer-auto-rotate-$(date +%s).json"
    
    if gcloud secrets versions access "$LATEST_VERSION" \
      --secret="$SECRET_NAME" --project="$PROJECT_ID" > "$TEMP_KEY" 2>&1; then
      
      log_audit "New key downloaded" "INFO"
      
      # Activate it
      if gcloud auth activate-service-account --key-file="$TEMP_KEY" --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
        log_audit "✅ NEW KEY ACTIVATED: $LATEST_VERSION" "WARN"
        
        # Update state
        echo "$LATEST_VERSION" > "$STATE_FILE"
        LAST_KNOWN_VERSION="$LATEST_VERSION"
        
        # Cleanup
        shred -vfz -n 3 "$TEMP_KEY" 2>&1 | tee -a "$AUDIT_LOG" || rm -f "$TEMP_KEY"
        log_audit "Temporary key securely deleted" "INFO"
        
        # Signal any orchestrator processes to restart
        if [[ -f /tmp/orchestrator-pid.txt ]]; then
          ORCH_PID=$(cat /tmp/orchestrator-pid.txt 2>/dev/null || echo "")
          if [[ -n "$ORCH_PID" ]] && kill -0 "$ORCH_PID" 2>/dev/null; then
            log_audit "Signaling orchestrator (PID: $ORCH_PID) to restart services" "INFO"
            kill -HUP "$ORCH_PID" 2>/dev/null || true
          fi
        fi
      else
        log_audit "❌ Failed to activate new key" "ERROR"
        rm -f "$TEMP_KEY"
      fi
    else
      log_audit "❌ Failed to download new key version: $LATEST_VERSION" "ERROR"
    fi
  fi
  
  sleep "$POLL_INTERVAL"
done

log_audit "⏹️  Max iterations reached. Exiting." "INFO"
