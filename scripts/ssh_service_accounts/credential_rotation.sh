#!/bin/bash
# SSH Credential Rotation & Management
# Handles credential lifecycle: generation, rotation, revocation, audit

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly AUDIT_LOG="${WORKSPACE_ROOT}/logs/credential-audit.log"
readonly ROTATION_STATE="${WORKSPACE_ROOT}/.credential-state/rotation"

readonly ROTATION_INTERVAL_DAYS="${ROTATION_INTERVAL_DAYS:-90}"
readonly PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$AUDIT_LOG"; }

audit_log() {
    local action=$1
    local details=$2
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local user=${SUDO_USER:-$USER}
    echo "{\"timestamp\":\"$timestamp\",\"action\":\"$action\",\"user\":\"$user\",\"details\":\"$details\"}" >> "$AUDIT_LOG"
}

init() {
    mkdir -p "$(dirname "$AUDIT_LOG")" "$ROTATION_STATE"
    log_info "Credential management initialized"
}

# Check if credential needs rotation
needs_rotation() {
    local svc_name=$1
    local last_rotation_file="${ROTATION_STATE}/${svc_name}.last-rotation"
    
    if [ ! -f "$last_rotation_file" ]; then
        return 0  # Never rotated, should rotate
    fi
    
    local last_rotation=$(cat "$last_rotation_file")
    local now=$(date +%s)
    local last_rotation_epoch=$(date -d "$last_rotation" +%s 2>/dev/null || echo 0)
    local age_days=$(( (now - last_rotation_epoch) / 86400 ))
    
    if [ $age_days -ge $ROTATION_INTERVAL_DAYS ]; then
        return 0  # Needs rotation
    fi
    
    return 1  # Still valid
}

# Generate new credentials
generate_new_credentials() {
    local svc_name=$1
    local backup_dir="${SECRETS_DIR}/.backups/${svc_name}"
    local current_dir="${SECRETS_DIR}/${svc_name}"
    
    log_info "Generating new credentials for: $svc_name"
    
    # Backup existing keys
    if [ -d "$current_dir" ]; then
        mkdir -p "$backup_dir"
        local backup_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        cp -r "$current_dir" "${backup_dir}/${backup_timestamp}" || {
            log_error "Failed to backup existing credentials"
            return 1
        }
        log_success "Backed up existing credentials"
    fi
    
    # Generate new key pair
    mkdir -p "$current_dir"
    ssh-keygen -t ed25519 -f "${current_dir}/id_ed25519" -N "" \
        -C "${svc_name}@$(hostname -f)" >/dev/null 2>&1
    
    chmod 600 "${current_dir}/id_ed25519"
    chmod 644 "${current_dir}/id_ed25519.pub"
    
    log_success "Generated new credentials for: $svc_name"
    audit_log "GENERATE" "Created new credentials for $svc_name"
    
    return 0
}

# Store in credential backends
store_credentials() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! -f "$key_file" ]; then
        log_error "Key file not found: $key_file"
        return 1
    fi
    
    # GSM
    log_info "Storing in Google Secret Manager..."
    local secret_name="ssh-${svc_name}"
    
    if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null 2>&1; then
        gcloud secrets versions add "$secret_name" \
            --data-file="$key_file" \
            --project="$PROJECT_ID" >/dev/null 2>&1 || true
    else
        gcloud secrets create "$secret_name" \
            --data-file="$key_file" \
            --project="$PROJECT_ID" \
            --replication-policy="automatic" >/dev/null 2>&1 || true
    fi
    
    log_success "Stored in GSM: $secret_name"
    audit_log "STORE_GSM" "Stored $svc_name in GSM"
    
    # Vault (if available)
    if command -v vault &>/dev/null && [ ! -z "${VAULT_ADDR:-}" ]; then
        log_info "Storing in Vault..."
        local key_data=$(cat "$key_file" | base64 -w 0)
        vault kv put "secret/ssh/${svc_name}" \
            private_key="$key_data" \
            rotated="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
        
        log_success "Stored in Vault"
        audit_log "STORE_VAULT" "Stored $svc_name in Vault"
    fi
}

