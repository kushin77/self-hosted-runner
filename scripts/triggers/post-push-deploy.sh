#!/bin/bash
################################################################################
# 🚀 POST-PUSH DEPLOYMENT TRIGGER
#
# Automatically deploys complete stack when commits are pushed to main branch
#
# MANDATE: On any main branch push/merge:
#   ✅ Trigger fresh build deployment
#   ✅ Update entire stack on 192.168.168.42
#   ✅ Create version backup for rollback
#   ✅ Auto-rollback on deployment failure
#   ✅ Notify Slack on success/failure
#
# Installation:
#   git config --local core.hooksPath .githooks
#   cp scripts/triggers/post-push-deploy.sh .githooks/post-push
#   chmod +x .githooks/post-push
#
# Or for remote server (SSH hook):
#   Install as post-receive hook in bare repository
#
# Triggered By:
#   - git push origin main
#   - GitHub pull requests merged to main
#   - Any commit landing on main branch
#
# Environment Variables:
#   TARGET_HOST       - Deployment target (default: 192.168.168.42)
#   SERVICE_ACCOUNT   - SSH service account (default: automation)
#   SSH_KEY           - Path to SSH key (default: ~/.ssh/automation_ed25519)
#   SLACK_WEBHOOK     - Slack webhook for notifications
#   DRY_RUN           - Set to "true" to preview without deploying
#   SKIP_ROLLBACK     - Set to "true" to disable auto-rollback
#
################################################################################

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
readonly SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-automation}"
readonly SSH_KEY="${SSH_KEY:-$HOME/.ssh/automation_ed25519}"
readonly DEPLOYMENT_LOG="${REPO_ROOT}/logs/deployments/$(date +%Y%m%d_%H%M%S).log"
readonly VERSION_BACKUP_DIR="${REPO_ROOT}/.deployment-backups"
readonly SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
readonly DRY_RUN="${DRY_RUN:-false}"
readonly SKIP_ROLLBACK="${SKIP_ROLLBACK:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# LOGGING & FORMATTING
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$DEPLOYMENT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$DEPLOYMENT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$DEPLOYMENT_LOG"; }
log_step() { echo -e "${YELLOW}▶${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$DEPLOYMENT_LOG"; }
log_section() { echo -e "\n${BLUE}══════════════════════════════════════════════════════╗${NC}" | tee -a "$DEPLOYMENT_LOG"; echo -e "${BLUE}║ $*${NC}" | tee -a "$DEPLOYMENT_LOG"; echo -e "${BLUE}╚══════════════════════════════════════════════════════${NC}\n" | tee -a "$DEPLOYMENT_LOG"; }

# =============================================================================
# SLACK NOTIFICATIONS
# =============================================================================

notify_slack() {
    local status="$1"
    local message="$2"
    local commit_sha="${3:-}"
    local duration="${4:-}"
    
    if [[ -z "$SLACK_WEBHOOK" ]]; then
        log_info "Slack webhook not configured (skipping notification)"
        return 0
    fi
    
    local color
    case "$status" in
        success) color="#36a64f" ;;
        failure) color="#ff0000" ;;
        rollback) color="#ff9900" ;;
        *) color="#808080" ;;
    esac
    
    local title
    case "$status" in
        success) title="✅ Deployment Successful (Fresh Build)" ;;
        failure) title="❌ Deployment Failed" ;;
        rollback) title="⚙️  Auto-Rollback Triggered" ;;
        *) title="📢 Deployment Update" ;;
    esac
    
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "$title",
            "text": "$message",
            "fields": [
                {
                    "title": "Target Host",
                    "value": "$TARGET_HOST",
                    "short": true
                },
                {
                    "title": "Deployment Type",
                    "value": "Fresh Build (Complete Rebuild)",
                    "short": true
                }
                $(if [[ -n "$commit_sha" ]]; then echo ",{\"title\": \"Commit SHA\", \"value\": \"$commit_sha\", \"short\": true}"; fi)
                $(if [[ -n "$duration" ]]; then echo ",{\"title\": \"Duration\", \"value\": \"$duration\", \"short\": true}"; fi)
            ],
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK" \
        2>/dev/null || log_error "Failed to send Slack notification"
}

