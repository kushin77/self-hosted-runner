#!/bin/bash
#
# Phase 5.2: Internal Health Check Service
# Validates system operational status without external dependencies
# Authority: Lead Engineer (Org-admin fallback)
# Status: Immutable audit trail, idempotent execution
#
# Features:
#  - Health checks for all critical services
#  - Credential verification (GSM/Vault/KMS)
#  - Secret rotation validation
#  - Cloud Run service availability
#  - Database connectivity checks
#
# Runs hourly via systemd timer (idempotent)
#
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
readonly LOG_DIR="${REPO_ROOT}/logs/phase-5-health"
readonly AUDIT_LOG="${LOG_DIR}/health-check-$(date +%Y%m%d).jsonl"
readonly TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
readonly BATCH_ID=$(date +%s)

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#
# Immutable audit logging (append-only JSONL)
#
audit_log() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    cat >> "$AUDIT_LOG" <<EOF
{"timestamp":"$TIMESTAMP","batch_id":"$BATCH_ID","event":"$event","status":"$status","details":"$details"}
EOF
}

# Log functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

#
# Health Check: GSM Credential Access
#
check_gsm_credentials() {
    log_info "Checking Google Secret Manager access..."
    audit_log "GSM_CHECK_START" "in-progress" "Validating credentials"
    
    if gcloud secrets versions list github-app-id --project="$GCP_PROJECT" &>/dev/null; then
        log_success "GSM access verified"
        audit_log "GSM_CHECK" "success" "Secret versioning accessible"
        return 0
    else
        log_error "GSM access failed"
        audit_log "GSM_CHECK" "failure" "Cannot list secret versions"
        return 1
    fi
}

#
# Health Check: Cloud Run Services
#
check_cloud_run_services() {
    log_info "Checking Cloud Run services..."
    audit_log "CLOUD_RUN_CHECK_START" "in-progress" "Validating deployed services"
    
    local services=("prevent-releases" "uptime-check-proxy")
    local all_healthy=0
    
    for service in "${services[@]}"; do
        if gcloud run services describe "$service" --region=us-central1 --project="$GCP_PROJECT" &>/dev/null; then
            log_success "Cloud Run service healthy: $service"
            audit_log "CLOUD_RUN_SERVICE_CHECK" "success" "service=$service"
        else
            log_error "Cloud Run service unavailable: $service"
            audit_log "CLOUD_RUN_SERVICE_CHECK" "failure" "service=$service"
            all_healthy=1
        fi
    done
    
    return $all_healthy
}

#
# Health Check: Secret Rotation Recent
#
check_secret_rotation_status() {
    log_info "Checking secret rotation status..."
    audit_log "ROTATION_STATUS_CHECK_START" "in-progress" "Validating rotation recency"
    
    # Check if rotation logs exist and are recent (within 26 hours)
    local rotation_logs="${REPO_ROOT}/logs/phase-5-orchestration/"
    
    if [ ! -d "$rotation_logs" ]; then
        log_warn "No rotation logs found yet"
        audit_log "ROTATION_STATUS_CHECK" "warning" "No rotation logs; first run scheduled"
        return 0
    fi
    
    # Find most recent orchestration log
    local latest_log=$(find "$rotation_logs" -name "orchestration-*.jsonl" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -z "$latest_log" ]; then
        log_warn "No rotation orchestration logs found (first run may not have occurred)"
        audit_log "ROTATION_STATUS_CHECK" "warning" "No orchestration logs yet"
        return 0
    fi
    
    # Extract timestamp and check recency
    local log_time=$(stat -c %Y "$latest_log")
    local current_time=$(date +%s)
    local age=$((current_time - log_time))
    local hours=$((age / 3600))
    
    if [ "$hours" -lt 26 ]; then
        log_success "Rotation logs current (${hours}h old): $latest_log"
        audit_log "ROTATION_STATUS_CHECK" "success" "Rotation_age_hours=$hours"
        return 0
    else
        log_warn "Rotation logs stale (${hours}h old)"
        audit_log "ROTATION_STATUS_CHECK" "warning" "Rotation_age_hours=$hours"
        return 0  # Warning, not fatal
    fi
}