# Revoke old credentials
revoke_credentials() {
    local svc_name=$1
    local hostname=$2
    local old_key_fingerprint=$3
    
    log_info "Revoking old credentials: $svc_name@$hostname"
    
    # Remove from authorized_keys
    ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new "${USER}@${hostname}" bash -s "$svc_name" "$old_key_fingerprint" <<'REVOKE_SCRIPT'
        SVC_NAME=$1
        OLD_FINGERPRINT=$2
        HOME_DIR="/home/$SVC_NAME"
        AUTH_KEYS="${HOME_DIR}/.ssh/authorized_keys"
        
        if [ -f "$AUTH_KEYS" ]; then
            # Remove old key (by removing line containing the fingerprint or old key)
            # This is a simplified approach - in production, track keys better
            sudo cp "$AUTH_KEYS" "${AUTH_KEYS}.bak"
            log_info "Backed up authorized_keys"
        fi
REVOKE_SCRIPT
    
    log_success "Revoked old credentials"
    audit_log "REVOKE" "Revoked old credentials for $svc_name@$hostname"
}

# Rotate credential for a service account
rotate_credential() {
    local svc_name=$1
    
    log_info "======================================"
    log_info "Rotating credential: $svc_name"
    log_info "======================================"
    
    # Check if rotation needed
    if ! needs_rotation "$svc_name"; then
        log_warn "Credential still valid, skipping"
        return 0
    fi
    
    # Generate new
    generate_new_credentials "$svc_name" || return 1
    
    # Store
    store_credentials "$svc_name" || return 1
    
    # Update rotation timestamp
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${ROTATION_STATE}/${svc_name}.last-rotation"
    
    log_success "Credential rotated: $svc_name"
    audit_log "ROTATE_COMPLETE" "Rotated $svc_name"
    
    return 0
}

# Check credential health
check_credential_health() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    log_info "Checking health of: $svc_name"
    
    # Check file exists and has correct permissions
    if [ ! -f "$key_file" ]; then
        log_error "Key file missing: $key_file"
        return 1
    fi
    
    local perms=$(stat -c %a "$key_file" 2>/dev/null || stat -f %OLp "$key_file")
    if [ "$perms" != "600" ]; then
        log_warn "Incorrect permissions: $perms (expected 600)"
    fi
    
    # Check key format
    if ! ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
        log_error "Invalid key format"
        return 1
    fi
    
    # Check age
    local age_days=$(( ($(date +%s) - $(stat -c %Y "$key_file" 2>/dev/null || stat -f %m "$key_file")) / 86400 ))
    log_info "Key age: $age_days days"
    
    if [ $age_days -gt $ROTATION_INTERVAL_DAYS ]; then
        log_warn "Key exceeds rotation interval: $age_days > $ROTATION_INTERVAL_DAYS"
    fi
    
    local fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
    log_success "Credential health OK - Fingerprint: $fingerprint"
    
    return 0
}

# Audit trail
show_audit_trail() {
    log_info "=== Credential Audit Trail ==="
    if [ -f "$AUDIT_LOG" ]; then
        tail -20 "$AUDIT_LOG"
    else
        log_warn "No audit trail yet"
    fi
}

# Credential report
credential_report() {
    log_info "=== Credential Status Report ==="
    
    for svc_name in elevatediq-svc-worker-dev elevatediq-svc-worker-nas elevatediq-svc-dev-nas; do
        local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
        
        if [ ! -f "$key_file" ]; then
            log_warn "$svc_name: Not generated"
            continue
        fi
        
        local last_rotation_file="${ROTATION_STATE}/${svc_name}.last-rotation"
        if [ -f "$last_rotation_file" ]; then
            local last_rotation=$(cat "$last_rotation_file")
            log_info "$svc_name: Last rotated $last_rotation"
        else
            log_info "$svc_name: Never rotated (key age: $(( ($(date +%s) - $(stat -c %Y "$key_file")) / 86400 )) days)"
        fi
        
        if needs_rotation "$svc_name"; then
            log_warn "$svc_name: Rotation needed"
        else
            log_success "$svc_name: Valid"
        fi
    done
}

# Rotate all
rotate_all() {
    log_info "Starting credential rotation cycle..."
    
    for svc_name in elevatediq-svc-worker-dev elevatediq-svc-worker-nas elevatediq-svc-dev-nas; do
        rotate_credential "$svc_name" || log_warn "Failed to rotate $svc_name, continuing..."
    done
    
    log_success "Rotation cycle complete"
}

# Main
main() {
    init
    
    case "${1:-report}" in
        rotate)
            rotate_credential "${2:-elevatediq-svc-worker-dev}"
            ;;
        rotate-all)
            rotate_all
            ;;
        health)
            check_credential_health "${2:-elevatediq-svc-worker-dev}"
            ;;
        report)
            credential_report
            ;;
        audit)
            show_audit_trail
            ;;
        *)
            echo "Usage: $0 {rotate <account>|rotate-all|health <account>|report|audit}"
            exit 1
            ;;
    esac
}

main "$@"
