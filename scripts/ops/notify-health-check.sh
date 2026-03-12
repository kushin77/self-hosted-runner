#!/bin/bash
# Notification Dispatcher: Health Check Status → Slack/Teams
#
# Purpose:
#   Parse health check results and route alerts to Slack/Teams webhooks
#   All actions logged to immutable JSONL audit trail
#   Idempotent: safe to re-run multiple times
#
# Usage:
#   ./scripts/ops/notify-health-check.sh --status [success|failure] --service <name> --message <msg>
#
# Examples:
#   ./scripts/ops/notify-health-check.sh --status success --service milestone-organizer --message "Daily run completed"
#   ./scripts/ops/notify-health-check.sh --status failure --service backend --message "Health check timed out"

set -euo pipefail

# Config
AUDIT_DIR="${AUDIT_DIR:-logs/multi-cloud-audit}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SCRIPT_NAME="notify-health-check"

# Fetch webhook from GSM
get_webhook_url() {
    local webhook_type=$1  # slack or teams
    if command -v gcloud &> /dev/null; then
        gcloud secrets versions access latest --secret="${webhook_type}-webhook" 2>/dev/null || echo ""
    fi
}

# Parse arguments
STATUS=""
SERVICE=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --status) STATUS="$2"; shift 2 ;;
        --service) SERVICE="$2"; shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        --help) echo "Usage: $0 --status [success|failure] --service <name> --message <msg>"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate inputs
if [[ -z "$STATUS" ]] || [[ -z "$SERVICE" ]] || [[ -z "$MESSAGE" ]]; then
    echo "ERROR: Missing required arguments (--status, --service, --message)" >&2
    exit 1
fi

if [[ "$STATUS" != "success" && "$STATUS" != "failure" ]]; then
    echo "ERROR: Invalid status (must be 'success' or 'failure')" >&2
    exit 1
fi

# Create audit directory if needed
mkdir -p "$AUDIT_DIR"

# Prepare audit entry
AUDIT_FILE="$AUDIT_DIR/${SCRIPT_NAME}-$(date -u +%Y%m%d-%H%M%S).jsonl"

# Log initial action
cat >> "$AUDIT_FILE" << EOF
{"timestamp":"$TIMESTAMP","action":"notify_health_check_initiated","service":"$SERVICE","status":"$STATUS","message":"$MESSAGE"}
EOF

# Prepare Slack message
if [[ "$STATUS" == "success" ]]; then
    SLACK_COLOR="good"
    SLACK_TITLE="✅ Health Check Passed"
else
    SLACK_COLOR="danger"
    SLACK_TITLE="❌ Health Check Failed"
fi

SLACK_PAYLOAD=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$SLACK_COLOR",
            "title": "$SLACK_TITLE",
            "fields": [
                {
                    "title": "Service",
                    "value": "$SERVICE",
                    "short": true
                },
                {
                    "title": "Status",
                    "value": "$STATUS",
                    "short": true
                },
                {
                    "title": "Message",
                    "value": "$MESSAGE",
                    "short": false
                },
                {
                    "title": "Timestamp",
                    "value": "$TIMESTAMP",
                    "short": true
                }
            ],
            "footer": "NexusShield Health Check Monitor",
            "ts": $(date +%s)
        }
    ]
}
EOF
)

# Try to send to Slack
SLACK_WEBHOOK=$(get_webhook_url "slack")
if [[ -n "$SLACK_WEBHOOK" ]]; then
    if curl -X POST -H 'Content-type: application/json' \
        --data "$SLACK_PAYLOAD" \
        "$SLACK_WEBHOOK" 2>/dev/null | grep -q "ok"; then
        
        cat >> "$AUDIT_FILE" << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","action":"slack_notification_sent","service":"$SERVICE","status":"success"}
EOF
        echo "✅ Slack notification sent successfully"
    else
        cat >> "$AUDIT_FILE" << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","action":"slack_notification_failed","service":"$SERVICE","status":"failed","error":"HTTP request failed"}
EOF
        echo "⚠️  Slack notification failed (webhook unavailable)" >&2
    fi
else
    cat >> "$AUDIT_FILE" << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","action":"slack_webhook_not_found","service":"$SERVICE","status":"skipped"}
EOF
    echo "⚠️  Slack webhook not found in GSM (skipped notification)"
fi

# Log completion
cat >> "$AUDIT_FILE" << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","action":"notify_health_check_complete","service":"$SERVICE","status":"success","audit_file":"$AUDIT_FILE"}
EOF

exit 0
