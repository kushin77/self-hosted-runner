#!/bin/bash
# ===================================================================
# LEAD ENGINEER: Auto-detect and activate new deployer key versions
# ===================================================================
# Purpose: Automatically activates new deployer-sa-key versions added
#          by the project owner. Runs in background. Idempotent.
# ===================================================================

set -euo pipefail

PROJECT_ID="nexusshield-prod"
SECRET_NAME="deployer-sa-key"
STATE_FILE="/tmp/deployer-key-version-state.txt"
AUDIT_LOG="/tmp/deployer-key-rotator-audit-$(date +%Y%m%d-%H%M%S).jsonl"
POLL_INTERVAL=30  # poll every 30 seconds for new versions
MAX_ITERATIONS=720  # 6 hours of polling (720 * 30s)

log_audit() {
  local msg="$1"
  local level="${2:-INFO}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$level\",\"message\":\"$msg\"}" | tee -a "$AUDIT_LOG"
}

# Initialize state file if it doesn't exist
if [[ ! -f "$STATE_FILE" ]]; then
  log_audit "Initializing state file: $STATE_FILE" "INFO"
  # Get the current latest version
  CURRENT_VERSION=$(gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" \
    --format="value(name)" --limit=1 2>/dev/null || echo "unknown")
  echo "$CURRENT_VERSION" > "$STATE_FILE"
  log_audit "Current key version: $CURRENT_VERSION" "INFO"
fi

LAST_KNOWN_VERSION=$(cat "$STATE_FILE")
log_audit "Starting watcher. Last known version: $LAST_KNOWN_VERSION" "INFO"

# Poll for new versions
ITERATION=0
while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ((ITERATION++))
  
  # Get latest version
  LATEST_VERSION=$(gcloud secrets versions list "$SECRET_NAME" --project="$PROJECT_ID" \
    --format="value(name)" --limit=1 2>/dev/null || echo "unknown")
  
  if [[ "$LATEST_VERSION" != "$LAST_KNOWN_VERSION" && "$LATEST_VERSION" != "unknown" ]]; then
    log_audit "🆕 NEW VERSION DETECTED: $LATEST_VERSION (was: $LAST_KNOWN_VERSION)" "WARN"
    
    # Download the new key
    TEMP_KEY_FILE="/tmp/deployer-sa-key-auto-$(date +%s).json"
    if gcloud secrets versions access "$LATEST_VERSION" \
      --secret="$SECRET_NAME" --project="$PROJECT_ID" > "$TEMP_KEY_FILE" 2>&1; then
      
      log_audit "✅ New key downloaded" "INFO"
      
      # Activate it
      if gcloud auth activate-service-account --key-file="$TEMP_KEY_FILE" \
        --project="$PROJECT_ID" 2>&1 | tee -a "$AUDIT_LOG"; then
        
        log_audit "✅ NEW KEY ACTIVATED: $LATEST_VERSION" "WARN"
        
        # Verify access
        if gcloud projects describe "$PROJECT_ID" --format="value(projectId)" 2>&1 | tee -a "$AUDIT_LOG"; then
          log_audit "✅ New key verified (project access confirmed)" "INFO"
        fi
        
        # Update state
        echo "$LATEST_VERSION" > "$STATE_FILE"
        LAST_KNOWN_VERSION="$LATEST_VERSION"
        
        # Cleanup
        shred -vfz -n 3 "$TEMP_KEY_FILE" 2>&1 | tee -a "$AUDIT_LOG" || rm -f "$TEMP_KEY_FILE"
        log_audit "Cleanup: temp key destroyed" "INFO"
        
        # Signal orchestrator to restart services if needed
        if [[ -f /tmp/orchestrator-pid.txt ]]; then
          ORCH_PID=$(cat /tmp/orchestrator-pid.txt 2>/dev/null || echo "")
          if kill -0 "$ORCH_PID" 2>/dev/null; then
            log_audit "Sending SIGHUP to orchestrator (PID: $ORCH_PID) to restart services" "INFO"
            kill -HUP "$ORCH_PID" 2>/dev/null || true
          fi
        fi
      else
        log_audit "❌ Failed to activate new key" "ERROR"
        rm -f "$TEMP_KEY_FILE"
      fi
    else
      log_audit "❌ Failed to download new key version $LATEST_VERSION" "ERROR"
    fi
  fi
  
  # Sleep until next poll
  sleep "$POLL_INTERVAL"
done

log_audit "⏹️  Watcher stopped (max iterations reached)" "INFO"
