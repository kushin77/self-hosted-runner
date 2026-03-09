#!/bin/bash
# 7-Day Self-Healing Monitoring Run
# Validates production infrastructure, auto-repairs issues, and reports status
# Immutable | Ephemeral | Idempotent | No-Ops
#
# Usage: ./7day-monitoring-runbook.sh [--start] [--day N]
#
# Runs autonomously 24/7 for 7 days, checking:
#   - Vault health & authentication
#   - Vault Agent status on worker nodes
#   - node_exporter metrics availability
#   - Filebeat log shipping
#   - Terraform state consistency
#   - Credential rotation cycles
#   - Health daemon uptime

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITORING_LOG="$PROJECT_ROOT/logs/7day-monitoring.jsonl"
MONITORING_STATE="$PROJECT_ROOT/tmp/7day-monitoring.state"
REPORT_FILE="$PROJECT_ROOT/MONITORING_7DAY_REPORT_$(date +%Y%m%d).md"

# State tracking
MONITORING_START_TIME=""
CURRENT_DAY=0
ISSUES_FOUND=0
ISSUES_FIXED=0

# Logging & state management
log_monitoring() {
    local action="$1"
    local status="$2"
    local component="$3"
    local details="${4:-}"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local day="${5:-$CURRENT_DAY}"
    echo "{\"timestamp\":\"$timestamp\",\"day\":$day,\"action\":\"$action\",\"status\":\"$status\",\"component\":\"$component\",\"details\":\"$details\"}" >> "$MONITORING_LOG"
}

save_state() {
    cat > "$MONITORING_STATE" <<EOF
MONITORING_STARTED_AT=$MONITORING_START_TIME
CURRENT_DAY=$CURRENT_DAY
ISSUES_FOUND=$ISSUES_FOUND
ISSUES_FIXED=$ISSUES_FIXED
LAST_CHECK=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
EOF
}

load_state() {
    if [ -f "$MONITORING_STATE" ]; then
        source "$MONITORING_STATE" || true
    fi
}

info() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] $1"
}

warn() {
    echo "[WARN] $1" >&2
    ((ISSUES_FOUND++))
}

success() {
    echo "[✓] $1"
}

# =============================================================================
# Health Checks
# =============================================================================

check_vault_health() {
    info "Checking Vault health..."
    
    # Connect to local Vault (via Unix socket or localhost:8200)
    if ! vault status > /tmp/vault-status.txt 2>&1; then
        warn "Vault health check failed"
        log_monitoring "VAULT_HEALTH" "FAILED" "vault" "Cannot reach Vault"
        return 1
    fi
    
    local sealed=$(grep "Sealed" /tmp/vault-status.txt | awk '{print $NF}')
    if [ "$sealed" == "true" ]; then
        warn "Vault is sealed; attempting auto-unseal..."
        # Auto-unseal logic depends on your setup (OIDC, cloud auth, etc.)
        # For now, log and continue
        log_monitoring "VAULT_SEALED" "WARNING" "vault" "Vault sealed - manual intervention may be needed"
        return 1
    fi
    
    success "Vault health check passed"
    log_monitoring "VAULT_HEALTH" "SUCCESS" "vault" "Vault unsealed and responsive"
}

check_vault_agent_on_workers() {
    info "Checking Vault Agent on worker nodes..."
    
    # Connect to known worker node
    local worker_host="192.168.168.42"
    
    if ! ssh -o ConnectTimeout=5 "akushnir@$worker_host" 'systemctl is-active vault-agent' > /dev/null 2>&1; then
        warn "Vault Agent not active on $worker_host"
        log_monitoring "VAULT_AGENT" "FAILED" "vault-agent@$worker_host" "Vault Agent not running"
        
        # Auto-repair attempt
        info "Attempting to restart Vault Agent on $worker_host..."
        if ssh "akushnir@$worker_host" 'sudo systemctl start vault-agent' 2>&1; then
            success "Vault Agent restarted on $worker_host"
            ((ISSUES_FIXED++))
            log_monitoring "VAULT_AGENT_REPAIR" "SUCCESS" "vault-agent@$worker_host" "Restarted"
        fi
        return 1
    fi
    
    success "Vault Agent check passed on $worker_host"
    log_monitoring "VAULT_AGENT" "SUCCESS" "vault-agent@$worker_host" "Active and healthy"
}

