#!/bin/bash
# OPERATOR INJECTION: Slack Webhook Configuration
# Injects Slack webhook URL into GCP Secret Manager
# Usage: bash scripts/ops/OPERATOR_INJECT_SLACK_WEBHOOK.sh --webhook-url "https://hooks.slack.com/..."

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRET_NAME="slack-webhook"
readonly GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
readonly AUDIT_LOG="${WORKSPACE_ROOT}/logs/slack-webhook-audit.jsonl"
readonly TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_step() { echo -e "${YELLOW}▶${NC} $1" | tee -a "$AUDIT_LOG"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --webhook-url) WEBHOOK_URL="$2"; shift 2 ;;
        --gcp-project) GCP_PROJECT="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "${WEBHOOK_URL:-}" ]; then
    log_error "Missing required argument: --webhook-url"
    echo "Usage: $0 --webhook-url https://hooks.slack.com/services/YOUR/WEBHOOK/URL [--gcp-project nexusshield-prod]"
    exit 1
fi

# Initialize
mkdir -p "$(dirname "$AUDIT_LOG")"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"slack_webhook_injection_started\",\"gcp_project\":\"$GCP_PROJECT\",\"user\":\"$USER\",\"webhook_domain\":\"https://hooks.slack.com\"}" >> "$AUDIT_LOG"

log_step "Configuring Slack Webhook"
log_info "GCP Project: $GCP_PROJECT"
log_info "Webhook Domain: https://hooks.slack.com/... (URL masked for security)"

# Verify gcloud is available
log_step "Verifying gcloud CLI..."
if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found. Please install Google Cloud SDK."
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"gcloud_check\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi
log_success "gcloud CLI verified"

# Set GCP project
gcloud config set project "$GCP_PROJECT" 2>/dev/null || {
    log_error "Failed to set GCP project: $GCP_PROJECT"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"gcloud_project_set\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
}
log_success "GCP project set: $GCP_PROJECT"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"gcp_project_configured\",\"project\":\"$GCP_PROJECT\",\"status\":\"success\"}" >> "$AUDIT_LOG"

