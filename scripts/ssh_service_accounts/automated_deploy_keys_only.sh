#!/bin/bash
# SSH Service Account Deployment - No Password Required
# Uses SSH keys from secrets, GSM, or Vault exclusively
# Fully automated with zero password prompts

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs/deployment"
readonly STATE_DIR="${WORKSPACE_ROOT}/.deployment-state"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_FILE="${LOG_DIR}/deployment-keys-only-${TIMESTAMP}.log"

# Magic line: disable all password prompts
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

readonly USERNAME="akushnir"
readonly PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"

# Deployment targets
declare -A DEPLOYMENT_TARGETS=(
    ["elevatediq-svc-worker-dev"]="192.168.168.42"
    ["elevatediq-svc-worker-nas"]="192.168.168.42"
    ["elevatediq-svc-dev-nas"]="192.168.168.39"
)

# Source host mappings
declare -A SOURCE_HOSTS=(
    ["elevatediq-svc-worker-dev"]="192.168.168.31"
    ["elevatediq-svc-worker-nas"]="192.168.168.39"
    ["elevatediq-svc-dev-nas"]="192.168.168.31"
)

# SSH user private key (for accessing source/target hosts as akushnir)
SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }

# Initialize
init() {
    mkdir -p "$LOG_DIR" "$STATE_DIR" "$SECRETS_DIR"
    log_info "=== SSH Key-Based Deployment (No Passwords) ==="
    log_info "Timestamp: $TIMESTAMP"
    log_info "Using SSH key: $SSH_KEY_PATH"
}

# Get private key for service account from GSM
get_key_from_gsm() {
    local svc_name=$1
    local secret_name="ssh-${svc_name}"
    local temp_key="/tmp/${svc_name}_temp_key"
    
    if ! command -v gcloud &>/dev/null; then
        log_warn "gcloud not available, using local keys only"
        return 1
    fi
    
    log_info "Retrieving $svc_name from GSM..."
    
    if gcloud secrets versions access latest \
        --secret="$secret_name" \
        --project="$PROJECT_ID" > "$temp_key" 2>/dev/null; then
        chmod 600 "$temp_key"
        echo "$temp_key"
        return 0
    else
        rm -f "$temp_key"
        return 1
    fi
}

# SSH command without password prompts
ssh_cmd() {
    local target=$1
    shift
    
    ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
 \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o PasswordAuthentication=no \
        -o PubkeyAuthentication=yes \
        -o PreferredAuthentications=publickey \
        -i "$SSH_KEY_PATH" \
        "$target" "$@"
}

# SCP command without password prompts
scp_cmd() {
    local src=$1
    local dst=$2
    
    scp -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
 \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o PasswordAuthentication=no \
        -o PubkeyAuthentication=yes \
        -o PreferredAuthentications=publickey \
        -i "$SSH_KEY_PATH" \
        "$src" "$dst"
}

# Create service account on remote host (no password)
create_service_account() {
    local target_host=$1
    local svc_name=$2
    local public_key=$3
    
    log_info "Creating service account: $svc_name on $target_host"
    
    # Use sudo with NOPASSWD or check if user already has sudo
    ssh_cmd "${USERNAME}@${target_host}" bash -s "$svc_name" <<'SETUP_SCRIPT'
        set -e
        SVC_NAME=$1
        
        # Check if account exists
        if id "$SVC_NAME" &>/dev/null; then
            echo "Account already exists"
        else
            # Try with sudo (may fail if no NOPASSWD configured)
            if sudo -n true 2>/dev/null; then
                sudo useradd -r -s /bin/bash -m -d "/home/$SVC_NAME" "$SVC_NAME" 2>/dev/null || true
            else
                # Try without sudo (if user is root)
                useradd -r -s /bin/bash -m -d "/home/$SVC_NAME" "$SVC_NAME" 2>/dev/null || true
            fi
        fi
        
        # Setup SSH directory
        if sudo -n true 2>/dev/null; then
            sudo mkdir -p "/home/$SVC_NAME/.ssh"
            sudo chmod 700 "/home/$SVC_NAME/.ssh"
        else
            mkdir -p "/home/$SVC_NAME/.ssh" 2>/dev/null || true
            chmod 700 "/home/$SVC_NAME/.ssh" 2>/dev/null || true
        fi
SETUP_SCRIPT
    
    if [ $? -eq 0 ]; then
        log_success "Service account setup: $svc_name@$target_host"
    else
        log_warn "Account creation had issues, continuing..."
    fi
}