# =============================================================================
# VERSION BACKUP & ROLLBACK
# =============================================================================

create_version_backup() {
    local commit_sha="$1"
    local backup_name="backup-${commit_sha:0:8}-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$VERSION_BACKUP_DIR/$backup_name"
    
    log_step "Creating version backup: $backup_name"
    mkdir -p "$VERSION_BACKUP_DIR"
    
    # Create backup metadata
    cat > "$backup_path.metadata" <<EOF
{
  "backup_name": "$backup_name",
  "commit_sha": "$commit_sha",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target_host": "$TARGET_HOST",
  "deployment_log": "$DEPLOYMENT_LOG"
}
EOF
    
    # Store current git state
    git rev-parse HEAD > "$backup_path.sha" 2>/dev/null || true
    git describe --tags --always > "$backup_path.version" 2>/dev/null || true
    
    log_success "Version backup created: $backup_path"
    echo "$backup_path"
}

get_previous_backup() {
    # Find the most recent backup before current deployment
    if [[ ! -d "$VERSION_BACKUP_DIR" ]]; then
        return 1
    fi
    
    local latest_backup=$(ls -t "$VERSION_BACKUP_DIR"/*.metadata 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        echo "${latest_backup%.metadata}"
        return 0
    fi
    
    return 1
}

rollback_to_version() {
    local backup_path="$1"
    
    if [[ ! -f "$backup_path.sha" ]]; then
        log_error "Cannot rollback: backup SHA not found"
        return 1
    fi
    
    local previous_sha=$(cat "$backup_path.sha")
    log_step "Rolling back to version: $previous_sha"
    
    # Create rollback marker
    cat > "$REPO_ROOT/.deployment-rollback" <<EOF
{
  "rollback_sha": "$previous_sha",
  "rollback_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "from_backup": "$backup_path"
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rollback to: $previous_sha"
        return 0
    fi
    
    # Trigger rollback deployment
    if ssh -i "$SSH_KEY" "${SERVICE_ACCOUNT}@${TARGET_HOST}" \
        "cd /opt/self-hosted-runner && git checkout $previous_sha && bash deploy-worker-node.sh"; then
        log_success "Rollback completed to: $previous_sha"
        return 0
    else
        log_error "Rollback FAILED - manual intervention required!"
        return 1
    fi
}

# =============================================================================
# DEPLOYMENT EXECUTION
# =============================================================================

execute_fresh_build_deployment() {
    local commit_sha="$1"
    local start_time=$(date +%s)
    
    log_section "FRESH BUILD DEPLOYMENT INITIATED"
    log_info "Commit: $commit_sha"
    log_info "Target: $TARGET_HOST"
    log_info "Type: Complete Fresh Build (Mandate Enforcement)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN MODE] Skipping actual deployment"
        return 0
    fi
    
    # Verify SSH connectivity
    log_step "Verifying SSH connectivity to target..."
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 "${SERVICE_ACCOUNT}@${TARGET_HOST}" "echo 'SSH connection verified'" 2>/dev/null; then
        log_error "Cannot connect to target host: $TARGET_HOST"
        return 1
    fi
    log_success "Target host connectivity verified"
    
    # Create version backup BEFORE deployment
    local backup_path
    backup_path=$(create_version_backup "$commit_sha")
    
    # Push latest code to target
    log_step "Syncing code to target host..."
    if ! ssh -i "$SSH_KEY" "${SERVICE_ACCOUNT}@${TARGET_HOST}" "cd /opt/self-hosted-runner && git pull origin main" 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
        log_error "Failed to sync code to target"
        return 1
    fi
    log_success "Code synced to target"
    
    # Execute fresh build deployment
    log_step "Starting fresh build deployment on target..."
    if ssh -i "$SSH_KEY" "${SERVICE_ACCOUNT}@${TARGET_HOST}" \
        "cd /opt/self-hosted-runner && TARGET_HOST=$TARGET_HOST bash deploy-worker-node.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local duration_formatted=$(printf '%dh %dm %ds\n' $((duration/3600)) $((duration%3600/60)) $((duration%60)))
        
        log_success "Fresh build deployment completed successfully!"
        log_info "Duration: $duration_formatted"
        
        # Update to latest deployment marker
        cat > "$REPO_ROOT/.last-deployment" <<EOF
{
  "deployment_sha": "$commit_sha",
  "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target_host": "$TARGET_HOST",
  "status": "success",
  "duration_seconds": $duration,
  "backup_path": "$backup_path",
  "mandate": "Fresh Build (Complete Rebuild) - On-Prem Only"
}
EOF
        
        return 0
    else
        log_error "Fresh build deployment FAILED"
        
        # Auto-rollback on deployment failure
        if [[ "$SKIP_ROLLBACK" != "true" ]]; then
            log_step "Initiating auto-rollback..."
            if rollback_to_version "$backup_path"; then
                log_success "Auto-rollback completed successfully"
                notify_slack "rollback" "Deployment failed and was auto-rolled back to previous version." "$commit_sha"
                return 1
            else
                log_error "Auto-rollback FAILED - MANUAL INTERVENTION REQUIRED!"
                notify_slack "failure" "⚠️ CRITICAL: Deployment failed and auto-rollback also failed. Manual intervention required immediately on $TARGET_HOST" "$commit_sha"
                return 1
            fi
        else
            notify_slack "failure" "Deployment failed (rollback disabled)" "$commit_sha"
            return 1
        fi
    fi
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
    # Initialize log directory
    mkdir -p "$(dirname "$DEPLOYMENT_LOG")"
    
    log_section "POST-PUSH DEPLOYMENT TRIGGER"
    log_info "Script: $(basename "$0")"
    log_info "Repository: $REPO_ROOT"
    log_info "User: $(whoami)"
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Determine if this is a main branch push
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    log_info "Current branch: ${current_branch:-unknown}"
    
    # Only deploy on main branch
    if [[ "$current_branch" != "main" && "$current_branch" != "HEAD" ]]; then
        log_info "Not on main branch (current: $current_branch) - skipping deployment"
        return 0
    fi
    
    # Get current commit SHA
    local commit_sha
    commit_sha=$(git rev-parse HEAD 2>/dev/null)
    
    if [[ -z "$commit_sha" ]]; then
        log_error "Cannot determine current commit SHA"
        return 1
    fi
    
    log_info "Commit SHA: $commit_sha"
    
    # Check if deployment is already running
    if [[ -f "$REPO_ROOT/.deployment-in-progress" ]]; then
        local progress_file="$REPO_ROOT/.deployment-in-progress"
        log_error "Deployment already in progress (lock file: $progress_file)"
        log_error "Previous deployment started: $(cat "$progress_file")"
        return 1
    fi
    
    # Create deployment lock
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - PID: $$" > "$REPO_ROOT/.deployment-in-progress"
    trap "rm -f '$REPO_ROOT/.deployment-in-progress'" EXIT
    
    # Execute deployment
    if execute_fresh_build_deployment "$commit_sha"; then
        log_section "✅ DEPLOYMENT SUCCESSFUL"
        notify_slack "success" "Fresh build deployment to $TARGET_HOST completed successfully. All systems operational." "$commit_sha"
        return 0
    else
        log_section "❌ DEPLOYMENT FAILED"
        notify_slack "failure" "Fresh build deployment to $TARGET_HOST failed. Check logs: $DEPLOYMENT_LOG" "$commit_sha"
        return 1
    fi
}

# =============================================================================
# SCRIPT ENTRY
# =============================================================================

# Only run if being executed as a script (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi
