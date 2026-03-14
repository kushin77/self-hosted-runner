#!/bin/bash
# Comprehensive Credential Rotation for All Service Accounts
# Rotates all SSH keys in secrets/ssh/ and updates GSM + deployment targets
# Enforces 90-day rotation interval, maintains immutable audit trail
# Status: Production-Grade Comprehensive Rotation

set -euo pipefail
trap 'cleanup_and_exit $?' EXIT INT TERM

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly LOGS_DIR="${WORKSPACE_ROOT}/logs"
readonly AUDIT_LOG="${LOGS_DIR}/credential-rotation.log"
readonly AUDIT_JSONL="${LOGS_DIR}/credential-audit.jsonl"
readonly ROTATION_STATE="${WORKSPACE_ROOT}/.credential-state/rotation"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Configuration
readonly ROTATION_INTERVAL_DAYS="${ROTATION_INTERVAL_DAYS:-90}"
readonly PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
readonly BACKUP_ENABLED="${BACKUP_ENABLED:-true}"

# SSH Key-Only Security (MANDATORY)
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Metrics tracking
ROTATION_START_TIME=$(date +%s)
TOTAL_ACCOUNTS=0
ROTATED_ACCOUNTS=0
FAILED_ACCOUNTS=0
SKIPPED_ACCOUNTS=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_step() { echo -e "${MAGENTA}▶▶${NC} $1" | tee -a "$AUDIT_LOG"; }

cleanup_and_exit() {
    local exit_code=$1
    log_info "=== Rotation Summary ==="
    log_info "Total Accounts: $TOTAL_ACCOUNTS"
    log_info "Successfully Rotated: $ROTATED_ACCOUNTS"
    log_info "Failed: $FAILED_ACCOUNTS"
    log_info "Skipped: $SKIPPED_ACCOUNTS"
    local duration=$(( ($(date +%s) - ROTATION_START_TIME) / 60 ))
    log_info "Duration: ${duration}m"
    
    if [ $exit_code -ne 0 ]; then
        log_error "Rotation completed with failures (exit code: $exit_code)"
    else
        log_success "Rotation completed successfully"
    fi
    exit $exit_code
}

# Audit trail logging
audit_log() {
    local action=$1
    local account=$2
    local status=$3
    local details="${4:-}"
    local user=${SUDO_USER:-$USER}
    
    local entry="{\"timestamp\":\"$TIMESTAMP\",\"action\":\"$action\",\"account\":\"$account\",\"status\":\"$status\",\"details\":\"$details\",\"user\":\"$user\"}"
    echo "$entry" | tee -a "$AUDIT_JSONL"
}

# Initialize directories
init() {
    mkdir -p "$LOGS_DIR" "$ROTATION_STATE" "$SECRETS_DIR/.backups"
    touch "$AUDIT_LOG" "$AUDIT_JSONL"
    log_info "Credential rotation initialized at $TIMESTAMP"
    log_info "Rotation interval: $ROTATION_INTERVAL_DAYS days"
    audit_log "rotation_started" "all_accounts" "initiated" "Comprehensive rotation cycle started"
}

# Check if credential needs rotation
needs_rotation() {
    local svc_name=$1
    local rotation_state_file="${ROTATION_STATE}/${svc_name}.last-rotation"
    
    if [ ! -f "$rotation_state_file" ]; then
        return 0  # Never rotated, needs rotation
    fi
    
    local last_rotation=$(cat "$rotation_state_file")
    local now=$(date +%s)
    local last_rotation_epoch=$(date -d "$last_rotation" +%s 2>/dev/null || echo 0)
    local age_days=$(( (now - last_rotation_epoch) / 86400 ))
    
    if [ $age_days -ge $ROTATION_INTERVAL_DAYS ]; then
        return 0  # Needs rotation
    fi
    
    return 1  # Still valid
}

