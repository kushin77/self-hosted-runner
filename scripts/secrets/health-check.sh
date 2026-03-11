#!/bin/bash

################################################################################
# Health Check & Alerting System
# Monitors orchestration logs for failures and sends alerts
# Operates independently (no GitHub Actions)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs"
HEALTH_CHECK_LOG="${LOGS_DIR}/health-check/check-$(date -u +%Y%m%dT%H%M%SZ).log"

# Alert configuration (customize as needed)
ALERT_EMAIL="${ALERT_EMAIL:-ops@example.com}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

mkdir -p "${LOGS_DIR}/health-check"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$HEALTH_CHECK_LOG"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$HEALTH_CHECK_LOG"; }
error() { echo -e "${RED}✗${NC} $*" | tee -a "$HEALTH_CHECK_LOG"; }
warning() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$HEALTH_CHECK_LOG"; }

################################################################################
# HEALTH CHECKS
################################################################################

check_last_orchestration() {
    log "Checking last orchestration run..."
    
    local latest_orch=$(find "${LOGS_DIR}/orchestration" -name "secret-orch-*.jsonl" -type f | sort -V | tail -1)
    
    if [ -z "$latest_orch" ]; then
        error "No orchestration logs found"
        return 1
    fi
    
    # Check if last run was recent (within last 24 hours)
    local mod_time=$(stat -c %Y "$latest_orch" 2>/dev/null || stat -f %m "$latest_orch" 2>/dev/null)
    local now=$(date +%s)
    local age=$((now - mod_time))
    local max_age=$((24 * 3600))
    
    if [ $age -gt $max_age ]; then
        warning "Last orchestration run is $(($age / 3600))h old (may have failed)"
        return 1
    fi
    
    success "Last orchestration run: $(($age / 3600))h ago"
    return 0
}

check_credential_presence() {
    log "Checking credential availability..."
    
    local missing=0
    local present=0
    
    for secret in azure-client-id azure-client-secret azure-tenant-id azure-subscription-id gcp-epic6-operator-sa-key; do
        if gcloud secrets versions access latest --secret="$secret" --project=nexusshield-prod >/dev/null 2>&1; then
            ((present++))
        else
            ((missing++))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        warning "Missing $missing secrets in GSM (present: $present)"
        return 1
    fi
    
    success "All credentials present in GSM ($present secrets)"
    return 0
}

check_keyvault_sync() {
    log "Checking Azure Key Vault sync..."
    
    if ! command -v az &>/dev/null; then
        warning "Azure CLI not available; skipping Key Vault check"
        return 0
    fi
    
    local vault_name="nsv298610"
    local secrets_in_vault=$(az keyvault secret list --vault-name "$vault_name" --query "length([])" -o tsv 2>/dev/null || echo "0")
    
    if [ "$secrets_in_vault" -lt 4 ]; then
        warning "Less than 4 secrets in Key Vault $vault_name (found: $secrets_in_vault)"
        return 1
    fi
    
    success "Key Vault $vault_name synchronized ($secrets_in_vault secrets)"
    return 0
}

check_mirror_audit_logs() {
    log "Checking mirror audit logs..."
    
    local latest_mirror=$(find "${LOGS_DIR}/secret-mirror" -name "mirror-*.jsonl" -type f | sort -V | tail -1)
    
    if [ -z "$latest_mirror" ]; then
        error "No mirror audit logs found"
        return 1
    fi
    
    # Check for successful mirrors
    # Count successes/failures robustly (normalize to integers)
    local successes
    local failures
    successes=$(grep -c '"status":"success"' "$latest_mirror" 2>/dev/null || true)
    failures=$(grep -c '"status":"failed"' "$latest_mirror" 2>/dev/null || true)

    # Ensure variables are plain integers (remove whitespace/newlines)
    successes=$(printf "%s" "$successes" | tr -d '[:space:]')
    failures=$(printf "%s" "$failures" | tr -d '[:space:]')

    successes=${successes:-0}
    failures=${failures:-0}

    if [ "$failures" -gt 0 ]; then
        warning "Mirror audit log shows failures: $successes success, $failures failed"
        return 1
    fi

    success "Mirror audit: $successes successful operations"
    return 0
}

################################################################################
# ALERTING
################################################################################

send_email_alert() {
    local subject="$1"
    local message="$2"
    
    if command -v mail &>/dev/null && [ -n "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
        log "Email alert sent to $ALERT_EMAIL"
    else
        warning "Mail command not available or ALERT_EMAIL not set"
    fi
}

send_slack_alert() {
    local message="$1"
    
    if [ -z "$SLACK_WEBHOOK" ]; then
        return 0
    fi
    
    local payload=$(cat <<EOF
{
  "text": "🚨 NexusShield Secret Management Alert",
  "attachments": [
    {
      "color": "danger",
      "text": "$message",
      "footer": "Hands-Off Orchestration | $(hostname)",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
    
    if curl -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1; then
        log "Slack alert sent"
    else
        warning "Failed to send Slack alert"
    fi
}

send_webhook_alert() {
    local message="$1"
    
    if [ -z "$ALERT_WEBHOOK" ]; then
        return 0
    fi
    
    local payload=$(cat <<EOF
{
  "event": "secret_management_health_check",
  "severity": "critical",
  "message": "$message",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)"
}
EOF
)
    
    if curl -X POST -H 'Content-type: application/json' --data "$payload" "$ALERT_WEBHOOK" >/dev/null 2>&1; then
        log "Webhook alert sent to $ALERT_WEBHOOK"
    else
        warning "Failed to send webhook alert"
    fi
}

################################################################################
# MAIN HEALTH CHECK
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║   Health Check: Hands-Off Secret Management       ║"
    echo "║   $(date -u +%Y-%m-%dT%H:%M:%SZ)                             "║
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    
    local issues=0
    
    # Run all health checks (continue on failures to collect all issues)
    check_last_orchestration || ((issues++))
    check_credential_presence || ((issues++))
    check_keyvault_sync || ((issues++))
    check_mirror_audit_logs || ((issues++))
    
    echo ""
    
    if [ $issues -eq 0 ]; then
        success "All health checks passed ✓"
        return 0
    else
        error "Health check failed: $issues issue(s) detected"
        
        # Send alerts if enabled
        local alert_msg="NexusShield Secret Management health check failed ($issues issues detected). Check logs at ${HEALTH_CHECK_LOG}"
        send_email_alert "🚨 Secret Management Alert" "$alert_msg"
        send_slack_alert "$alert_msg"
        send_webhook_alert "$alert_msg"
        
        return 1
    fi
}

main "$@"
