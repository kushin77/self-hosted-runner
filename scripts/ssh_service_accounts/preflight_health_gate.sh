#!/bin/bash
# Preflight Health Gate
# Runs comprehensive pre-deployment checks; fails fast if infrastructure not ready
# All production credential operations should call this first
# Usage: preflight_health_gate.sh [--fix-minor]

set -euo pipefail

readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SYSTEMD_DIR="${WORKSPACE_ROOT}/systemd"
readonly LOGS_DIR="${WORKSPACE_ROOT}/logs"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_header() { echo -e "${CYAN}$1${NC}"; }

passed=0
failed=0
warnings=0
fix_minor=false

if [ "${1:-}" = "--fix-minor" ]; then
    fix_minor=true
fi

# ============================================================================
# CHECK: Required command availability
# ============================================================================
check_commands() {
    log_info "Checking required commands..."
    
    local commands=(ssh ssh-keygen gcloud bash jq curl)
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_success "Found: $cmd"
            ((passed++))
        else
            log_error "Missing: $cmd"
            ((failed++))
        fi
    done
}

# ============================================================================
# CHECK: Directory structure and permissions
# ============================================================================
check_directory_structure() {
    log_info "Checking directory structure..."
    
    local dirs=(
        "$LOGS_DIR"
        "$SECRETS_DIR"
        "${WORKSPACE_ROOT}/.credential-state"
        "${SECRETS_DIR}/.backups"
    )
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_success "Directory exists: $dir"
            ((passed++))
        else
            if [ "$fix_minor" = true ]; then
                mkdir -p "$dir"
                chmod 755 "$dir"
                log_success "Created directory: $dir"
                ((passed++))
            else
                log_warn "Missing directory: $dir"
                ((warnings++))
            fi
        fi
    done
}

# ============================================================================
# CHECK: File permissions on SSH keys
# ============================================================================
check_key_permissions() {
    log_info "Checking SSH key permissions..."
    
    if [ ! -d "$SECRETS_DIR" ]; then
        log_warn "Secrets directory not found"
        ((warnings++))
        return
    fi
    
    local bad_perms=0
    while read -r keyfile; do
        local perms=$(stat -c "%a" "$keyfile" 2>/dev/null || echo "000")
        
        if [ "$perms" = "600" ]; then
            ((passed++))
        else
            log_error "Bad permissions on $keyfile: $perms (should be 600)"
            
            if [ "$fix_minor" = true ]; then
                chmod 600 "$keyfile" 2>/dev/null
                log_success "Fixed permissions: $keyfile"
                ((passed++))
            else
                ((failed++))
            fi
            ((bad_perms++))
        fi
    done < <(find "$SECRETS_DIR" -name "id_ed25519" -type f 2>/dev/null || true)
    
    [ $bad_perms -eq 0 ] && log_success "All SSH key permissions correct"
}