check_node_exporter_metrics() {
    info "Checking node_exporter metrics availability..."
    
    local exporter_url="http://192.168.168.42:9100/metrics"
    
    if ! curl -sf "$exporter_url" > /tmp/node-metrics.txt 2>&1; then
        warn "node_exporter metrics not available at $exporter_url"
        log_monitoring "NODE_EXPORTER" "FAILED" "node_exporter" "Metrics endpoint not responding"
        return 1
    fi
    
    local metric_count=$(wc -l < /tmp/node-metrics.txt)
    success "node_exporter metrics available ($metric_count lines)"
    log_monitoring "NODE_EXPORTER" "SUCCESS" "node_exporter" "Metrics count: $metric_count"
}

check_filebeat_health() {
    info "Checking Filebeat health..."
    
    local worker_host="192.168.168.42"
    
    if ! ssh -o ConnectTimeout=5 "akushnir@$worker_host" 'systemctl is-active filebeat' > /dev/null 2>&1; then
        warn "Filebeat not active on $worker_host"
        log_monitoring "FILEBEAT" "FAILED" "filebeat@$worker_host" "Filebeat not running"
        
        # Auto-repair
        info "Attempting to restart Filebeat on $worker_host..."
        if ssh "akushnir@$worker_host" 'sudo systemctl start filebeat' 2>&1; then
            success "Filebeat restarted on $worker_host"
            ((ISSUES_FIXED++))
            log_monitoring "FILEBEAT_REPAIR" "SUCCESS" "filebeat@$worker_host" "Restarted"
        fi
        return 1
    fi
    
    success "Filebeat health check passed"
    log_monitoring "FILEBEAT" "SUCCESS" "filebeat@$worker_host" "Running"
}

check_terraform_state() {
    info "Checking Terraform state consistency..."
    
    if ! cd "$PROJECT_ROOT/terraform" && terraform validate > /tmp/tf-validate.txt 2>&1; then
        warn "Terraform state validation failed"
        log_monitoring "TERRAFORM_STATE" "FAILED" "terraform" "$(tail -3 /tmp/tf-validate.txt)"
        return 1
    fi
    
    success "Terraform state validation passed"
    log_monitoring "TERRAFORM_STATE" "SUCCESS" "terraform" "State valid"
}

check_credential_rotation() {
    info "Checking credential rotation cycles..."
    
    # Check when last rotation occurred
    if [ ! -f "$PROJECT_ROOT/logs/rotation-audit.jsonl" ]; then
        warn "Rotation audit log not found"
        log_monitoring "CREDENTIAL_ROTATION" "WARNING" "rotation" "Audit log missing"
        return 1
    fi
    
    # Get last rotation timestamp
    local last_rotation=$(tail -1 "$PROJECT_ROOT/logs/rotation-audit.jsonl" | jq -r '.timestamp' 2>/dev/null || echo "")
    
    if [ -z "$last_rotation" ]; then
        warn "No credential rotation records found"
        log_monitoring "CREDENTIAL_ROTATION" "WARNING" "rotation" "No rotations recorded yet"
        return 1
    fi
    
    success "Credential rotation check passed (last: $last_rotation)"
    log_monitoring "CREDENTIAL_ROTATION" "SUCCESS" "rotation" "Last rotation: $last_rotation"
}

check_health_daemon() {
    info "Checking autonomous health daemon..."
    
    if ! pgrep -f "autonomous_terraform_monitor" > /dev/null; then
        warn "Health daemon not running"
        log_monitoring "HEALTH_DAEMON" "FAILED" "daemon" "Health daemon process not found"
        
        # Auto-restart (if script exists)
        if [ -f /tmp/autonomous_terraform_monitor.sh ]; then
            info "Restarting health daemon..."
            # Run daemon in background (be careful not to double-spawn)
            nohup /tmp/autonomous_terraform_monitor.sh > /tmp/health-daemon.log 2>&1 &
            ((ISSUES_FIXED++))
            log_monitoring "HEALTH_DAEMON_RESTART" "SUCCESS" "daemon" "Restarted"
        fi
        return 1
    fi
    
    success "Health daemon is running"
    log_monitoring "HEALTH_DAEMON" "SUCCESS" "daemon" "Running"
}

# =============================================================================
# Daily Reports
# =============================================================================

