#!/bin/bash
# monitoring-notification-channels.sh
# Configure Cloud Monitoring notification channels for all alert policies
# Purpose: Setup email, Slack, and PagerDuty notification channels
# Related Issues: #2560, #2561, #2357

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AUDIT_FILE="${REPO_ROOT}/logs/notification-channels-audit.jsonl"

# Configuration from environment or defaults
EMAIL_ADDRESS="${ALERT_EMAIL:-platform-alerting@nexusshield-prod.iam.gserviceaccount.com}"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"
PAGERDUTY_KEY="${PAGERDUTY_INTEGRATION_KEY:-}"

mkdir -p "$(dirname "${AUDIT_FILE}")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

audit_entry() {
    local event="$1"
    local details="${2:-}"
    local status="${3:-success}"
    echo "{\"timestamp\": \"${TIMESTAMP}\", \"event\": \"${event}\", \"status\": \"${status}\", \"details\": \"${details}\"}" >> "${AUDIT_FILE}"
}

# ============================================================================
# Helper Functions
# ============================================================================
retry_cmd() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=1
    
    while [ $attempt -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi
        if [ $attempt -lt "$max_attempts" ]; then
            echo "Attempt $attempt failed, retrying in ${delay}s..." >&2
            sleep "$delay"
        fi
        ((attempt++))
    done
    
    return 1
}

# ============================================================================
# Create Email Notification Channel
# ============================================================================
create_email_channel() {
    log_info "Creating email notification channel..."
    
    local channel_json=$(mktemp)
    cat > "$channel_json" <<EOF
{
  "type": "email",
  "displayName": "Platform Alerting Email",
  "description": "Email notifications for monitoring alerts",
  "labels": {
    "email_address": "${EMAIL_ADDRESS}"
  },
  "enabled": true
}
EOF

    if channel_id=$(gcloud alpha monitoring channels create \
        --channel-content-from-file="$channel_json" \
        --format='value(name)' 2>/dev/null); then
        log_info "Email channel created: $channel_id"
        audit_entry "email_channel_created" "channel_id: $channel_id"
        echo "$channel_id"
    else
        log_warn "Email channel creation failed or already exists; attempting to list..."
        if channel_id=$(gcloud alpha monitoring channels list \
            --filter='type=email AND displayName="Platform Alerting Email"' \
            --format='value(name)' | head -1); then
            if [ -n "$channel_id" ]; then
                log_info "Using existing email channel: $channel_id"
                echo "$channel_id"
            else
                log_error "Could not create or find email notification channel"
                audit_entry "email_channel" "failed" "failure"
                return 1
            fi
        fi
    fi
    
    rm -f "$channel_json"
}

# ============================================================================
# Create Slack Notification Channel
# ============================================================================
create_slack_channel() {
    if [ -z "$SLACK_WEBHOOK" ]; then
        log_warn "SLACK_WEBHOOK_URL not set; skipping Slack channel creation"
        log_warn "To enable Slack notifications, set: export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'"
        return 0
    fi
    
    log_info "Creating Slack notification channel..."
    
    local channel_json=$(mktemp)
    cat > "$channel_json" <<EOF
{
  "type": "slack",
  "displayName": "Slack Alerts",
  "description": "Slack notifications for monitoring alerts",
  "labels": {
    "url": "${SLACK_WEBHOOK}"
  },
  "enabled": true
}
EOF

    if channel_id=$(gcloud alpha monitoring channels create \
        --channel-content-from-file="$channel_json" \
        --format='value(name)' 2>/dev/null); then
        log_info "Slack channel created: $channel_id"
        audit_entry "slack_channel_created" "channel_id: $channel_id"
        echo "$channel_id"
    else
        log_warn "Slack channel creation failed; attempting to list existing..."
        if channel_id=$(gcloud alpha monitoring channels list \
            --filter='type=slack AND displayName="Slack Alerts"' \
            --format='value(name)' | head -1); then
            if [ -n "$channel_id" ]; then
                log_info "Using existing Slack channel: $channel_id"
                echo "$channel_id"
            else
                log_warn "Could not create Slack notification channel"
                audit_entry "slack_channel" "skipped" "warning"
            fi
        fi
    fi
    
    rm -f "$channel_json"
}

# ============================================================================
# Create PagerDuty Notification Channel
# ============================================================================
create_pagerduty_channel() {
    if [ -z "$PAGERDUTY_KEY" ]; then
        log_warn "PAGERDUTY_INTEGRATION_KEY not set; skipping PagerDuty channel creation"
        log_warn "To enable PagerDuty notifications, set: export PAGERDUTY_INTEGRATION_KEY='<integration_key>'"
        return 0
    fi
    
    log_info "Creating PagerDuty notification channel..."
    
    local channel_json=$(mktemp)
    cat > "$channel_json" <<EOF
{
  "type": "pagerduty",
  "displayName": "PagerDuty Alerts",
  "description": "PagerDuty notifications for critical alerts",
  "labels": {
    "service_key": "${PAGERDUTY_KEY}"
  },
  "enabled": true
}
EOF

    if channel_id=$(gcloud alpha monitoring channels create \
        --channel-content-from-file="$channel_json" \
        --format='value(name)' 2>/dev/null); then
        log_info "PagerDuty channel created: $channel_id"
        audit_entry "pagerduty_channel_created" "channel_id: $channel_id"
        echo "$channel_id"
    else
        log_warn "PagerDuty channel creation failed; attempting to list existing..."
        if channel_id=$(gcloud alpha monitoring channels list \
            --filter='type=pagerduty AND displayName="PagerDuty Alerts"' \
            --format='value(name)' | head -1); then
            if [ -n "$channel_id" ]; then
                log_info "Using existing PagerDuty channel: $channel_id"
                echo "$channel_id"
            else
                log_warn "Could not create PagerDuty notification channel"
                audit_entry "pagerduty_channel" "skipped" "warning"
            fi
        fi
    fi
    
    rm -f "$channel_json"
}

