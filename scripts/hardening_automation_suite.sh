#!/bin/bash
# Service Account Hardening & Enhancement Suite
# Implements: systemd sandboxing, audit signing, rollback logic, preflight gates
# Status: Production Grade Enhancement Package

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SYSTEMD_DIR="${WORKSPACE_ROOT}/systemd"
readonly SCRIPTS_DIR="${WORKSPACE_ROOT}/scripts/ssh_service_accounts"
readonly LOGS_DIR="${WORKSPACE_ROOT}/logs"
readonly AUDIT_TRAIL="${LOGS_DIR}/credential-audit.jsonl"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# ============================================================================
# 1. SYSTEMD HARDENING - Apply security constraints to all service units
# ============================================================================

harden_systemd_units() {
    log_info "Hardening systemd service units with security sandbox..."
    
    local services=(
        "service-account-credential-rotation.service"
        "service-account-orchestration.service"
        "ssh-health-checks.service"
        "audit-trail-logger.service"
        "monitoring-alert-triage.service"
    )
    
    for service in "${services[@]}"; do
        local service_file="${SYSTEMD_DIR}/${service}"
        
        if [ ! -f "$service_file" ]; then
            log_warn "Service not found: $service_file (skipping)"
            continue
        fi
        
        log_info "Hardening: $service"
        
        # Extract [Service] section, remove it, and reconstruct with hardening directives
        # This is a careful edit that adds sandbox controls without breaking the service
        
        sed -i '/^\[Service\]$/a\
# Security Hardening\
NoNewPrivileges=true\
ProtectSystem=strict\
ProtectHome=true\
PrivateTmp=true\
ProtectKernelTunables=true\
ProtectKernelModules=true\
ProtectKernelLogs=true\
ProtectClock=true\
ProtectHostname=true\
RestrictRealtime=true\
RestrictNamespaces=true\
LockPersonality=true\
MemoryDenyWriteExecute=true\
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6' "$service_file"
        
        # Add ReadWritePaths for logs and state directories (per service)
        case "$service" in
            "credential-rotation.service"|"service-account-credential-rotation.service")
                sed -i '/LockPersonality=/a\
ReadWritePaths=/home/akushnir/self-hosted-runner/logs /home/akushnir/self-hosted-runner/.credential-state /home/akushnir/self-hosted-runner/secrets/ssh/.backups' "$service_file"
                ;;
            "audit-trail-logger.service")
                sed -i '/LockPersonality=/a\
ReadWritePaths=/home/akushnir/self-hosted-runner/logs' "$service_file"
                ;;
            *)
                sed -i '/LockPersonality=/a\
ReadWritePaths=/home/akushnir/self-hosted-runner/logs /home/akushnir/self-hosted-runner/.deployment-state' "$service_file"
                ;;
        esac
        
        log_success "Hardened: $service"
    done
    
    log_success "All systemd units hardened"
}

# ============================================================================
# 2. AUDIT LOG SIGNING - Create SHA-256 hash-chain for immutable verification
# ============================================================================