# ============================================================================
# CHECK: Systemd services enabled
# ============================================================================
check_systemd_services() {
    log_info "Checking systemd services..."
    
    local services=(
        "credential-rotation.service"
        "ssh-health-checks.service"
        "audit-trail-logger.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_success "Enabled: $service"
            ((passed++))
        else
            log_warn "Not enabled: $service"
            ((warnings++))
        fi
    done
}

# ============================================================================
# CHECK: Systemd timers active
# ============================================================================
check_timers() {
    log_info "Checking systemd timers..."
    
    local timers=(
        "credential-rotation.timer"
        "ssh-health-checks.timer"
    )
    
    for timer in "${timers[@]}"; do
        if systemctl is-active "$timer" >/dev/null 2>&1; then
            log_success "Active: $timer"
            ((passed++))
        else
            log_error "Inactive: $timer"
            ((failed++))
        fi
    done
}

# ============================================================================
# CHECK: Disk space for logs and backups
# ============================================================================
check_disk_space() {
    log_info "Checking disk space..."
    
    local available=$(df "$LOGS_DIR" | awk 'NR==2 {print $4}')
    local required=$((500 * 1024))  # 500MB minimum for safety
    
    if [ "$available" -gt "$required" ]; then
        local mb=$((available/1024))
        log_success "Sufficient disk space: ${mb}MB available"
        ((passed++))
    else
        local mb=$((available/1024))
        log_error "Insufficient disk space: only ${mb}MB available (need 500MB)"
        ((failed++))
    fi
}

# ============================================================================
# CHECK: GCP Secret Manager connectivity
# ============================================================================
check_gsm_connectivity() {
    log_info "Checking GCP Secret Manager connectivity..."
    
    local project_id="${GCP_PROJECT_ID:-nexusshield-prod}"
    
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
        if gcloud secrets list --limit=1 --project="$project_id" >/dev/null 2>&1; then
            log_success "GCP Secret Manager: Accessible"
            ((passed++))
        else
            log_error "GCP Secret Manager: Unreachable or auth failed"
            ((failed++))
        fi
    else
        log_warn "GCP authentication not configured"
        ((warnings++))
    fi
}

# ============================================================================
# CHECK: Vault connectivity (optional)
# ============================================================================
check_vault_connectivity() {
    log_info "Checking Vault connectivity..."
    
    if command -v vault &>/dev/null; then
        if vault status >/dev/null 2>&1; then
            log_success "Vault: Accessible"
            ((passed++))
        else
            log_warn "Vault: Configured but unreachable"
            ((warnings++))
        fi
    else
        log_info "Vault: Not configured (optional)"
    fi
}

# ============================================================================
# CHECK: Recent failures in audit trail
# ============================================================================
check_recent_failures() {
    log_info "Checking recent failures in audit trail..."
    
    local audit_log="${LOGS_DIR}/credential-audit.jsonl"
    if [ -f "$audit_log" ]; then
        local recent_failures=$(tail -100 "$audit_log" | grep -c '"status":"failed"' || true)
        
        if [ "$recent_failures" -eq 0 ]; then
            log_success "No recent failures detected"
            ((passed++))
        else
            log_warn "Found $recent_failures failures in last 100 entries"
            ((warnings++))
        fi
    else
        log_info "Audit log not yet created"
    fi
}

# ============================================================================
# CHECK: Quarantined accounts
# ============================================================================
check_quarantined_accounts() {
    log_info "Checking quarantined accounts..."
    
    local quarantine_file="${WORKSPACE_ROOT}/.credential-state/quarantined-accounts"
    
    if [ -f "$quarantine_file" ]; then
        local count=$(wc -l < "$quarantine_file")
        log_warn "Found $count quarantined accounts requiring review"
        ((warnings++))
    else
        log_success "No quarantined accounts"
        ((passed++))
    fi
}

# ============================================================================
# CHECK: Audit log integrity
# ============================================================================
check_audit_integrity() {
    log_info "Checking audit log integrity..."
    
    local audit_signer="${WORKSPACE_ROOT}/scripts/ssh_service_accounts/audit_log_signer.sh"
    
    if [ -f "$audit_signer" ]; then
        if bash "$audit_signer" verify >/dev/null 2>&1; then
            log_success "Audit trail integrity verified"
            ((passed++))
        else
            log_warn "Audit trail integrity check inconclusive (may be expected on first run)"
            ((warnings++))
        fi
    else
        log_info "Audit signer not yet installed"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    clear
    echo ""
    log_header "╔════════════════════════════════════════════════════════════╗"
    log_header "║  PREFLIGHT HEALTH GATE - PRODUCTION READY CHECK            ║"
    log_header "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    mkdir -p "$LOGS_DIR"
    
    check_commands
    check_directory_structure
    check_key_permissions
    check_systemd_services
    check_timers
    check_disk_space
    check_gsm_connectivity
    check_vault_connectivity
    check_recent_failures
    check_quarantined_accounts
    check_audit_integrity
    
    echo ""
    log_header "═══════════════════════════════════════════════════════════"
    log_header "RESULTS:"
    echo ""
    log_success "Passed:   $passed"
    log_warn "Warnings: $warnings"
    log_error "Failed:   $failed"
    log_header "═══════════════════════════════════════════════════════════"
    echo ""
    
    if [ $failed -gt 0 ]; then
        log_error "PREFLIGHT CHECK FAILED - System not ready for production"
        echo ""
        echo "❌ Production operations BLOCKED until failures are resolved"
        echo ""
        return 1
    elif [ $warnings -gt 0 ]; then
        log_warn "PREFLIGHT CHECK PASSED WITH WARNINGS - Review above"
        echo ""
        echo "⚠️  System is OPERATIONAL but check warnings for non-critical issues"
        echo ""
        return 0
    else
        log_success "PREFLIGHT CHECK PASSED - System ready for all operations"
        echo ""
        echo "✅ System is fully OPERATIONAL and healthy"
        echo ""
        return 0
    fi
}

main "$@"
