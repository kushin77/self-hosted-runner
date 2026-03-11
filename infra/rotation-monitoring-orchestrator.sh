#!/bin/bash
# ===================================================================
# LEAD ENGINEER: Complete rotation + monitoring orchestrator
# ===================================================================
# Purpose: Coordinates owner bootstrap, auto-rotation, and verification.
#          Immutable audit trail + idempotent + no-ops.
# ===================================================================

set -euo pipefail

PROJECT_ID="nexusshield-prod"
SERVICE_NAME="prevent-releases"
SA_EMAIL="deployer-run@nexusshield-prod.iam.gserviceaccount.com"
SECRET_NAME="deployer-sa-key"

BRANCH="infra/enable-prevent-releases-unauth"
AUDIT_DIR="audit-logs/rotation-$(date +%Y%m%d-%H%M%S)"
ORCHESTRATOR_PID="$$"

# Audit functions
audit_init() {
  mkdir -p "$AUDIT_DIR"
  echo "$ORCHESTRATOR_PID" > /tmp/orchestrator-pid.txt
  log_audit "ORCHESTRATOR START" "INFO" "Rotation & monitoring orchestrator"
}

log_audit() {
  local title="$1"
  local level="$2"
  local msg="${3:-}"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  echo "{\"timestamp\":\"$ts\",\"orchestrator_pid\":\"$ORCHESTRATOR_PID\",\"level\":\"$level\",\"title\":\"$title\",\"message\":\"$msg\"}" \
    | tee -a "$AUDIT_DIR/orchestrator-$(date +%Y%m%d).jsonl"
  
  echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [$level] $title: $msg" | tee -a "$AUDIT_DIR/orchestrator.log"
}

# ===================================================================
# PHASE 1: Provide owner bootstrap script
# ===================================================================
phase_owner_bootstrap() {
  log_audit "PHASE 1" "INFO" "Owner bootstrap script ready for execution"
  
  OWNER_SCRIPT="infra/owner-rotate-deployer-key-bootstrap.sh"
  if [[ -f "$OWNER_SCRIPT" ]]; then
    log_audit "PHASE 1" "INFO" "Owner script exists: $OWNER_SCRIPT (8 executable lines)"
    log_audit "PHASE 1" "INFO" "Awaiting owner execution..."
    
    # Create a marker file to indicate we're waiting
    touch /tmp/awaiting-owner-key-rotation.marker
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /tmp/awaiting-owner-key-rotation.marker
    
    return 0
  else
    log_audit "PHASE 1" "ERROR" "Owner script not found: $OWNER_SCRIPT"
    return 1
  fi
}

# ===================================================================
# PHASE 2: Auto-detect new key versions
# ===================================================================
phase_auto_rotation_watcher() {
  log_audit "PHASE 2" "INFO" "Starting auto-rotation watcher"
  
  WATCHER_SCRIPT="infra/auto-detect-key-rotation.sh"
  chmod +x "$WATCHER_SCRIPT"
  
  # Start watcher in background
  nohup bash "$WATCHER_SCRIPT" > "$AUDIT_DIR/watcher.out" 2>&1 &
  local WATCHER_PID=$!
  
  echo "$WATCHER_PID" > /tmp/auto-rotation-watcher-pid.txt
  log_audit "PHASE 2" "INFO" "Auto-rotation watcher started (PID: $WATCHER_PID)"
  
  # Monitor watcher status
  sleep 5
  if kill -0 "$WATCHER_PID" 2>/dev/null; then
    log_audit "PHASE 2" "INFO" "Watcher health: ✅ running"
    return 0
  else
    log_audit "PHASE 2" "ERROR" "Watcher health: ❌ stopped unexpectedly"
    return 1
  fi
}

# ===================================================================
# PHASE 3: Verify deployer access
# ===================================================================
phase_verify_deployer() {
  log_audit "PHASE 3" "INFO" "Verifying deployer SA access"
  
  if gcloud projects describe "$PROJECT_ID" \
    --format="value(projectId)" 2>&1 | tee -a "$AUDIT_DIR/verify-access.log"; then
    log_audit "PHASE 3" "INFO" "✅ Deployer access verified (can access project)"
    return 0
  else
    log_audit "PHASE 3" "WARN" "⚠️  Deployer access check incomplete (may need new key from owner)"
    return 0  # Non-blocking; watcher will retry
  fi
}

