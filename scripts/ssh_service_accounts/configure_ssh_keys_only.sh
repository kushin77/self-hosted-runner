#!/bin/bash
# SSH Configuration for Service Accounts - Keys Only
# Sets up SSH config to prevent password prompts

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs"

readonly USERNAME="akushnir"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Configure SSH to never prompt for passwords
configure_ssh_no_passwords() {
    log_info "Configuring SSH to use keys only (no password prompts)..."
    
    local ssh_config="${HOME}/.ssh/config"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    
    # Create/update SSH config for service account hosts
    cat >> "$ssh_config" <<'SSH_CONFIG'

# ========================================
# Service Accounts - Keys Only, No Passwords
# ========================================

Host 192.168.168.* dev-elevatediq* nas-elevatediq* worker-prod*
    # Force key authentication
    PasswordAuthentication no
    PubkeyAuthentication yes
    PreferredAuthentications publickey
    
    # Disable password-based fallback
    ChallengeResponseAuthentication no
    KbdInteractiveAuthentication no
    
    # Never prompt for passwords
    BatchMode yes
    
    # Skip host key verification for internal network
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    
    # Use service account keys
    IdentitiesOnly yes
    IdentityFile ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key
    IdentityFile ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key
    IdentityFile ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key

SSH_CONFIG
    
    chmod 600 "$ssh_config"
    log_success "SSH config updated"
}

# Verify SSH_ASKPASS is disabled
configure_shell_environment() {
    log_info "Configuring shell environment..."
    
    local bashrc="${HOME}/.bashrc"
    
    # Add to bashrc
    cat >> "$bashrc" <<'BASHRC'

# ========================================
# SSH - Keys Only, No Password Prompts
# ========================================
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

BASHRC
    
    log_success "Shell environment configured"
}

# Create SSH identity file
create_ssh_identity() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    local dest="${HOME}/.ssh/svc-keys/${svc_name}_key"
    
    if [ ! -f "$key_file" ]; then
        log_warn "Key not found: $key_file"
        return 1
    fi
    
    mkdir -p "${HOME}/.ssh/svc-keys"
    cp "$key_file" "$dest"
    chmod 600 "$dest"
    
    log_success "Created identity: $dest"
    return 0
}

# Deploy all service account keys to ~/.ssh/svc-keys
deploy_all_keys() {
    log_info "Deploying all service account keys..."
    
    mkdir -p "${HOME}/.ssh/svc-keys"
    chmod 700 "${HOME}/.ssh/svc-keys"
    
    for svc_dir in "${SECRETS_DIR}"/*/; do
        local svc_name=$(basename "$svc_dir")
        if [ -f "${svc_dir}/id_ed25519" ]; then
            cp "${svc_dir}/id_ed25519" "${HOME}/.ssh/svc-keys/${svc_name}_key"
            chmod 600 "${HOME}/.ssh/svc-keys/${svc_name}_key"
            log_success "Deployed: $svc_name"
        fi
    done
}

# Verify no password prompts
verify_no_prompts() {
    log_info "Verifying SSH_ASKPASS settings..."
    
    local askpass="${SSH_ASKPASS:-unset}"
    local askpass_req="${SSH_ASKPASS_REQUIRE:-unset}"
    local display="${DISPLAY:-unset}"
    
    log_info "  SSH_ASKPASS=$askpass"
    log_info "  SSH_ASKPASS_REQUIRE=$askpass_req"
    log_info "  DISPLAY=$display"
    
    if [ "$askpass" = "none" ] && [ "$askpass_req" = "never" ]; then
        log_success "Environment configured correctly"
        return 0
    else
        log_warn "Please reload shell or source ~/.bashrc"
        return 1
    fi
}

# Test SSH connection without password
test_ssh_connection() {
    local target=$1
    local svc_name=${2:-elevatediq-svc-worker-dev}
    
    log_info "Testing SSH connection to $target with $svc_name..."
    
    if ssh -o BatchMode=yes \
           -o PasswordAuthentication=no \
           -o PubkeyAuthentication=yes \
           -o ConnectTimeout=5 \
           -i "${HOME}/.ssh/svc-keys/${svc_name}_key" \
           "${svc_name}@${target}" "whoami" 2>/dev/null; then
        log_success "Connection successful!"
        return 0
    else
        log_error "Connection failed"
        return 1
    fi
}

# Main
main() {
    case "${1:-setup}" in
        setup)
            log_info "=== SSH Configuration: Keys Only ==="
            configure_ssh_no_passwords
            configure_shell_environment
            deploy_all_keys
            verify_no_prompts
            log_success "SSH configured for key-based auth (no passwords)"
            ;;
        verify)
            verify_no_prompts
            ;;
        deploy-keys)
            deploy_all_keys
            ;;
        test)
            test_ssh_connection "${2:-192.168.168.42}" "${3:-elevatediq-svc-worker-dev}"
            ;;
        *)
            echo "Usage: $0 {setup|verify|deploy-keys|test [host] [account]}"
            exit 1
            ;;
    esac
}

main "$@"