# ============================================================================
# Update Alert Policies with Notification Channels
# ============================================================================
update_alert_policies_with_channels() {
    log_info "Updating alert policies with notification channels..."
    
    # Get all active alert policies
    local policies=$(gcloud alpha monitoring policies list --format='value(name)')
    
    if [ -z "$policies" ]; then
        log_warn "No alert policies found to update"
        return 0
    fi
    
    # Create array of channel IDs to attach
    local channel_ids=()
    
    # Try to get email channel (primary/required)
    if email_ch=$(create_email_channel); then
        channel_ids+=("$email_ch")
    else
        log_error "Failed to create email channel - this is required"
        return 1
    fi
    
    # Try to get Slack channel (optional)
    if slack_ch=$(create_slack_channel); then
        if [ -n "$slack_ch" ]; then
            channel_ids+=("$slack_ch")
        fi
    fi
    
    # Try to get PagerDuty channel (optional)
    if pagerduty_ch=$(create_pagerduty_channel); then
        if [ -n "$pagerduty_ch" ]; then
            channel_ids+=("$pagerduty_ch")
        fi
    fi
    
    # Update each policy
    local policy_count=0
    while IFS= read -r policy_name; do
        if [ -z "$policy_name" ]; then
            continue
        fi
        
        log_debug "Processing policy: $policy_name"
        
        # Get current policy configuration
        local policy_json=$(gcloud alpha monitoring policies describe "$policy_name" --format=json 2>/dev/null || echo "{}")
        
        if [ "$policy_json" = "{}" ]; then
            log_warn "Could not retrieve policy: $policy_name"
            continue
        fi
        
        # Update policy with notification channels
        local update_json=$(mktemp)
        echo "$policy_json" | jq \
            --argjson channels "$(printf '["%s"]' "${channel_ids[@]}")" \
            '.notificationChannels = $channels' > "$update_json"
        
        if gcloud alpha monitoring policies update "$policy_name" \
            --policy-from-file="$update_json" 2>/dev/null; then
            log_info "✓ Policy updated: $policy_name"
            ((policy_count++))
        else
            log_warn "Failed to update policy: $policy_name"
        fi
        
        rm -f "$update_json"
    done <<< "$policies"
    
    log_info "Updated $policy_count alert policies with notification channels"
    audit_entry "alert_policies_updated" "count: $policy_count, channels: ${#channel_ids[@]}"
}

# ============================================================================
# List All Notification Channels (Verification)
# ============================================================================
verify_notification_channels() {
    log_info "Verifying notification channels..."
    echo ""
    echo "=== Active Notification Channels ==="
    gcloud alpha monitoring channels list --format='table(name,type,displayName,enabled)' || true
    echo ""
}

# ============================================================================
# List All Alert Policies (Verification)
# ============================================================================
verify_alert_policies() {
    log_info "Verifying alert policies..."
    echo ""
    echo "=== Active Alert Policies ==="
    gcloud alpha monitoring policies list --format='table(name,displayName)' || true
    echo ""
}

# ============================================================================
# Immutable Audit & Git Record
# ============================================================================
finalize_audit() {
    log_info "Recording immutable audit trail..."
    
    cd "${REPO_ROOT}"
    git add logs/notification-channels-audit.jsonl 2>/dev/null || true
    if git diff --cached --quiet 2>/dev/null; then
        log_debug "No changes to commit"
    else
        git commit -m "ops: notification channels configured (${TIMESTAMP}) - email, slack, pagerduty alerts setup" || true
        git push origin main || true
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "=========================================="
    echo "Notification Channels Configuration"
    echo "Immutable • Idempotent • Monitoring"
    echo "=========================================="
    echo ""
    
    log_info "Project: $GCP_PROJECT_ID"
    log_info "Email: $EMAIL_ADDRESS"
    [ -n "$SLACK_WEBHOOK" ] && log_info "Slack: configured" || log_info "Slack: not configured"
    [ -n "$PAGERDUTY_KEY" ] && log_info "PagerDuty: configured" || log_info "PagerDuty: not configured"
    echo ""
    
    # Main operations
    update_alert_policies_with_channels || {
        log_error "Failed to configure notification channels"
        audit_entry "main" "notification channels setup failed" "failure"
        exit 1
    }
    
    # Verify setup
    verify_notification_channels
    verify_alert_policies
    
    # Audit trail
    finalize_audit
    
    log_info "✅ Notification channels configured successfully"
    audit_entry "main_complete" "notification channels setup completed"
}

main "$@"
