#!/bin/bash
################################################################################
# 🚀 POST-RECEIVE HOOK (Server-Side Deployment Trigger)
#
# Runs on the remote Git repository (bare repo) when commits are pushed
# Automatically triggers fresh build deployment on main branch push
#
# Installation on remote server (192.168.168.42 or Git server):
#   1. Copy this to: /path/to/repo.git/hooks/post-receive
#   2. chmod +x /path/to/repo.git/hooks/post-receive
#   3. Set environment variables in a .env file or systemd service
#
# Triggered By:
#   - git push origin main
#   - Any commits landing on main branch
#
# What It Does:
#   1. Detects if push is to main branch
#   2. Extracts commit SHA
#   3. Calls deployment trigger script
#   4. Logs all operations for audit trail
#   5. Sends deployment status notifications
#
# Environment Variables (set via deployment service):
#   DEPLOYMENT_TRIGGER_SCRIPT - Path to post-push-deploy.sh
#   TARGET_HOST               - Deployment target (192.168.168.42)
#   SLACK_WEBHOOK             - Slack webhook URL
#
################################################################################

set -euo pipefail

# Git post-receive receives refs on stdin in format: oldrev newrev refname
# Example: 0000000000000000000000000000000000000000 abc123def456 refs/heads/main

readonly GIT_DIR="${GIT_DIR:-.}"
readonly REPO_NAME=$(basename "$GIT_DIR" .git)
readonly HOOK_LOG="${GIT_DIR}/hooks/post-receive.log"
readonly DEPLOYMENT_SCRIPT="${DEPLOYMENT_TRIGGER_SCRIPT:-/opt/self-hosted-runner/scripts/triggers/post-push-deploy.sh}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local msg="$*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg" | tee -a "$HOOK_LOG"
}

log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$HOOK_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$HOOK_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$HOOK_LOG"; }

# =============================================================================
# MAIN LOGIC
# =============================================================================

# Ensure log directory exists
mkdir -p "$(dirname "$HOOK_LOG")"

log_info "Post-receive hook triggered for: $REPO_NAME"

# Read push refs from stdin
while IFS= read -r oldrev newrev refname; do
    log_info "Received push: $refname ($newrev)"
    
    # Check if this is a push to main branch
    if [[ "$refname" == "refs/heads/main" ]]; then
        log_success "Push to main branch detected"
        log_info "Old revision: $oldrev"
        log_info "New revision: $newrev"
        
        # Verify the deployment trigger script exists
        if [[ ! -x "$DEPLOYMENT_SCRIPT" ]]; then
            log_error "Deployment script not found or not executable: $DEPLOYMENT_SCRIPT"
            echo "error: deployment trigger script not available" >&2
            continue
        fi
        
        log_info "Executing deployment trigger..."
        
        # Call the deployment trigger script in background
        # This prevents the git push from blocking while deployment runs
        (
            export DEPLOYMENT_COMMIT_SHA="$newrev"
            export DEPLOYMENT_REF="$refname"
            export DEPLOYMENT_INITIATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            
            log_info "Starting deployment process (PID: $$)"
            if bash "$DEPLOYMENT_SCRIPT" >>"$HOOK_LOG" 2>&1; then
                log_success "Deployment process initiated successfully"
            else
                log_error "Deployment process initiation failed"
            fi
        ) &
        
        # Capture background PID for tracking
        local bg_pid=$!
        log_info "Deployment process backgrounded (PID: $bg_pid)"
        
        # Send immediate acknowledgment to git client
        echo "✓ Deployment triggered for commit $newrev on $refname"
        echo "  Check logs for deployment progress: $HOOK_LOG"
        
    else
        log_info "Push to non-main branch: $refname (skipping deployment)"
    fi
done

log_success "Post-receive hook completed"
exit 0