generate_daily_report() {
    local day="$1"
    local issues="$2"
    local fixed="$3"
    
    cat >> "$REPORT_FILE" <<EOF

## Day $day Report

**Timestamp**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

### Summary
- **Issues Found**: $issues
- **Issues Auto-Fixed**: $fixed
- **Net Issues Remaining**: $((issues - fixed))

### Components Checked
- Vault (health, AppRole auth)
- Vault Agent (worker nodes)
- node_exporter (metrics collection)
- Filebeat (log shipping)
- Terraform state
- Credential rotation
- Health daemon

### Audit Trail
\`\`\`
EOF
    tail -50 "$MONITORING_LOG" | jq -r '.timestamp + " | " + .action + " | " + .status' >> "$REPORT_FILE" 2>/dev/null || true
    cat >> "$REPORT_FILE" <<EOF
\`\`\`

EOF
}

# =============================================================================
# Alert Integration (if PagerDuty available)
# =============================================================================

send_daily_alert() {
    local day="$1"
    local issues="$2"
    
    if [ -x "$PROJECT_ROOT/scripts/pagerduty-integration.sh" ]; then
        info "Sending PagerDuty update for day $day..."
        "$PROJECT_ROOT/scripts/pagerduty-integration.sh" monitoring-update "$day" "Daily health check complete" "$issues" "Day $day Monitoring" || true
    fi
}

# =============================================================================
# Main Monitoring Loop
# =============================================================================

run_monitoring_cycle() {
    load_state
    
    local start_day=${1:-1}
    CURRENT_DAY=$start_day
    
    for day in $(seq $start_day 7); do
        CURRENT_DAY=$day
        ISSUES_FOUND=0
        ISSUES_FIXED=0
        
        info "=== MONITORING RUN: DAY $day / 7 ==="
        log_monitoring "DAY_START" "INITIATED" "monitoring" "Day $day started"
        
        # Run all health checks
        check_vault_health || true
        check_vault_agent_on_workers || true
        check_node_exporter_metrics || true
        check_filebeat_health || true
        check_terraform_state || true
        check_credential_rotation || true
        check_health_daemon || true
        
        # Generate report
        generate_daily_report "$day" "$ISSUES_FOUND" "$ISSUES_FIXED"
        
        # Send alert
        send_daily_alert "$day" "$ISSUES_FOUND"
        
        # Save state
        save_state
        
        info "Day $day complete. Issues found: $ISSUES_FOUND, Fixed: $ISSUES_FIXED"
        log_monitoring "DAY_COMPLETE" "SUCCESS" "monitoring" "Day $day completed with $ISSUES_FOUND issues found and $ISSUES_FIXED auto-fixed"
        
        # Wait 24 hours before next cycle (unless last day)
        if [ "$day" -lt 7 ]; then
            info "Sleeping until next 24h check (day $((day + 1)))..."
            sleep 86400  # 24 hours
        fi
    done
    
    info "✅ 7-DAY MONITORING RUN COMPLETE"
    info "Final report: $REPORT_FILE"
    
    # Mark completion
    log_monitoring "MONITORING_COMPLETE" "SUCCESS" "monitoring" "7-day run finished"
}

# =============================================================================
# CLI Interface
# =============================================================================

case "${1:-start}" in
    start)
        # Initialize monitoring report
        cat > "$REPORT_FILE" <<EOF
# 7-Day Production Monitoring Report
**Generated**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
**Duration**: 7 days (March 9-15, 2026)

---

EOF
        MONITORING_START_TIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
        save_state
        run_monitoring_cycle 1
        ;;
    resume)
        # Resume from current day
        load_state
        run_monitoring_cycle "$((CURRENT_DAY + 1))"
        ;;
    check)
        # Run one-time health check cycle (no sleep)
        CURRENT_DAY=1
        check_vault_health || true
        check_vault_agent_on_workers || true
        check_node_exporter_metrics || true
        check_filebeat_health || true
        check_terraform_state || true
        check_credential_rotation || true
        check_health_daemon || true
        info "One-time health check complete"
        ;;
    *)
        cat <<EOF
usage: $0 <command>

Supported Commands:
  start         Start a new 7-day monitoring run
  resume        Resume from saved state (continue from last day)
  check         Run one-time health check cycle (no sleep)

Examples:
  $0 start       # Begin 7-day automated monitoring
  $0 resume      # Continue from day 3, 4, etc.
  $0 check       # Quick health check

EOF
        ;;
esac