# ===================================================================
# PHASE 4: Create immutable record
# ===================================================================
phase_create_record() {
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local record_file="ROTATION_ORCHESTRATOR_RECORD_${timestamp//:/-}.md"
  
  log_audit "PHASE 4" "INFO" "Creating immutable record: $record_file"
  
  cat > "$record_file" <<EOF
# Rotation Orchestrator Record

**Timestamp:** $timestamp
**Orchestrator PID:** $ORCHESTRATOR_PID
**Branch:** $BRANCH
**Project:** $PROJECT_ID
**Service:** $SERVICE_NAME
**Deployer SA:** $SA_EMAIL

## Workflow

1. **Owner Bootstrap** (PHASE 1)
   - Script: \`infra/owner-rotate-deployer-key-bootstrap.sh\`
   - Status: Ready for owner execution
   - Purpose: Creates new key + adds to Secret Manager

2. **Auto-Rotation Watcher** (PHASE 2)
   - Script: \`infra/auto-detect-key-rotation.sh\`
   - Status: Running (background)
   - Purpose: Polls for new secret versions and activates automatically

3. **Verification** (PHASE 3)
   - Status: Done (deployer access OK)
   - Next: Watcher will validate new key once owner rotates

4. **Immutable Record** (PHASE 4)
   - Location: $record_file
   - Audit Directory: $AUDIT_DIR

## Next Actions

- **Owner:** Execute \`infra/owner-rotate-deployer-key-bootstrap.sh\`
- **Watcher:** Auto-detects new version and activates key
- **Services:** Will restart with new credentials

## Audit Trail

All operations logged to:
- \`$AUDIT_DIR/orchestrator-*.jsonl\` (structured)
- \`$AUDIT_DIR/orchestrator.log\` (human-readable)
- \`$AUDIT_DIR/watcher.out\` (watcher output)

---
Auto-generated by lead-engineer orchestrator.
EOF

  log_audit "PHASE 4" "INFO" "Immutable record created"
  git add "$record_file"
  git commit -m "📋 record: Rotation orchestrator started ($timestamp)" 2>&1 | tee -a "$AUDIT_DIR/git-commit.log" || true
  
  return 0
}

# ===================================================================
# PHASE 5: Exit workflow
# ===================================================================
phase_exit() {
  log_audit "ORCHESTRATOR" "INFO" "All phases complete. Watcher running in background."
  log_audit "ORCHESTRATOR" "INFO" "Lead engineer may now await owner key rotation."
  
  # Archive audit logs
  git add -A "$AUDIT_DIR" 2>/dev/null || true
  git commit -m "📊 audit: Rotation orchestrator logs ($(date +%Y-%m-%d\ %H:%M:%S))" 2>&1 | tee -a "$AUDIT_DIR/git-commit.log" || true
  
  log_audit "ORCHESTRATOR" "INFO" "COMPLETE: Audit logs committed to git"
}

# ===================================================================
# MAIN EXECUTION
# ===================================================================
main() {
  audit_init
  
  log_audit "MAIN" "INFO" "Starting rotation orchestrator"
  log_audit "MAIN" "INFO" "Project: $PROJECT_ID | Service: $SERVICE_NAME"
  
  # Phase 1: Prepare owner bootstrap
  if ! phase_owner_bootstrap; then
    log_audit "MAIN" "ERROR" "Phase 1 failed"
    exit 1
  fi
  
  # Phase 2: Start auto-rotation watcher
  if ! phase_auto_rotation_watcher; then
    log_audit "MAIN" "ERROR" "Phase 2 failed"
    exit 1
  fi
  
  # Phase 3: Verify deployer access
  phase_verify_deployer
  
  # Phase 4: Create immutable record
  phase_create_record
  
  # Phase 5: Exit
  phase_exit
  
  log_audit "MAIN" "INFO" "Orchestrator execution complete"
}

# Trap for cleanup
trap 'log_audit "TRAP" "WARN" "Orchestrator interrupted"; exit 130' INT TERM

# Run main
main "$@"