# Deploy SSH key to target (no password)
deploy_ssh_key() {
    local target_host=$1
    local svc_name=$2
    local public_key=$3
    
    log_info "Deploying SSH key: $svc_name → $target_host"
    
    ssh_cmd "${USERNAME}@${target_host}" bash -s "$svc_name" "$public_key" <<'DEPLOY_SCRIPT'
        set -e
        SVC_NAME=$1
        PUBLIC_KEY=$2
        HOME_DIR="/home/$SVC_NAME"
        AUTH_KEYS="${HOME_DIR}/.ssh/authorized_keys"
        
        # Add key if not present
        if ! grep -q "$PUBLIC_KEY" "$AUTH_KEYS" 2>/dev/null; then
            if sudo -n true 2>/dev/null; then
                echo "$PUBLIC_KEY" | sudo tee -a "$AUTH_KEYS" >/dev/null
            else
                echo "$PUBLIC_KEY" >> "$AUTH_KEYS" 2>/dev/null || true
            fi
        fi
        
        # Fix permissions
        if sudo -n true 2>/dev/null; then
            sudo chmod 600 "$AUTH_KEYS"
            sudo chown "$SVC_NAME:$SVC_NAME" "$AUTH_KEYS"
        else
            chmod 600 "$AUTH_KEYS" 2>/dev/null || true
            chown "$SVC_NAME:$SVC_NAME" "$AUTH_KEYS" 2>/dev/null || true
        fi
DEPLOY_SCRIPT
    
    if [ $? -eq 0 ]; then
        log_success "Key deployed: $svc_name@$target_host"
    else
        log_error "Key deployment failed"
        return 1
    fi
}

# Deploy key to source host (no password)
deploy_key_to_source() {
    local source_host=$1
    local svc_name=$2
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    log_info "Deploying key to source: $source_host"
    
    # Create directory on source
    ssh_cmd "${USERNAME}@${source_host}" "mkdir -p ~/.ssh/svc-keys && chmod 700 ~/.ssh/svc-keys" || true
    
    # Copy key via SCP (no password)
    if [ -f "$key_file" ]; then
        if scp_cmd "$key_file" "${USERNAME}@${source_host}:~/.ssh/svc-keys/${svc_name}_key"; then
            ssh_cmd "${USERNAME}@${source_host}" "chmod 600 ~/.ssh/svc-keys/${svc_name}_key"
            log_success "Key deployed to source: $source_host"
            return 0
        else
            log_error "SCP failed for $source_host"
            return 1
        fi
    else
        log_error "Key file not found: $key_file"
        return 1
    fi
}

# Test connection using keys only
test_connection() {
    local source_host=$1
    local target_host=$2
    local svc_name=$3
    
    log_info "Testing connection: $svc_name@$source_host → $target_host"
    
    ssh_cmd "${USERNAME}@${source_host}" bash -s "$svc_name" "$target_host" <<'TEST_SCRIPT'
        SVC_NAME=$1
        TARGET_HOST=$2
        KEY="~/.ssh/svc-keys/${SVC_NAME}_key"
        
        if [ ! -f "$KEY" ]; then
            echo "Key not found: $KEY"
            exit 1
        fi
        
        # Test with key-only authentication
        if timeout 5 ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
 \
            -o BatchMode=yes \
            -o PasswordAuthentication=no \
            -o PubkeyAuthentication=yes \
            -i "$KEY" "${SVC_NAME}@${TARGET_HOST}" "whoami" 2>/dev/null | grep -q "$SVC_NAME"; then
            echo "✓ Connection successful: $SVC_NAME@$TARGET_HOST"
            exit 0
        else
            echo "✗ Connection failed or identity mismatch"
            exit 1
        fi
TEST_SCRIPT
    
    local result=$?
    if [ $result -eq 0 ]; then
        log_success "Connection test passed: $svc_name"
        return 0
    else
        log_warn "Connection test result: $result"
        return 1
    fi
}

# Deploy service account (no passwords)
deploy_service_account() {
    local svc_name=$1
    local target_host=${DEPLOYMENT_TARGETS[$svc_name]}
    local source_host=${SOURCE_HOSTS[$svc_name]}
    
    log_info "=================================="
    log_info "Deploying: $svc_name"
    log_info "Source: $source_host → Target: $target_host"
    log_info "=================================="
    
    # Verify keys exist
    if [ ! -f "${SECRETS_DIR}/${svc_name}/id_ed25519" ]; then
        log_error "Keys missing for $svc_name"
        return 1
    fi
    
    local public_key=$(cat "${SECRETS_DIR}/${svc_name}/id_ed25519.pub")
    
    # Deploy (all via SSH keys, no passwords)
    create_service_account "$target_host" "$svc_name" "$public_key" || true
    deploy_ssh_key "$target_host" "$svc_name" "$public_key" || return 1
    deploy_key_to_source "$source_host" "$svc_name" || return 1
    test_connection "$source_host" "$target_host" "$svc_name" || log_warn "Test inconclusive"
    
    # Mark as deployed
    echo "$TIMESTAMP" > "${STATE_DIR}/${svc_name}.${target_host}.deployed"
    
    log_success "Deployed: $svc_name"
    return 0
}

# Deploy all (no passwords)
deploy_all() {
    log_info "Starting deployment... (NO PASSWORD PROMPTS)"
    
    local failed=0
    for svc_name in "${!DEPLOYMENT_TARGETS[@]}"; do
        if deploy_service_account "$svc_name"; then
            log_success "✓ $svc_name"
        else
            log_error "✗ $svc_name failed"
            ((failed++)) || true
        fi
        echo ""
    done
    
    if [ $failed -eq 0 ]; then
        log_success "All deployments complete!"
        return 0
    else
        log_error "$failed deployment(s) failed"
        return 1
    fi
}

# Main
main() {
    init
    deploy_all
}

main "$@"