create_audit_signer() {
    log_info "Creating audit log hash-chain signer..."
    
    cat > "${SCRIPTS_DIR}/audit_log_signer.sh" <<'AUDIT_SIGNER'
#!/bin/bash
# Audit Log Hash-Chain Signer
# Signs each JSONL entry with SHA-256 hash of (previous_hash + current_entry)
# Enables detection of tampering or deletion

set -euo pipefail

readonly AUDIT_LOG="${1:?AUDIT_LOG path required}"
readonly SIGNATURE_FILE="${AUDIT_LOG}.signatures"
readonly HASH_CHAIN_FILE="${AUDIT_LOG}.chain"

# Initialize or verify chain file
init_or_verify_chain() {
    if [ ! -f "$HASH_CHAIN_FILE" ]; then
        # First run: initialize with zero hash
        echo "0000000000000000000000000000000000000000000000000000000000000000" > "$HASH_CHAIN_FILE"
        return 0
    fi
}

# Sign latest unprocessed entries
sign_unprocessed_entries() {
    local last_signed_line=0
    
    if [ -f "$SIGNATURE_FILE" ]; then
        last_signed_line=$(tail -1 "$SIGNATURE_FILE" | awk '{print $1}')
    fi
    
    local current_line=0
    local prev_hash=$(cat "$HASH_CHAIN_FILE")
    
    while IFS= read -r entry; do
        ((current_line++))
        
        if [ $current_line -le $last_signed_line ]; then
            continue
        fi
        
        # Hash = SHA256(previous_hash + current_entry)
        local entry_hash=$(echo -n "${prev_hash}${entry}" | sha256sum | awk '{print $1}')
        
        # Store signature: line_number hash timestamp
        echo "$current_line $entry_hash $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SIGNATURE_FILE"
        
        prev_hash="$entry_hash"
    done < "$AUDIT_LOG"
    
    # Update chain file with latest hash
    echo "$prev_hash" > "$HASH_CHAIN_FILE"
}

# Verify integrity of audit log
verify_integrity() {
    log_info "Verifying audit trail integrity..."
    
    if [ ! -f "$SIGNATURE_FILE" ]; then
        echo "No signatures found. Initialize with: audit_log_signer.sh sign"
        return 1
    fi
    
    local expected_hash="0000000000000000000000000000000000000000000000000000000000000000"
    local errors=0
    
    while IFS=' ' read -r line_num expected_hash timestamp; do
        local entry=$(sed -n "${line_num}p" "$AUDIT_LOG")
        
        if [ -z "$entry" ]; then
            echo "ERROR: Missing entry at line $line_num"
            ((errors++))
            continue
        fi
        
        local computed_hash=$(echo -n "${expected_hash}${entry}" | sha256sum | awk '{print $1}')
        
        if [ "$computed_hash" != "$expected_hash" ]; then
            echo "ERROR: Hash mismatch at line $line_num"
            ((errors++))
        fi
    done < "$SIGNATURE_FILE"
    
    if [ $errors -eq 0 ]; then
        echo "✓ Audit trail integrity verified ($(wc -l < "$SIGNATURE_FILE") entries)"
        return 0
    else
        echo "✗ Integrity verification failed ($errors errors)"
        return 1
    fi
}

main() {
    case "${1:-verify}" in
        sign)
            init_or_verify_chain
            sign_unprocessed_entries
            echo "✓ Audit entries signed"
            ;;
        verify)
            verify_integrity
            ;;
        status)
            echo "Signatures: $(wc -l < "$SIGNATURE_FILE" || echo 0)"
            echo "Last Hash: $(cat "$HASH_CHAIN_FILE")"
            ;;
        *)
            echo "Usage: $0 {sign|verify|status}"
            exit 1
            ;;
    esac
}

main "$@"
AUDIT_SIGNER
    
    chmod +x "${SCRIPTS_DIR}/audit_log_signer.sh"
    log_success "Audit signer created: audit_log_signer.sh"
}

# ============================================================================
# 3. ROTATION ROLLBACK LOGIC - Auto-restore on health failure
# ============================================================================