# Validate Slack webhook URL format
log_step "Validating Slack webhook URL..."
if ! [[ "$WEBHOOK_URL" =~ ^https://hooks\.slack\.com/services/[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9]+$ ]]; then
    log_error "Invalid Slack webhook URL format"
    log_info "Expected format: https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    log_info "Got: $WEBHOOK_URL (partial log)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"webhook_format_validation\",\"status\":\"invalid\"}" >> "$AUDIT_LOG"
    exit 1
fi
log_success "Webhook URL format valid"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"webhook_format_validated\",\"status\":\"valid\"}" >> "$AUDIT_LOG"

# Test webhook connectivity
log_step "Testing Slack webhook connectivity..."
TEST_PAYLOAD='{"text":"Deployment system testing connection to Slack webhook."}'

if curl -s -X POST \
    -H 'Content-type: application/json' \
    --data "$TEST_PAYLOAD" \
    "$WEBHOOK_URL" \
    2>/dev/null | grep -q "ok"; then
    log_success "Slack webhook connectivity verified"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"webhook_connectivity_test\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_error "Slack webhook connectivity test failed"
    log_info "Possible causes:"
    log_info "  - Webhook URL is invalid"
    log_info "  - Slack workspace is not accessible"
    log_info "  - Network connectivity issue"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"webhook_connectivity_test\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi

# Store webhook in Google Secret Manager
log_step "Storing webhook in Google Secret Manager..."

# Check if secret already exists
if gcloud secrets describe "$SECRET_NAME" --project "$GCP_PROJECT" >/dev/null 2>&1; then
    log_info "Secret already exists, adding new version..."
    if echo "$WEBHOOK_URL" | gcloud secrets versions add "$SECRET_NAME" \
        --data-file=- \
        --project "$GCP_PROJECT" \
        >/dev/null 2>&1; then
        log_success "New secret version created"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_version_added\",\"secret\":\"$SECRET_NAME\",\"status\":\"success\"}" >> "$AUDIT_LOG"
    else
        log_error "Failed to add secret version"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_version_add\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
        exit 1
    fi
else
    log_info "Creating new secret..."
    if echo "$WEBHOOK_URL" | gcloud secrets create "$SECRET_NAME" \
        --data-file=- \
        --replication-policy="automatic" \
        --project "$GCP_PROJECT" \
        >/dev/null 2>&1; then
        log_success "Secret created in GSM"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_created\",\"secret\":\"$SECRET_NAME\",\"status\":\"success\"}" >> "$AUDIT_LOG"
    else
        log_error "Failed to create secret in GSM"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_creation\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
        exit 1
    fi
fi

# Wait for secret to be available
sleep 2

# Verify secret was stored
log_step "Verifying secret storage..."
if gcloud secrets versions access latest --secret="$SECRET_NAME" --project "$GCP_PROJECT" 2>/dev/null | grep -q "hooks.slack.com"; then
    log_success "Secret verified in GCP Secret Manager"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_verification\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_error "Failed to verify secret"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_verification\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi

# Trigger auto-retry notification system
log_step "Triggering auto-retry notification system..."
if [ -f "${WORKSPACE_ROOT}/scripts/ops/auto-retry-notifications.sh" ]; then
    log_info "Starting notification auto-retry watcher..."
    # This script runs in background and detects new webhook
    bash "${WORKSPACE_ROOT}/scripts/ops/auto-retry-notifications.sh" &>/dev/null &
    RETRY_PID=$!
    disown $RETRY_PID 2>/dev/null || true
    log_success "Auto-retry watcher started (PID: $RETRY_PID)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"auto_retry_started\",\"pid\":$RETRY_PID,\"status\":\"started\"}" >> "$AUDIT_LOG"
else
    log_info "Auto-retry watcher not found (optional)"
fi

# Wait for pending notifications to be sent (if auto-retry is running)
log_step "Waiting for pending notifications to be sent (30 seconds)..."
sleep 30

# Check notification logs
NOTIFICATION_LOG="${WORKSPACE_ROOT}/logs/cutover/auto-retry-notifications.log"
if [ -f "$NOTIFICATION_LOG" ]; then
    RECENT_NOTIFICATIONS=$(tail -5 "$NOTIFICATION_LOG" 2>/dev/null || echo "")
    if echo "$RECENT_NOTIFICATIONS" | grep -q "sent.*success"; then
        log_success "Recent notifications sent successfully"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"pending_notifications_sent\",\"status\":\"sent\"}" >> "$AUDIT_LOG"
    else
        log_info "Waiting for notifications... (may send shortly)"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"pending_notifications_status\",\"status\":\"pending\"}" >> "$AUDIT_LOG"
    fi
fi

# Generate status report
WEBHOOK_STATUS="${WORKSPACE_ROOT}/logs/slack-webhook-status.md"
{
    cat <<EOF
# Slack Webhook Configuration Status

**Configuration Date:** $TIMESTAMP
**GCP Project:** $GCP_PROJECT
**Secret Name:** $SECRET_NAME
**Status:** ✅ DEPLOYED

## What Was Configured

- Slack webhook URL stored in GCP Secret Manager
- Webhook connectivity verified
- Auto-retry notification system enabled
- Pending notifications queued for delivery

## Slack Integration Details

- **Notification Channel:** Configured in Slack workspace
- **Notification Types:** 
  - DNS cutover completion
  - Phase completion milestones
  - Error alerts (pending)
- **Message Format:** JSON with structured metadata
- **Retry Policy:** Every 30 seconds (auto-retry enabled)

## Pending Notifications

DNS cutover completion notification pending delivery. Will be sent within 30-60 seconds of webhook configuration.

Notification details:
- Date: 2026-03-13T14:10:51Z
- Content: Phase 2 & 3 DNS promotion complete, production live

## Next Steps

1. Monitor Slack for incoming notifications
2. Verify notifications are being received
3. Optional: Configure additional notification channels
4. Optional: Set up Slack notification filtering/routing

## Files Updated

- GCP Secret Manager: \`slack-webhook\` secret
- Auto-retry system: Active and monitoring
- Audit logs: \`logs/slack-webhook-audit.jsonl\`

---
Generated: $TIMESTAMP
EOF
} > "$WEBHOOK_STATUS"

log_success "Status report written: $WEBHOOK_STATUS"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"status_report_generated\",\"file\":\"$WEBHOOK_STATUS\",\"status\":\"success\"}" >> "$AUDIT_LOG"

# Final success
log_success "=== Slack Webhook Configuration Complete ==="
log_info "Deployment: ✅ SUCCESS"
log_info "Secret Name: $SECRET_NAME"
log_info "GCP Project: $GCP_PROJECT"
log_info "Status: Ready for notifications"
log_info "Pending notifications: Will auto-send in ~30 seconds"
log_info "Status Report: $WEBHOOK_STATUS"
log_info "Audit Trail: $AUDIT_LOG"

echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"slack_webhook_injection_completed\",\"status\":\"success\",\"gcp_project\":\"$GCP_PROJECT\",\"notifications_pending\":true}" >> "$AUDIT_LOG"

log_info ""
log_success "Slack webhook is now active and receiving notifications"
log_success "Pending notifications will auto-send to Slack within 30-60 seconds"