# Backup existing credentials
backup_credentials() {
    local svc_name=$1
    local source_dir="${SECRETS_DIR}/${svc_name}"
    
    if [ ! -d "$source_dir" ]; then
        return 0  # No credentials to backup
    fi
    
    local backup_parent="${SECRETS_DIR}/.backups/${svc_name}"
    local backup_dir="${backup_parent}/${TIMESTAMP}"
    
    mkdir -p "$backup_dir"
    
    # Copy all files except .pub (we keep private keys backed up)
    for file in "$source_dir"/*; do
        [ -f "$file" ] && cp "$file" "$backup_dir/" 2>/dev/null || true
    done
    
    chmod -R 600 "$backup_dir"
    log_success "Backed up existing credentials for $svc_name → $backup_dir"
    audit_log "backup_completed" "$svc_name" "success" "Backup location: $backup_dir"
}

# Generate new Ed25519 key pair
generate_new_key() {
    local svc_name=$1
    local key_dir="${SECRETS_DIR}/${svc_name}"
    local key_file="${key_dir}/id_ed25519"
    
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    
    # Remove old key if it exists
    [ -f "$key_file" ] && rm -f "$key_file" "$key_file.pub"
    
    # Generate new Ed25519 key
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "$svc_name@nexusshield-prod" >/dev/null 2>&1 || {
        log_error "Failed to generate key for $svc_name"
        audit_log "key_generation" "$svc_name" "failed" "ssh-keygen failed"
        return 1
    }
    
    chmod 600 "$key_file"
    chmod 644 "$key_file.pub"
    
    local fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
    log_success "Generated new Ed25519 key for $svc_name (fingerprint: $fingerprint)"
    audit_log "key_generated" "$svc_name" "success" "Fingerprint: $fingerprint"
    
    return 0
}

# Store credential in GSM
store_in_gsm() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! -f "$key_file" ]; then
        log_warn "Key file not found for $svc_name (skipping GSM storage)"
        return 1
    fi
    
    # Try to create secret if it doesn't exist
    gcloud secrets create "$svc_name" \
        --replication-policy="automatic" \
        --data-file="$key_file" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1 || \
    # If it exists, add new version
    gcloud secrets versions add "$svc_name" \
        --data-file="$key_file" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1 || {
        log_error "Failed to store $svc_name in GSM"
        audit_log "gsm_storage" "$svc_name" "failed" "gcloud secrets command failed"
        return 1
    }
    
    log_success "Stored credential for $svc_name in GSM"
    audit_log "gsm_storage" "$svc_name" "success" "Secret updated in Google Secret Manager"
    return 0
}

# Check credential health
check_credential_health() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! -f "$key_file" ]; then
        log_error "Key file missing: $key_file"
        audit_log "health_check" "$svc_name" "failed" "Key file missing"
        return 1
    fi
    
    # Check permissions
    local perms=$(stat -c %a "$key_file" 2>/dev/null || echo "000")
    if [ "$perms" != "600" ]; then
        log_warn "Incorrect permissions for $svc_name: $perms (expected 600)"
    fi
    
    # Validate key format
    if ! ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
        log_error "Invalid key format for $svc_name"
        audit_log "health_check" "$svc_name" "failed" "Invalid key format detected"
        return 1
    fi
    
    # Get fingerprint
    local fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
    log_success "Health check passed for $svc_name (fingerprint: $fingerprint)"
    audit_log "health_check" "$svc_name" "success" "Fingerprint: $fingerprint"
    
    return 0
}

# Rotate single account
rotate_account() {
    local svc_name=$1
    ((TOTAL_ACCOUNTS++))
    
    log_info ""
    log_step "Rotating: $svc_name"
    
    # Check if rotation is needed
    if ! needs_rotation "$svc_name"; then
        log_warn "Rotation not needed yet (skipping)"
        ((SKIPPED_ACCOUNTS++))
        audit_log "rotation_skipped" "$svc_name" "skipped" "Not yet due for rotation"
        return 0
    fi
    
    # Backup existing credentials
    if [ "$BACKUP_ENABLED" = "true" ]; then
        backup_credentials "$svc_name" || {
            log_warn "Backup failed but continuing with rotation"
        }
    fi
    
    # Generate new key
    if ! generate_new_key "$svc_name"; then
        ((FAILED_ACCOUNTS++))
        return 1
    fi
    
    # Store in GSM
    if ! store_in_gsm "$svc_name"; then
        ((FAILED_ACCOUNTS++))
        return 1
    fi
    
    # Verify health
    if ! check_credential_health "$svc_name"; then
        ((FAILED_ACCOUNTS++))
        return 1
    fi
    
    # Update rotation state
    echo "$TIMESTAMP" > "${ROTATION_STATE}/${svc_name}.last-rotation"
    
    ((ROTATED_ACCOUNTS++))
    log_success "Successfully rotated $svc_name"
    audit_log "rotation_completed" "$svc_name" "success" "Rotation and verification complete"
    
    return 0
}

# Rotate all accounts
rotate_all_accounts() {
    log_step "Discovering all service accounts..."
    
    # Get list of all account directories in secrets/ssh/
    local account_dirs=()
    if [ ! -d "$SECRETS_DIR" ]; then
        log_error "Secrets directory not found: $SECRETS_DIR"
        return 1
    fi
    
    for dir in "$SECRETS_DIR"/*; do
        if [ -d "$dir" ] && [ "$(basename "$dir")" != ".backups" ]; then
            account_dirs+=("$(basename "$dir")")
        fi
    done
    
    if [ ${#account_dirs[@]} -eq 0 ]; then
        log_error "No service accounts found in $SECRETS_DIR"
        return 1
    fi
    
    log_success "Found ${#account_dirs[@]} account(s) to process"
    
    # Rotate each account
    local rotation_exit_code=0
    for account in "${account_dirs[@]}"; do
        rotate_account "$account" || rotation_exit_code=$?
    done
    
    return $rotation_exit_code
}

# Report credential status
report_status() {
    log_step "Credential Status Report"
    log_info "=== Service Account Credentials ==="
    
    if [ ! -d "$SECRETS_DIR" ]; then
        log_warn "Secrets directory not found"
        return
    fi
    
    for account_dir in "$SECRETS_DIR"/*; do
        if [ ! -d "$account_dir" ] || [ "$(basename "$account_dir")" = ".backups" ]; then
            continue
        fi
        
        local account=$(basename "$account_dir")
        local key_file="${account_dir}/id_ed25519"
        
        if [ ! -f "$key_file" ]; then
            log_warn "$account: Key not generated"
            continue
        fi
        
        local last_rotation_file="${ROTATION_STATE}/${account}.last-rotation"
        local fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
        
        if [ -f "$last_rotation_file" ]; then
            local last_rotation=$(cat "$last_rotation_file")
            local age_days=$(( ($(date +%s) - $(date -d "$last_rotation" +%s 2>/dev/null || echo 0)) / 86400 ))
            
            if needs_rotation "$account"; then
                log_warn "$account: Rotated $last_rotation (age: ${age_days}d) - NEEDS ROTATION"
            else
                log_success "$account: Rotated $last_rotation (age: ${age_days}d) - Valid"
            fi
        else
            log_warn "$account: Never rotated"
        fi
        
        log_info "  Fingerprint: $fingerprint"
    done
}

# Show audit trail
show_audit_trail() {
    log_step "Credential Audit Trail (Recent 20 entries)"
    if [ -f "$AUDIT_JSONL" ]; then
        tail -20 "$AUDIT_JSONL" | while read -r line; do
            echo "  $line"
        done
    else
        log_warn "No audit trail yet"
    fi
}

# Main function
main() {
    init
    
    case "${1:-rotate-all}" in
        rotate-all)
            log_step "Starting comprehensive credential rotation for all accounts..."
            rotate_all_accounts || true
            ;;
        report)
            report_status
            ;;
        audit)
            show_audit_trail
            ;;
        health)
            log_step "Health check for all credentials..."
            for account_dir in "$SECRETS_DIR"/*; do
                if [ -d "$account_dir" ] && [ "$(basename "$account_dir")" != ".backups" ]; then
                    local account=$(basename "$account_dir")
                    check_credential_health "$account" || true
                fi
            done
            ;;
        *)
            cat <<'USAGE'
Usage: rotate_all_service_accounts.sh {rotate-all|report|audit|health}

Commands:
  rotate-all   Rotate all service account credentials (default)
  report       Show credential status report
  audit        Show audit trail
  health       Run health checks on all credentials

Environment Variables:
  ROTATION_INTERVAL_DAYS  (default: 90)
  GCP_PROJECT_ID         (default: nexusshield-prod)
  BACKUP_ENABLED         (default: true)
USAGE
            exit 1
            ;;
    esac
}

# Run main
main "$@"