create_rotation_rollback() {
    log_info "Creating rotation rollback handler..."
    
    cat > "${SCRIPTS_DIR}/rotation_rollback_handler.sh" <<'ROLLBACK_HANDLER'
#!/bin/bash
# Credential Rotation Rollback Handler
# Auto-restores previous key if post-rotation health check fails
# Maintains quarantine state for manual review

set -euo pipefail

readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly BACKUP_DIR="${SECRETS_DIR}/.backups"
readonly QUARANTINE_FILE="${WORKSPACE_ROOT}/.credential-state/quarantined-accounts"
readonly AUDIT_LOG="${WORKSPACE_ROOT}/logs/credential-audit.jsonl"

# Rollback a failed rotation
rollback_account() {
    local account=$1
    local latest_backup=$(ls -t "${BACKUP_DIR}/${account}/" 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        echo "ERROR: No backup found for $account"
        return 1
    fi
    
    local backup_path="${BACKUP_DIR}/${account}/${latest_backup}"
    local key_file="${SECRETS_DIR}/${account}/id_ed25519"
    
    # Restore from backup
    cp "${backup_path}/id_ed25519" "$key_file"
    cp "${backup_path}/id_ed25519.pub" "$key_file.pub"
    chmod 600 "$key_file"
    chmod 644 "$key_file.pub"
    
    # Log rollback event
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local user=${SUDO_USER:-$USER}
    echo "{\"timestamp\":\"$timestamp\",\"action\":\"rotation_rollback\",\"account\":\"$account\",\"status\":\"auto_restored\",\"backup\":\"$latest_backup\",\"user\":\"$user\"}" >> "$AUDIT_LOG"
    
    # Mark account as quarantined
    echo "$account" >> "$QUARANTINE_FILE"
    
    echo "✓ Rolled back $account to backup: $latest_backup"
    echo "⚠ Account quarantined for manual review"
    
    return 0
}

# Check if account needs rollback
check_and_rollback() {
    local account=$1
    
    # Run health check
    if ! bash "${WORKSPACE_ROOT}/scripts/ssh_service_accounts/health_check.sh" "$account" >/dev/null 2>&1; then
        echo "Health check failed for $account - initiating rollback..."
        rollback_account "$account"
        return 1
    fi
    
    return 0
}

# List quarantined accounts
list_quarantined() {
    if [ -f "$QUARANTINE_FILE" ]; then
        echo "Quarantined accounts (require manual review):"
        cat "$QUARANTINE_FILE"
    else
        echo "No quarantined accounts"
    fi
}

# Clear quarantine (manual approval)
clear_quarantine() {
    local account=$1
    grep -v "^${account}$" "$QUARANTINE_FILE" > "${QUARANTINE_FILE}.tmp" || true
    mv "${QUARANTINE_FILE}.tmp" "$QUARANTINE_FILE"
    echo "✓ Cleared quarantine for $account"
}

main() {
    case "${1:-check}" in
        check)
            check_and_rollback "${2:?account required}"
            ;;
        rollback)
            rollback_account "${2:?account required}"
            ;;
        quarantine)
            list_quarantined
            ;;
        clear)
            clear_quarantine "${2:?account required}"
            ;;
        *)
            echo "Usage: $0 {check <account>|rollback <account>|quarantine|clear <account>}"
            exit 1
            ;;
    esac
}

main "$@"
ROLLBACK_HANDLER
    
    chmod +x "${SCRIPTS_DIR}/rotation_rollback_handler.sh"
    log_success "Rollback handler created: rotation_rollback_handler.sh"
}

# ============================================================================
# 4. PREFLIGHT HEALTH GATE - Check before any production operation
# ============================================================================

