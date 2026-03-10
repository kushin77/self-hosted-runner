#!/bin/bash
# PagerDuty Integration for Deployment Automation
# Sends incident alerts, escalations, and recovery notifications
# Immutable | Ephemeral | Idempotent | No-Ops
#
# Prerequisites:
#   - PAGERDUTY_API_KEY env var set (or in Vault at secret/data/pagerduty/api-key)
#   - PAGERDUTY_SERVICE_ID env var set (or in Vault at secret/data/pagerduty/service-id)
#   - PAGERDUTY_ESCALATION_POLICY_ID (optional, for high-severity incidents)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_LOG="$PROJECT_ROOT/logs/pagerduty-audit.jsonl"

# Retrieve credentials from Vault or environment
PD_API_KEY="${PAGERDUTY_API_KEY:-}"
PD_SERVICE_ID="${PAGERDUTY_SERVICE_ID:-}"
PD_ESCALATION_POLICY="${PAGERDUTY_ESCALATION_POLICY_ID:-}"

# If credentials not in env, attempt to retrieve from Vault
if [ -z "$PD_API_KEY" ]; then
    if command -v vault &> /dev/null && vault status > /dev/null 2>&1; then
        PD_API_KEY=$(vault kv get -field=api_key secret/pagerduty 2>/dev/null || echo "")
    fi
fi

if [ -z "$PD_SERVICE_ID" ]; then
    if command -v vault &> /dev/null && vault status > /dev/null 2>&1; then
        PD_SERVICE_ID=$(vault kv get -field=service_id secret/pagerduty 2>/dev/null || echo "")
    fi
fi

# Logging
log_audit() {
    local action="$1"
    local severity="$2"
    local message="$3"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local incident_id="${4:-null}"
    echo "{\"timestamp\":\"$timestamp\",\"action\":\"$action\",\"severity\":\"$severity\",\"message\":\"$message\",\"incident_id\":$incident_id}" >> "$AUDIT_LOG"
}

info() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] $1"
}

warn() {
    echo "[WARN] $1" >&2
}

# =============================================================================
# PagerDuty API: Create Incident
# =============================================================================

pd_create_incident() {
    local title="$1"
    local severity="${2:-warning}"  # critical, error, warning, info
    local body="$3"
    local urgency="${4:-high}"  # high, low
    
    if [ -z "$PD_API_KEY" ] || [ -z "$PD_SERVICE_ID" ]; then
        warn "PagerDuty credentials not configured; skipping incident creation"
        log_audit "PD_CREATE_SKIPPED" "$severity" "Credentials missing"
        return 1
    fi
    
    info "Creating PagerDuty incident: $title (severity: $severity)"
    
    local payload=$(cat <<EOF
{
  "incident": {
    "type": "incident",
    "title": "$title",
    "service": {
      "id": "$PD_SERVICE_ID",
      "type": "service_reference"
    },
    "urgency": "$urgency",
    "body": {
      "type": "incident_body",
      "details": "$body"
    }
  }
}
EOF
)
    
    local response
    response=$(curl -s -X POST https://api.pagerduty.com/incidents \
        -H "Authorization: Token token=$PD_API_KEY" \
        -H "Content-Type: application/json" \
        -H "From: deployment-automation@example.com" \
        -d "$payload")
    
    local incident_id=$(echo "$response" | jq -r '.incident.incident_number // empty' 2>/dev/null || echo "")
    
    if [ -n "$incident_id" ]; then
        info "✅ PagerDuty incident created: #$incident_id"
        log_audit "PD_INCIDENT_CREATED" "$severity" "$title" "$incident_id"
        echo "$incident_id"
    else
        warn "Failed to create PagerDuty incident. Response: $response"
        log_audit "PD_INCIDENT_FAILED" "$severity" "$title"
        return 1
    fi
}

# =============================================================================
# PagerDuty API: Resolve Incident
# =============================================================================

pd_resolve_incident() {
    local incident_id="$1"
    local resolution_note="${2:-Resolved by automation}"
    
    if [ -z "$PD_API_KEY" ]; then
        warn "PagerDuty API key not configured; skipping incident resolution"
        return 1
    fi
    
    info "Resolving PagerDuty incident: $incident_id"
    
    local payload=$(cat <<EOF
{
  "incidents": [
    {
      "id": "$incident_id",
      "type": "incident_reference",
      "status": "resolved"
    }
  ]
}
EOF
)
    
    local response
    response=$(curl -s -X PUT https://api.pagerduty.com/incidents \
        -H "Authorization: Token token=$PD_API_KEY" \
        -H "Content-Type: application/json" \
        -H "From: deployment-automation@example.com" \
        -d "$payload")
    
    if echo "$response" | jq -e '.incidents[0].status == "resolved"' > /dev/null 2>&1; then
        info "✅ PagerDuty incident $incident_id resolved"
        log_audit "PD_INCIDENT_RESOLVED" "info" "Resolved: $resolution_note" "$incident_id"
    else
        warn "Failed to resolve incident. Response: $response"
        log_audit "PD_RESOLVE_FAILED" "warning" "Failed" "$incident_id"
    fi
}

