#!/bin/bash
################################################################################
# ⚡ GITHUB WEBHOOK DEPLOYMENT HANDLER
#
# Integrates with GitHub webhook receiver to trigger automatic deployments
# when commits are pushed to main branch
#
# This handler:
#   1. Receives webhook event from GitHub
#   2. Validates webhook signature
#   3. Extracts commit information
#   4. Triggers fresh build deployment
#   5. Sends deployment status back to GitHub
#   6. Publishes Slack notifications
#
# Integration Points:
#   - GitHub → webhook receiver (Cloud Run)
#   - Webhook receiver → this handler
#   - Handler → deployment trigger (post-push-deploy.sh)
#   - Handler → Slack webhook for notifications
#
# Environment Variables (set via deployment service):
#   WEBHOOK_SECRET       - GitHub webhook signing secret
#   SLACK_WEBHOOK        - Slack webhook URL
#   TARGET_HOST          - Deployment target (192.168.168.42)
#   GITHUB_TOKEN         - GitHub API token for status updates
#   GIT_REPO_PATH        - Path to git repository
#
# Usage in webhook system:
#   POST /webhooks/deployment
#   Content-Type: application/json
#   X-Hub-Signature-256: sha256=...
#   
#   {
#     "ref": "refs/heads/main",
#     "before": "...",
#     "after": "...",
#     "repository": {...},
#     "pusher": {...}
#   }
#
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly DEPLOYMENT_TRIGGER="${SCRIPT_DIR}/post-push-deploy.sh"
readonly WEBHOOK_LOG="${REPO_ROOT}/logs/webhook-deployments.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# LOGGING & UTILITIES
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$WEBHOOK_LOG"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$WEBHOOK_LOG"
}

log_error() {
    echo -e "${RED}[✗]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$WEBHOOK_LOG"
}

# =============================================================================
# WEBHOOK VALIDATION
# =============================================================================

validate_webhook_signature() {
    local payload="$1"
    local signature="$2"
    local secret="${3:-}"
    
    if [[ -z "$secret" ]]; then
        log_error "Webhook secret not configured"
        return 1
    fi
    
    # Calculate expected signature
    local expected_sig="sha256=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" -r | awk '{print $1}')"
    
    # Constant-time comparison
    if [[ "$signature" == "$expected_sig" ]]; then
        log_success "Webhook signature validation passed"
        return 0
    else
        log_error "Webhook signature validation failed"
        echo "Signature mismatch: expected=$expected_sig, got=$signature" >&2
        return 1
    fi
}

# =============================================================================
# GITHUB STATUS UPDATES
# =============================================================================

post_github_status() {
    local repo_owner="$1"
    local repo_name="$2"
    local commit_sha="$3"
    local state="$4"        # pending, success, failure, error
    local description="$5"
    local context="${6:-deployment}"
    
    local github_token="${GITHUB_TOKEN:-}"
    
    if [[ -z "$github_token" ]]; then
        log_info "GitHub token not configured - skipping status update"
        return 0
    fi
    
    local status_url="https://api.github.com/repos/${repo_owner}/${repo_name}/statuses/${commit_sha}"
    
    local payload=$(cat <<EOF
{
  "state": "$state",
  "description": "$description",
  "context": "$context"
}
EOF
)
    
    if curl -s -X POST \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "$payload" \
        "$status_url" > /dev/null 2>&1; then
        log_success "Posted GitHub status: $state"
        return 0
    else
        log_error "Failed to post GitHub status"
        return 1
    fi
}

# =============================================================================
# DEPLOYMENT TRIGGERING
# =============================================================================

trigger_deployment() {
    local commit_sha="$1"
    local repo_owner="$2"
    local repo_name="$3"
    local branch="$4"
    
    log_info "Triggering deployment for commit: $commit_sha"
    
    # Verify trigger script exists
    if [[ ! -x "$DEPLOYMENT_TRIGGER" ]]; then
        log_error "Deployment trigger script not found: $DEPLOYMENT_TRIGGER"
        return 1
    fi
    
    # Post pending status to GitHub
    post_github_status "$repo_owner" "$repo_name" "$commit_sha" "pending" "Deployment in progress..." "deployment"
    
    # Execute deployment in background
    (
        cd "$REPO_ROOT"
        export DEPLOYMENT_COMMIT_SHA="$commit_sha"
        export TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
        
        log_info "Starting deployment process..."
        
        if bash "$DEPLOYMENT_TRIGGER" 2>&1 | tee -a "$WEBHOOK_LOG"; then
            log_success "Deployment completed successfully"
            post_github_status "$repo_owner" "$repo_name" "$commit_sha" "success" "Fresh build deployment successful" "deployment"
            return 0
        else
            log_error "Deployment failed"
            post_github_status "$repo_owner" "$repo_name" "$commit_sha" "failure" "Fresh build deployment failed" "deployment"
            return 1
        fi
    ) &
    
    local bg_pid=$!
    log_info "Deployment process started in background (PID: $bg_pid)"
    
    return 0
}

# =============================================================================
# WEBHOOK HANDLER
# =============================================================================

handle_push_webhook() {
    local payload="$1"
    
    log_info "Processing push webhook"
    
    # Extract information from payload
    local ref
    local commit_sha
    local repo_owner
    local repo_name
    
    # Parse JSON payload
    ref=$(echo "$payload" | grep -o '"ref":"[^"]*"' | head -1 | cut -d'"' -f4)
    commit_sha=$(echo "$payload" | grep -o '"after":"[^"]*"' | head -1 | cut -d'"' -f4)
    repo_owner=$(echo "$payload" | grep -o '"owner":{"type":"User","name":"[^"]*"' | cut -d'"' -f8 || echo "")
    repo_name=$(echo "$payload" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$repo_owner" ]]; then
        # Try alternate format
        repo_owner=$(echo "$payload" | grep -o '"login":"[^"]*"' | cut -d'"' -f4)
    fi
    
    log_info "Ref: $ref"
    log_info "Commit: $commit_sha"
    log_info "Repository: ${repo_owner}/${repo_name}"
    
    # Only process main branch pushes
    if [[ "$ref" != "refs/heads/main" ]]; then
        log_info "Skipping non-main branch: $ref"
        return 0
    fi
    
    log_success "Main branch push detected - triggering deployment"
    
    # Trigger fresh build deployment
    if trigger_deployment "$commit_sha" "$repo_owner" "$repo_name" "$ref"; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# MAIN HANDLER
# =============================================================================

main() {
    local webhook_payload="$1"
    local webhook_signature="$2"
    
    # Initialize log
    mkdir -p "$(dirname "$WEBHOOK_LOG")"
    
    log_info "Webhook handler invoked"
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Validate webhook signature
    if ! validate_webhook_signature "$webhook_payload" "$webhook_signature" "${WEBHOOK_SECRET:-}"; then
        log_error "Webhook signature validation failed - aborting"
        return 1
    fi
    
    # Process webhook
    if handle_push_webhook "$webhook_payload"; then
        log_success "Webhook processed successfully"
        return 0
    else
        log_error "Webhook processing failed"
        return 1
    fi
}

# =============================================================================
# ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <webhook_payload> <webhook_signature>"
        echo ""
        echo "Example:"
        echo "  $0 '{\"ref\":\"refs/heads/main\", ...}' 'sha256=...'"
        exit 1
    fi
    
    main "$1" "$2"
    exit $?
fi