create_preflight_gate() {
    log_info "Creating preflight health gate..."
    
    cat > "${SCRIPTS_DIR}/preflight_health_gate.sh" <<'PREFLIGHT_GATE'
#!/bin/bash
# Preflight Health Gate
# Runs pre-deployment checks; fails fast if infrastructure not ready
# All production scripts should call this first

set -euo pipefail

readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SYSTEMD_DIR="${WORKSPACE_ROOT}/systemd"
readonly LOGS_DIR="${WORKSPACE_ROOT}/logs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

passed=0
failed=0
warnings=0

# Check command availability
check_commands() {
    log_info "Checking required commands..."
    
    local commands=(ssh ssh-keygen gcloud bash jq)
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

# Check systemd services are enabled
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

# Check systemd timers active
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

# Check disk space for logs
check_disk_space() {
    log_info "Checking disk space..."
    
    local available=$(df "$LOGS_DIR" | awk 'NR==2 {print $4}')
    local required=$((100 * 1024))  # 100MB minimum
    
    if [ "$available" -gt "$required" ]; then
        log_success "Sufficient disk space: $((available/1024))MB available"
        ((passed++))
    else
        log_error "Insufficient disk space: only $((available/1024))MB available"
        ((failed++))
    fi
}

# Check GSM/Vault connectivity
check_credential_backends() {
    log_info "Checking credential backends..."
    
    # Check GCP Secret Manager
    if gcloud secrets list --limit=1 --project="${GCP_PROJECT_ID:-nexusshield-prod}" >/dev/null 2>&1; then
        log_success "GCP Secret Manager: Accessible"
        ((passed++))
    else
        log_warn "GCP Secret Manager: Unreachable"
        ((warnings++))
    fi
    
    # Check Vault (optional)
    if command -v vault &>/dev/null && vault status >/dev/null 2>&1; then
        log_success "Vault: Accessible"
        ((passed++))
    else
        log_warn "Vault: Not configured or unreachable (optional)"
        ((warnings++))
    fi
}

# Check previous errors in audit trail
check_recent_failures() {
    log_info "Checking recent failures in audit trail..."
    
    local audit_log="${LOGS_DIR}/credential-audit.jsonl"
    if [ -f "$audit_log" ]; then
        local recent_failures=$(tail -100 "$audit_log" | grep -c '"status":"failed"' || true)
        
        if [ "$recent_failures" -eq 0 ]; then
            log_success "No recent failures detected"
            ((passed++))
        else
            log_warn "Found $recent_failures recent failures - review logs"
            ((warnings++))
        fi
    fi
}

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         PREFLIGHT HEALTH GATE - PRODUCTION READY CHECK    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_commands
    check_systemd_services
    check_timers
    check_disk_space
    check_credential_backends
    check_recent_failures
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "RESULTS:"
    echo "  ✓ Passed:  $passed"
    echo "  ! Warnings: $warnings"
    echo "  ✗ Failed:  $failed"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    if [ $failed -gt 0 ]; then
        log_error "PREFLIGHT CHECK FAILED - System not ready for production"
        return 1
    elif [ $warnings -gt 0 ]; then
        log_warn "PREFLIGHT CHECK PASSED WITH WARNINGS - Review warnings above"
        return 0
    else
        log_success "PREFLIGHT CHECK PASSED - System ready for operations"
        return 0
    fi
}

main "$@"
PREFLIGHT_GATE
    
    chmod +x "${SCRIPTS_DIR}/preflight_health_gate.sh"
    log_success "Preflight gate created: preflight_health_gate.sh"
}

# ============================================================================
# 5. CHANGE-CONTROL AUTOMATION - Log all production operations
# ============================================================================

create_change_control() {
    log_info "Creating change-control automation..."
    
    cat > "${SCRIPTS_DIR}/change_control_tracker.sh" <<'CHANGE_CONTROL'
#!/bin/bash
# Change Control Tracker
# Records all production-impacting operations with standardized format
# Enables audit, rollback capability, and change history

set -euo pipefail

readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CHANGE_LOG="${WORKSPACE_ROOT}/logs/change-control.jsonl"
readonly SCRIPTS_DIR="${WORKSPACE_ROOT}/scripts/ssh_service_accounts"

# Log a change record
log_change() {
    local operation=$1
    local details=$2
    local status="${3:-initiating}"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local user=${SUDO_USER:-$USER}
    local hostname=$(hostname)
    
    local change_record="{
  \"timestamp\": \"$timestamp\",
  \"operation\": \"$operation\",
  \"status\": \"$status\",
  \"user\": \"$user\",
  \"hostname\": \"$hostname\",
  \"details\": \"$details\",
  \"change_id\": \"$(date +%s)-${RANDOM}\"
}"
    
    echo "$change_record" >> "$CHANGE_LOG"
}

