#!/bin/bash

# Updated NAS Dev Node Push - eiq-nas Integration
# Pushes IAC updates to eiq-nas GitHub repository via elevatediq-svc-git service account
#
# Uses: git push to github.com:kushin77/eiq-nas.git
# Auth: elevatediq-svc-git service account with SSH key from GSM
# Modes: push (one-time), watch (continuous), diff (preview)
#
# Compliance: Immutable, ephemeral, idempotent, hands-off, GSM vault, no GitHub Actions

set -euo pipefail

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/nas-integration"
AUDIT_LOG="${LOG_DIR}/dev-push-audit.jsonl"

# Configuration
NAS_GIT_REPO="${NAS_GIT_REPO:-git@github.com:kushin77/eiq-nas.git}"
NAS_REPO_PATH="${NAS_REPO_PATH:-/home/kushin77}"
PUSH_USER="elevatediq-svc-git"
GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
GSM_SECRET="${GSM_SECRET:-elevatediq-svc-git-ssh-key}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Mode (default: push, or 'watch' or 'diff')
MODE="${1:-push}"

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

warn() {
  echo -e "${YELLOW}[!]${NC} $*" >&2
}

info() {
  echo -e "${BLUE}[ℹ]${NC} $*" >&2
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
    --arg repo "$NAS_GIT_REPO" \
    '{timestamp: $timestamp, action: $action, status: $status, repository: $repo, details: $details}' \
    >> "$AUDIT_LOG"
}

verify_svc_git() {
  # Verify elevatediq-svc-git user and SSH access
  if ! id "$PUSH_USER" >/dev/null 2>&1; then
    error "elevatediq-svc-git user not found"
    audit_entry "svc_git_verify" "FAILED" "User not found"
    return 1
  fi
  
  # Check if SSH key is accessible (should be fetched by elevatediq-svc-git-key.service)
  if ! sudo -u "$PUSH_USER" -H ssh -T git@github.com >/dev/null 2>&1; then
    if ! sudo -u "$PUSH_USER" -H ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
      warn "GitHub SSH auth check returned warning (may be normal)"
    fi
  fi
  
  log "elevatediq-svc-git user verified"
  audit_entry "svc_git_verify" "SUCCESS" "User accessible"
  return 0
}

check_git_status() {
  # Show current git status
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Git Repository Status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" status
  
  echo ""
  echo "Recent Commits:"
  sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" log --oneline -5
  echo ""
}

check_diff() {
  # Show changes to be pushed
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Pending Changes"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local uncommitted
  uncommitted=$(sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" status --porcelain | wc -l)
  
  if [ "$uncommitted" -gt 0 ]; then
    echo "Uncommitted changes: $uncommitted"
    sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" status --porcelain
  else
    echo "No uncommitted changes"
  fi
  
  local untracked
  untracked=$(sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" ls-files --others --exclude-standard | wc -l)
  
  if [ "$untracked" -gt 0 ]; then
    echo ""
    echo "Untracked files: $untracked"
    sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" ls-files --others --exclude-standard | head -10
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Diff (HEAD vs origin/main):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" diff origin/main
  
  echo ""
}

push_to_eiqnas() {
  # Push changes to eiq-nas
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Pushing to eiq-nas"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  log "Starting push to $NAS_GIT_REPO"
  audit_entry "push_start" "INITIATED" "Push cycle started"
  
  # Fetch to ensure we have latest
  if ! sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" fetch origin main 2>&1 | tee -a "$LOG_DIR/push.log"; then
    error "Fetch failed"
    audit_entry "push_fetch" "FAILED" "Fetch from origin failed"
    return 1
  fi
  
  log "Fetch successful"
  
  # Check for uncommitted changes
  if sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" diff-index --quiet HEAD --; then
    info "No uncommitted changes"
  else
    warn "Uncommitted changes detected - commit before pushing"
  fi
  
  # Push to remote
  if sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" push origin main 2>&1 | tee -a "$LOG_DIR/push.log"; then
    log "Push completed successfully"
    audit_entry "push_complete" "SUCCESS" "Push to origin/main completed"
    
    echo ""
    echo -e "${GREEN}✅ Push successful!${NC}"
    echo ""
    echo "Latest commit:"
    sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" log --oneline -1
    echo ""
    
    return 0
  else
    error "Push failed - see log for details"
    audit_entry "push_complete" "FAILED" "Push to origin/main failed"
    return 1
  fi
}

watch_for_changes() {
  # Continuously push on changes
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Watch Mode - Continuous Push on Changes"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Monitoring $NAS_REPO_PATH for changes..."
  echo "Press Ctrl+C to exit"
  echo ""
  
  log "Watch mode started"
  audit_entry "watch_start" "STARTED" "Continuous watch mode"
  
  local last_push_time=0
  local debounce_delay=5  # seconds
  
  while true; do
    # Check if files have changed
    local current_time
    current_time=$(date +%s)
    
    if sudo -u "$PUSH_USER" -H git -C "$NAS_REPO_PATH" diff-index --quiet HEAD --; then
      : # No changes
    else
      local time_since_last
      time_since_last=$((current_time - last_push_time))
      
      if [ "$time_since_last" -ge "$debounce_delay" ]; then
        info "Changes detected, pushing in 5 seconds (Ctrl+C to cancel)..."
        sleep 5
        
        if push_to_eiqnas; then
          last_push_time=$(date +%s)
        fi
      fi
    fi
    
    sleep 1
  done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║           Dev Node NAS Push - eiq-nas Integration                         ║"
echo "║                  Mode: $MODE | $(date '+%Y-%m-%d %H:%M:%S UTC')            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Initialize audit entry
audit_entry "session_start" "INITIATED" "Mode: $MODE"

# Verify elevatediq-svc-git user and SSH access
if ! verify_svc_git; then
  error "elevatediq-svc-git verification failed"
  exit 1
fi

# Execute based on mode
case "$MODE" in
  diff)
    check_git_status
    check_diff
    ;;
    
  watch)
    watch_for_changes
    ;;
    
  push|"")
    check_git_status
    if push_to_eiqnas; then
      exit 0
    else
      exit 1
    fi
    ;;
    
  *)
    error "Unknown mode: $MODE"
    echo "Usage: $0 [push|watch|diff]"
    exit 1
    ;;
esac

exit 0