# =============================================================================
# Alert: Credential Rotation Failure
# =============================================================================

alert_credential_rotation_failure() {
    local error_msg="$1"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    pd_create_incident \
        "🚨 Credential Rotation Failed" \
        "critical" \
        "Automated credential rotation failed at $timestamp. Error: $error_msg. Manual intervention may be required. Check logs at: $PROJECT_ROOT/logs/rotation-audit.jsonl" \
        "high"
}

# =============================================================================
# Alert: Terraform Apply Failure
# =============================================================================

alert_terraform_apply_failure() {
    local tf_error="$1"
    local exit_code="${2:-unknown}"
    
    pd_create_incident \
        "🚨 Terraform Apply Failed (Exit Code: $exit_code)" \
        "critical" \
        "Automated Terraform apply failed. Error: $tf_error. Review: $PROJECT_ROOT/deploy_apply_run.log" \
        "high"
}

# =============================================================================
# Alert: Health Check Failure
# =============================================================================

alert_health_check_failure() {
    local component="$1"
    local status_msg="$2"
    
    pd_create_incident \
        "⚠️  Health Check Failed: $component" \
        "error" \
        "Component $component failed health check. Status: $status_msg" \
        "high"
}

# =============================================================================
# Alert: Key Revocation Complete
# =============================================================================

alert_key_revocation_complete() {
    local keys_revoked="$1"
    local backends="${2:-GSM/Vault/AWS}"
    
    local incident_id
    incident_id=$(pd_create_incident \
        "✅ Key Revocation Completed" \
        "info" \
        "Successfully revoked $keys_revoked keys from $backends. Audit trail: $PROJECT_ROOT/logs/revocation-audit.jsonl" \
        "low")
    
    if [ -n "$incident_id" ]; then
        pd_resolve_incident "$incident_id" "Revocation complete - resolving automatically"
    fi
}

# =============================================================================
# Alert: Monitoring Run Started
# =============================================================================

alert_monitoring_run_started() {
    local duration="${1:-7 days}"
    local components="${2:-All systems}"
    
    local incident_id
    incident_id=$(pd_create_incident \
        "📊 7-Day Automated Monitoring Run Started" \
        "info" \
        "Monitoring automation started for $duration. Monitoring: $components. Updates will be sent at day 1, 3, 5, and 7." \
        "low")
    
    echo "$incident_id"
}

# =============================================================================
# Alert: Monitoring Run Update
# =============================================================================

alert_monitoring_run_update() {
    local day="$1"
    local status="$2"
    local issues_found="${3:-0}"
    local incident_title="$4"
    
    local severity="info"
    if [ "$issues_found" -gt 0 ]; then
        severity="warning"
    fi
    
    pd_create_incident \
        "📊 7-Day Monitoring - Day $day Update" \
        "$severity" \
        "Day $day Status: $status. Issues found: $issues_found. Incident title: $incident_title" \
        "low"
}

# =============================================================================
# CLI Interface
# =============================================================================

case "${1:-help}" in
    create-incident)
        pd_create_incident "${2:-Incident}" "${3:-warning}" "${4:-No details provided}"
        ;;
    resolve-incident)
        pd_resolve_incident "${2:-}" "${3:-Resolved}"
        ;;
    rotation-failure)
        alert_credential_rotation_failure "${2:-Unknown error}"
        ;;
    terraform-failure)
        alert_terraform_apply_failure "${2:-Unknown error}" "${3:-unknown}"
        ;;
    health-check-failure)
        alert_health_check_failure "${2:-Component}" "${3:-No details}"
        ;;
    revocation-complete)
        alert_key_revocation_complete "${2:-0}" "${3:-GSM/Vault/AWS}"
        ;;
    monitoring-started)
        alert_monitoring_run_started "${2:-7 days}" "${3:-All systems}"
        ;;
    monitoring-update)
        alert_monitoring_run_update "${2:-1}" "${3:-Unknown}" "${4:-0}" "${5:-N/A}"
        ;;
    *)
        cat <<EOF
usage: $0 <command> [args...]

Supported Commands:
  create-incident <title> [severity] [body]      Create a PagerDuty incident
  resolve-incident <incident_id> [note]          Resolve an incident
  rotation-failure <error>                        Alert credential rotation failure
  terraform-failure <error> [exit_code]          Alert Terraform apply failure
  health-check-failure <component> [status]      Alert health check failure
  revocation-complete <keys_count> [backends]    Alert successful key revocation
  monitoring-started [duration] [components]     Start monitoring run alert
  monitoring-update <day> <status> [issues]      Send monitoring update

Examples:
  $0 rotation-failure "GSM connection timeout"
  $0 terraform-failure "timeout: operation took 180 seconds" "124"
  $0 revocation-complete 12 "GSM/Vault/AWS"
  $0 monitoring-started "7 days" "Vault,node_exporter,Filebeat"

EOF
        ;;
esac