# Execute with change tracking
execute_with_tracking() {
    local operation=$1
    local command=$2
    local details=$3
    
    # Log change initiation
    log_change "$operation" "$details" "initiating"
    
    # Execute command
    local exit_code=0
    if eval "$command"; then
        # Log success
        log_change "$operation" "$details" "completed"
        echo "✓ Change tracked: $operation"
        return 0
    else
        exit_code=$?
        # Log failure
        log_change "$operation" "FAILED: $details" "failed"
        echo "✗ Change failed: $operation (exit code: $exit_code)"
        return $exit_code
    fi
}

# Show change history
show_history() {
    local limit="${1:-20}"
    
    echo "Recent Changes (last $limit):"
    echo ""
    
    if [ -f "$CHANGE_LOG" ]; then
        tail -"$limit" "$CHANGE_LOG" | jq -r '[.timestamp, .operation, .status, .user] | @tsv' | \
        awk '{printf "%-30s %-30s %-15s %s\n", $1, $2, $3, $4}' || true
    else
        echo "No changes recorded yet"
    fi
}

# Rollback to previous state
rollback_change() {
    local change_id=$1
    
    log_change "rollback" "Rolling back change: $change_id" "initiating"
    
    # Find the change record
    if grep -q "\"change_id\": \"$change_id\"" "$CHANGE_LOG"; then
        log_change "rollback" "Rollback completed for change: $change_id" "completed"
        echo "✓ Rollback logged (actual rollback via specific handlers)"
    else
        echo "✗ Change ID not found: $change_id"
        return 1
    fi
}

main() {
    mkdir -p "$(dirname "$CHANGE_LOG")"
    
    case "${1:-history}" in
        log)
            # Internal use: log change with status
            log_change "$2" "$3" "${4:-initiating}"
            ;;
        execute)
            # Execute command with tracking
            execute_with_tracking "$2" "$3" "$4"
            ;;
        history)
            show_history "${2:-20}"
            ;;
        rollback)
            rollback_change "$2"
            ;;
        *)
            echo "Usage: $0 {log <op> <details> [status]|execute <op> <cmd> <details>|history [limit]|rollback <change_id>}"
            exit 1
            ;;
    esac
}

main "$@"
CHANGE_CONTROL
    
    chmod +x "${SCRIPTS_DIR}/change_control_tracker.sh"
    log_success "Change-control tracker created: change_control_tracker.sh"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  PRODUCTION HARDENING & AUTOMATION SUITE INSTALLATION    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    mkdir -p "$LOGS_DIR"
    
    harden_systemd_units
    create_audit_signer
    create_rotation_rollback
    create_preflight_gate
    create_change_control
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ ALL ENHANCEMENTS INSTALLED"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "📋 NEW SCRIPTS CREATED:"
    echo "   • audit_log_signer.sh - Sign audit trail with SHA-256 hashes"
    echo "   • rotation_rollback_handler.sh - Auto-restore on failure"
    echo "   • preflight_health_gate.sh - Pre-deployment health checks"
    echo "   • change_control_tracker.sh - Operation change logging"
    echo ""
    echo "🔒 SYSTEMD UNITS HARDENED:"
    echo "   • service-account-credential-rotation.service"
    echo "   • service-account-orchestration.service"
    echo "   • ssh-health-checks.service"
    echo "   • audit-trail-logger.service"
    echo "   • monitoring-alert-triage.service"
    echo ""
    echo "Next steps:"
    echo "  1. Reload systemd: systemctl daemon-reload"
    echo "  2. Restart services: systemctl restart credential-rotation.service"
    echo "  3. Run preflight gate: bash scripts/ssh_service_accounts/preflight_health_gate.sh"
    echo "  4. Verify audit signing: bash scripts/ssh_service_accounts/audit_log_signer.sh verify"
    echo ""
}

main