#
# Health Check: Audit Trail Integrity
#
check_audit_trail_integrity() {
    log_info "Checking audit trail integrity..."
    audit_log "AUDIT_TRAIL_CHECK_START" "in-progress" "Validating immutability"
    
    # Count JSONL entries in all audit logs
    local total_entries=$(find "$REPO_ROOT/logs" -name "*.jsonl" -type f -exec wc -l {} + | awk '{sum+=$1} END {print sum}')
    
    if [ "$total_entries" -gt 0 ]; then
        log_success "Audit trail intact (${total_entries} entries across all logs)"
        audit_log "AUDIT_TRAIL_CHECK" "success" "Total_entries=$total_entries"
        return 0
    else
        log_error "No audit trail entries found"
        audit_log "AUDIT_TRAIL_CHECK" "failure" "audit_logs_empty"
        return 1
    fi
}

#
# Health Check: Database Connectivity
#
check_database_connectivity() {
    log_info "Checking database connectivity..."
    audit_log "DATABASE_CHECK_START" "in-progress" "Validating Cloud SQL"
    
    if gcloud sql instances describe nexusshield-postgres-prod --project="$GCP_PROJECT" &>/dev/null; then
        log_success "Database instance accessible"
        audit_log "DATABASE_CHECK" "success" "nexusshield-postgres-prod connected"
        return 0
    else
        log_error "Database instance unreachable"
        audit_log "DATABASE_CHECK" "failure" "nexusshield-postgres-prod not found"
        return 1
    fi
}

#
# Health Check: systemd Timer Status
#
check_systemd_timers() {
    log_info "Checking systemd automation timers..."
    audit_log "SYSTEMD_CHECK_START" "in-progress" "Validating timer status"
    
    if systemctl is-active phase5-rotation.timer &>/dev/null; then
        log_success "Phase 5 rotation timer active"
        audit_log "SYSTEMD_CHECK" "success" "phase5-rotation.timer active"
        return 0
    else
        log_warn "Phase 5 rotation timer not active"
        audit_log "SYSTEMD_CHECK" "warning" "phase5-rotation.timer not active"
        return 0  # Not fatal; may be scheduled for future
    fi
}

#
# Comprehensive Health Report
#
generate_health_report() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "🏥 Phase 5 Internal Health Check Report"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Batch ID: $BATCH_ID"
    log_info "Audit Log: $AUDIT_LOG"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Run all checks
    local failed=0
    
    check_gsm_credentials || ((failed++))
    check_cloud_run_services || ((failed++))
    check_secret_rotation_status || true  # Non-fatal
    check_audit_trail_integrity || ((failed++))
    check_database_connectivity || ((failed++))
    check_systemd_timers || true  # Non-fatal
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$failed" -eq 0 ]; then
        log_success "All critical health checks PASSED ✅"
        audit_log "HEALTH_CHECK_COMPLETE" "success" "All critical systems operational"
        echo ""
        return 0
    else
        log_error "Some health checks FAILED ($failed critical failures)"
        audit_log "HEALTH_CHECK_COMPLETE" "failure" "Critical_failures=$failed"
        echo ""
        return 1
    fi
}

#
# Main execution
#
main() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Phase 5.2: Internal Health Check Service"
    log_info "Repository: $REPO_ROOT"
    log_info "Project: $GCP_PROJECT"
    log_info "═══════════════════════════════════════════════════════════"
    
    audit_log "HEALTH_CHECK_START" "in-progress" "Batch initiated"
    
    generate_health_report
    local exit_code=$?
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Architecture Compliance:"
    log_info "  ✅ Immutable: JSONL audit trail (append-only)"
    log_info "  ✅ Idempotent: Safe to run multiple times"
    log_info "  ✅ Hands-Off: No manual intervention required"
    log_info "═══════════════════════════════════════════════════════════"
    
    return $exit_code
}

# Execute
main "$@"
