#!/bin/bash
# Rotation Rollback Handler
# Automatically restores previous SSH key if post-rotation health check fails
# Quarantines accounts for manual review after auto-rollback
# Usage: rotation_rollback_handler.sh {check <account>|rollback <account>|quarantine|clear <account>}

set -euo pipefail

readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly BACKUP_DIR="${SECRETS_DIR}/.backups"
readonly QUARANTINE_FILE="${WORKSPACE_ROOT}/.credential-state/quarantined-accounts"
readonly AUDIT_LOG="${WORKSPACE_ROOT}/logs/credential-audit.jsonl"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Rollback a failed credential rotation to previous backup
rollback_account() {
    local account=$1
    
    log_info "Rolling back account: $account"
    
    # Find latest backup (most recent timestamp)
    local latest_backup=$(ls -t "${BACKUP_DIR}/${account}/" 2>/dev/null | head -1 || echo "")
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup found for $account - cannot rollback"
        return 1
    fi
    
    local backup_path="${BACKUP_DIR}/${account}/${latest_backup}"
    local key_file="${SECRETS_DIR}/${account}/id_ed25519"
    
    # Verify backup files exist
    if [ ! -f "${backup_path}/id_ed25519" ]; then
        log_error "Backup key file missing: ${backup_path}/id_ed25519"
        return 1
    fi
    
    # Restore from backup
    cp "${backup_path}/id_ed25519" "$key_file"
    cp "${backup_path}/id_ed25519.pub" "$key_file.pub" 2>/dev/null || true
    chmod 600 "$key_file"
    chmod 644 "$key_file.pub" 2>/dev/null || true
    
    # Log rollback event to audit trail
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local user=${SUDO_USER:-$USER}
    local hostname=$(hostname)
    
    local rollback_record="{\"timestamp\":\"$timestamp\",\"action\":\"credential_rollback\",\"account\":\"$account\",\"status\":\"auto_restored\",\"backup_timestamp\":\"$latest_backup\",\"user\":\"$user\",\"hostname\":\"$hostname\",\"reason\":\"health_check_failure\"}"
    echo "$rollback_record" >> "$AUDIT_LOG"
    
    # Mark account as quarantined for manual review
    mkdir -p "$(dirname "$QUARANTINE_FILE")"
    if ! grep -q "^${account}$" "$QUARANTINE_FILE" 2>/dev/null; then
        echo "$account" >> "$QUARANTINE_FILE"
    fi
    
    log_success "Credential restored from backup: $latest_backup"
    log_warn "Account quarantined for manual review"
    
    return 0
}

# Check health and auto-rollback if failed
check_and_rollback() {
    local account=$1
    
    log_info "Running health check for: $account"
    
    # Run health check on specific account
    local health_script="${WORKSPACE_ROOT}/scripts/ssh_service_accounts/health_check.sh"
    
    if [ -f "$health_script" ]; then
        if ! bash "$health_script" "$account" >/dev/null 2>&1; then
            log_error "Health check FAILED for $account - initiating auto-rollback"
            rollback_account "$account" || return 1
            return 0
        fi
    else
        log_warn "Health check script not found, skipping health verification"
        return 0
    fi
    
    log_success "Health check PASSED for $account"
    return 0
}

# List all quarantined accounts
list_quarantined() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║             QUARANTINED ACCOUNTS (MANUAL REVIEW)         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -f "$QUARANTINE_FILE" ]; then
        echo "Accounts requiring manual review:"
        echo ""
        while IFS= read -r account; do
            echo "  • $account"
        done < "$QUARANTINE_FILE"
        echo ""
        echo "Action: Review rotation logs and either:"
        echo "  1. Fix the issue and clear quarantine: rotation_rollback_handler.sh clear <account>"
        echo "  2. Manual remediation required - escalate to ops"
        echo ""
    else
        echo "No quarantined accounts"
        echo ""
    fi
}

# Clear quarantine after manual approval
clear_quarantine() {
    local account=$1
    
    if [ ! -f "$QUARANTINE_FILE" ]; then
        log_warn "No quarantine file - account not quarantined"
        return 0
    fi
    
    if grep -q "^${account}$" "$QUARANTINE_FILE"; then
        grep -v "^${account}$" "$QUARANTINE_FILE" > "${QUARANTINE_FILE}.tmp"
        mv "${QUARANTINE_FILE}.tmp" "$QUARANTINE_FILE"
        
        # Log clearance event
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local user=${SUDO_USER:-$USER}
        echo "{\"timestamp\":\"$timestamp\",\"action\":\"quarantine_cleared\",\"account\":\"$account\",\"status\":\"manually_approved\",\"user\":\"$user\"}" >> "$AUDIT_LOG"
        
        log_success "Quarantine cleared for: $account"
    else
        log_warn "Account not found in quarantine: $account"
    fi
}

main() {
    case "${1:-quarantine}" in
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
            echo ""
            echo "Commands:"
            echo "  check <account>     - Run health check and auto-rollback if failed"
            echo "  rollback <account>  - Manually rollback to last backup"
            echo "  quarantine          - List quarantined accounts"
            echo "  clear <account>     - Clear quarantine after manual fix"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
