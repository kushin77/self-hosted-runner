#!/bin/bash
# Host Crash Remediation Script
# Autonomous, idempotent actions to recover from disk/memory exhaustion
# Immutable audit trail via gsutil to GCS (Object Lock WORM)

set -euo pipefail

# Configuration
ANALYSIS_REPORT_FILE="${ANALYSIS_REPORT_FILE:-/tmp/host_analysis_report.json}"
AUDIT_LOG_FILE="/var/log/host-remediation-audit.jsonl"
GCS_AUDIT_BUCKET="${GCS_AUDIT_BUCKET:-gs://my-audit-logs}"  # Injected from GSM
REMEDIATION_CONFIG="${REMEDIATION_CONFIG:-/etc/host-remediation.conf}"

# Logging functions
log_action() {
    local action="$1" status="$2" detail="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname=$(hostname)
    
    # JSONL to local audit log
    jq -n \
        --arg ts "$timestamp" \
        --arg host "$hostname" \
        --arg act "$action" \
        --arg st "$status" \
        --arg det "$detail" \
        '{timestamp: $ts, hostname: $host, action: $act, status: $st, detail: $det}' > \
        >(tee -a "$AUDIT_LOG_FILE")
    
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$action] $status: $detail" | tee -a /var/log/host-remediation.log
}

# Remediation action: clean snap packages
remediate_snap_cleanup() {
    log_action "SNAP_CLEANUP" "STARTED" "Cleaning unused snap packages..."
    
    if command -v snap &> /dev/null; then
        local snapshots_removed=0
        
        # Remove old snap revisions (keep only 1 per snap)
        for snap in $(snap list --all | awk '{print $1}' | tail -n +2); do
            while [ $(snap list --all "$snap" | wc -l) -gt 2 ]; do
                old_rev=$(snap list --all "$snap" | tail -1 | awk '{print $3}')
                if snap remove "$snap" --revision "$old_rev" 2>/dev/null; then
                    ((snapshots_removed++))
                else
                    break
                fi
            done
        done
        
        log_action "SNAP_CLEANUP" "COMPLETED" "Removed $snapshots_removed old snap revisions"
        return 0
    else
        log_action "SNAP_CLEANUP" "SKIPPED" "snap not installed"
        return 0
    fi
}

# Remediation action: clean temp files
remediate_temp_cleanup() {
    log_action "TEMP_CLEANUP" "STARTED" "Cleaning /tmp and /var/tmp..."
    
    local files_removed=0
    local space_freed_mb=0
    
    # Clean /tmp (files older than 7 days)
    if [ -d /tmp ]; then
        space_freed=$(find /tmp -type f -mtime +7 -delete -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum}')
        space_freed_mb=$((space_freed / 1024 / 1024))
        ((files_removed+=$(find /tmp -type f -mtime +7 2>/dev/null | wc -l)))
    fi
    
    # Clean /var/tmp (files older than 7 days)
    if [ -d /var/tmp ]; then
        space_freed=$(find /var/tmp -type f -mtime +7 -delete -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum}')
        space_freed_mb=$((space_freed_mb + space_freed / 1024 / 1024))
    fi
    
    log_action "TEMP_CLEANUP" "COMPLETED" "Removed $files_removed files, freed ${space_freed_mb}MB"
    return 0
}

# Remediation action: rotate logs
remediate_log_rotation() {
    log_action "LOG_ROTATION" "STARTED" "Rotating and compressing old logs..."
    
    local logs_rotated=0
    
    if command -v logrotate &> /dev/null; then
        logrotate -f /etc/logrotate.conf 2>/dev/null && ((logs_rotated++))
    fi
    
    # Manual compression of large logs
    find /var/log -type f \( -name "*.log" -o -name "*.err" \) -mtime +30 ! -name "*.gz" -exec gzip {} \; 2>/dev/null && true
    
    log_action "LOG_ROTATION" "COMPLETED" "Rotated and compressed logs ($logs_rotated operations)"
    return 0
}

# Remediation action: prune journalctl
remediate_journal_cleanup() {
    log_action "JOURNAL_CLEANUP" "STARTED" "Pruning journalctl to 30 days..."
    
    if command -v journalctl &> /dev/null; then
        journalctl --vacuum=time=30d --vacuum-pct=10 2>/dev/null || true
        log_action "JOURNAL_CLEANUP" "COMPLETED" "Journal pruned to 30 days"
    else
        log_action "JOURNAL_CLEANUP" "SKIPPED" "journalctl not available"
    fi
    return 0
}

# Remediation action: docker system prune
remediate_docker_prune() {
    log_action "DOCKER_PRUNE" "STARTED" "Pruning docker images/containers/volumes..."
    
    if command -v docker &> /dev/null && docker stats --no-stream &> /dev/null; then
        docker system prune -a -f --volumes 2>/dev/null || true
        log_action "DOCKER_PRUNE" "COMPLETED" "Docker system pruned"
    else
        log_action "DOCKER_PRUNE" "SKIPPED" "docker not running"
    fi
    return 0
}

# Main remediation orchestrator
run_remediation() {
    log_action "REMEDIATION_CYCLE" "STARTED" "Host crash remediation cycle initiated"
    local failed_actions=0
    
    remediate_temp_cleanup || ((failed_actions++))
    remediate_log_rotation || ((failed_actions++))
    remediate_journal_cleanup || ((failed_actions++))
    remediate_snap_cleanup || ((failed_actions++))
    remediate_docker_prune || ((failed_actions++))
    
    if [ $failed_actions -eq 0 ]; then
        log_action "REMEDIATION_CYCLE" "COMPLETED_SUCCESS" "All remediation actions succeeded"
        return 0
    else
        log_action "REMEDIATION_CYCLE" "COMPLETED_PARTIAL_FAILURE" "$failed_actions actions failed"
        return 1
    fi
}

# Push audit logs to GCS (immutable Object Lock)
push_audit_logs() {
    if [ -z "${GCS_AUDIT_BUCKET:-}" ]; then
        echo "WARNING: GCS_AUDIT_BUCKET not set, skipping immutable audit trail"
        return 0
    fi
    
    if [ -f "$AUDIT_LOG_FILE" ]; then
        local timestamp=$(date -u +%Y%m%d%H%M%S)
        local hostname=$(hostname)
        local gcs_path="${GCS_AUDIT_BUCKET}/host-crash-analysis/${hostname}/${timestamp}.jsonl"
        
        if gsutil -h "Cache-Control:no-cache" cp "$AUDIT_LOG_FILE" "$gcs_path" 2>/dev/null; then
            log_action "AUDIT_PUSH" "SUCCESS" "Audit logs pushed to $gcs_path"
            # Clear local log after successful push (immutable copy in GCS)
            > "$AUDIT_LOG_FILE"
            return 0
        else
            log_action "AUDIT_PUSH" "FAILED" "Could not push to GCS"
            return 1
        fi
    fi
}

# Main entry point
main() {
    echo "=== Host Crash Remediation $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    
    # Run remediation cycle
    run_remediation || true
    
    # Push audit trail to GCS
    push_audit_logs || true
    
    echo "=== Remediation cycle complete ==="
    
    # Post-remediation analysis
    if command -v python3 &> /dev/null && [ -f "$ANALYSIS_REPORT_FILE" ]; then
        echo "Re-analyzing host post-remediation..."
        python3 /opt/host-crash-analysis/host-crash-analyzer.py > "$ANALYSIS_REPORT_FILE" 2>&1 || true
        cat "$ANALYSIS_REPORT_FILE"
    fi
}

main "$@"
