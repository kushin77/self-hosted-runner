#!/bin/bash

# Updated NAS Worker Node Sync - eiq-nas Integration
# Pulls IAC from eiq-nas GitHub repository instead of direct NAS SSH
# 
# Uses: git clone/pull from github.com:kushin77/eiq-nas.git
# Auth: svc-git service account with SSH key from GSM
# Schedule: Every 30 minutes (via systemd timer)
# 
# Compliance: Immutable, ephemeral, idempotent, hands-off, GSM vault, no GitHub Actions

set -euo pipefail

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/nas-integration"
AUDIT_LOG="${LOG_DIR}/worker-sync-audit.jsonl"
SYNC_STATE="/var/lib/automation/nas-sync-state.json"

# Configuration
NAS_GIT_REPO="${NAS_GIT_REPO:-git@github.com:kushin77/eiq-nas.git}"
NAS_LOCAL_PATH="${NAS_LOCAL_PATH:-/home/automation/eiq-nas-local}"
NAS_HOST="${NAS_HOST:-192.168.168.100}"
SSH_IDENTITY="${SSH_IDENTITY:-/home/svc-git/.ssh/id_ed25519}"
AUTOMATION_USER="${AUTOMATION_USER:-automation}"

# Ensure log directories exist
mkdir -p "$LOG_DIR"
touch "$AUDIT_LOG"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

log() {
  echo "[${TIMESTAMP}] $*" >> "$AUDIT_LOG"
  echo -e "${GREEN}[✓]${NC} $*" >&2
}

error() {
  echo "[${TIMESTAMP}] ERROR: $*" >> "$AUDIT_LOG"
  echo -e "${RED}[✗]${NC} ERROR: $*" >&2
}

audit_entry() {
  local action="$1"
  local status="$2"
  local details="${3:-}"
  
  jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg action "$action" \
    --arg status "$status" \
    --arg details "$details" \
    --arg host "$NAS_HOST" \
    '{timestamp: $timestamp, action: $action, status: $status, host: $host, details: $details}' \
    >> "$AUDIT_LOG"
}

verify_ssh_access() {
  # Check SSH key accessibility via GSM (done by svc-git-key.service at boot)
  if [ ! -f "$SSH_IDENTITY" ]; then
    error "SSH identity not found: $SSH_IDENTITY"
    audit_entry "ssh_verify" "FAILED" "SSH key not accessible"
    return 1
  fi
  
  log "SSH identity verified: $SSH_IDENTITY"
  audit_entry "ssh_verify" "SUCCESS" "SSH key accessible"
  return 0
}

clone_or_update_nas() {
  # Clone eiq-nas or update existing
  if [ ! -d "$NAS_LOCAL_PATH/.git" ]; then
    log "Cloning eiq-nas repository..."
    
    if ! git clone "$NAS_GIT_REPO" "$NAS_LOCAL_PATH" 2>&1 | tee -a "$LOG_DIR/clone.log"; then
      error "Failed to clone eiq-nas"
      audit_entry "git_clone" "FAILED" "Clone from $NAS_GIT_REPO failed"
      return 1
    fi
    
    log "eiq-nas cloned successfully"
    audit_entry "git_clone" "SUCCESS" "Repository cloned"
  else
    log "Updating eiq-nas repository..."
    
    if ! git -C "$NAS_LOCAL_PATH" pull origin main 2>&1 | tee -a "$LOG_DIR/pull.log"; then
      error "Failed to pull eiq-nas"
      audit_entry "git_pull" "FAILED" "Pull from $NAS_GIT_REPO failed"
      return 1
    fi
    
    log "eiq-nas updated successfully"
    audit_entry "git_pull" "SUCCESS" "Repository updated"
  fi
  
  return 0
}

sync_to_worker_deployment() {
  # Sync eiq-nas content to worker deployment directory
  local deployment_target="/home/automation/nas-config/latest"
  
  mkdir -p "$deployment_target"
  
  log "Syncing eiq-nas to deployment directory..."
  
  if ! rsync -av --delete "$NAS_LOCAL_PATH/" "$deployment_target/" 2>&1 | tee -a "$LOG_DIR/rsync.log"; then
    error "Failed to sync to deployment directory"
    audit_entry "local_sync" "FAILED" "rsync to $deployment_target failed"
    return 1
  fi
  
  log "Deployment sync completed"
  audit_entry "local_sync" "SUCCESS" "Files synced to deployment directory"
  return 0
}

validate_sync() {
  # Verify sync integrity
  local source_count
  local target_count
  
  source_count=$(find "$NAS_LOCAL_PATH" -type f | wc -l)
  target_count=$(find "/home/automation/nas-config/latest" -type f | wc -l)
  
  if [ "$source_count" -eq "$target_count" ]; then
    log "Sync validation: $source_count files verified"
    audit_entry "validation" "SUCCESS" "File count: $source_count"
    return 0
  else
    error "Sync validation failed: source=$source_count, target=$target_count"
    audit_entry "validation" "FAILURE" "File count mismatch: $source_count vs $target_count"
    return 1
  fi
}

update_sync_state() {
  # Store sync state for monitoring/alerting
  local last_commit
  local files_synced
  local status="$1"
  
  last_commit=$(git -C "$NAS_LOCAL_PATH" rev-parse HEAD 2>/dev/null || echo "unknown")
  files_synced=$(find "$NAS_LOCAL_PATH" -type f | wc -l)
  
  jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg status "$status" \
    --arg last_commit "$last_commit" \
    --arg files_synced "$files_synced" \
    --arg repo "$NAS_GIT_REPO" \
    '{
      timestamp: $timestamp,
      status: $status,
      last_commit: $last_commit,
      files_synced: ($files_synced | tonumber),
      repository: $repo
    }' > "$SYNC_STATE"
  
  log "Sync state updated: status=$status, commit=$last_commit, files=$files_synced"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║          Worker Node NAS Sync - eiq-nas Integration                      ║"
echo "║                     $(date '+%Y-%m-%d %H:%M:%S UTC')                              ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Initialize audit entry
audit_entry "sync_cycle_start" "INITIATED" "Sync cycle initiated on worker node"

# Phase 1: Verify SSH access
if ! verify_ssh_access; then
  error "SSH access verification failed"
  update_sync_state "FAILED"
  exit 1
fi

# Phase 2: Clone or update repository
if ! clone_or_update_nas; then
  error "Repository clone/update failed"
  update_sync_state "FAILED"
  exit 1
fi

# Phase 3: Sync to deployment directory
if ! sync_to_worker_deployment; then
  error "Deployment sync failed"
  update_sync_state "FAILED"
  exit 1
fi

# Phase 4: Validate sync
if ! validate_sync; then
  error "Sync validation failed"
  update_sync_state "FAILED"
  exit 1
fi

# Success
echo ""
echo -e "${GREEN}✅ NAS sync completed successfully${NC}"
echo "   Timestamp: $TIMESTAMP"
echo "   Repository: $NAS_GIT_REPO"
echo "   Local Path: $NAS_LOCAL_PATH"
echo "   Last Commit: $(git -C "$NAS_LOCAL_PATH" rev-parse HEAD)"
echo "   Files: $(find "$NAS_LOCAL_PATH" -type f | wc -l)"
echo ""

update_sync_state "SUCCESS"
audit_entry "sync_cycle_complete" "SUCCESS" "Sync cycle completed successfully"

exit 0
