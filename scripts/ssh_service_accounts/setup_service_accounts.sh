#!/bin/bash
# Setup service accounts with SSH key authentication between hosts
# This script creates service accounts and configures SSH key-based authentication
# between specified hosts

set -e

export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
USERNAME="akushnir"
SSH_OPTS="-o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Service account configurations
# Format: "from_host:to_host:service_account_name"
ACCOUNTS=(
    "192.168.168.31:192.168.168.42:elevatediq-svc-worker-dev"
    "192.168.168.39:192.168.168.42:elevatediq-svc-worker-nas"
    "192.168.168.31:192.168.168.39:elevatediq-svc-dev-nas"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create local SSH key for service account
create_service_account_key() {
    local svc_name=$1
    local key_dir="${SECRETS_DIR}/${svc_name}"
    
    if [ -d "$key_dir" ]; then
        log_warn "Key directory already exists: $key_dir"
        return 0
    fi
    
    mkdir -p "$key_dir"
    
    log_info "Generating SSH key for $svc_name..."
    ssh-keygen -t ed25519 -f "${key_dir}/id_ed25519" -N "" -C "${svc_name}@$(hostname)" >/dev/null 2>&1
    
    log_success "Generated SSH key for $svc_name"
    echo "$(cat ${key_dir}/id_ed25519.pub)"
}

# Create service account on remote host
create_remote_service_account() {
    local host=$1
    local svc_name=$2
    local public_key=$3
    
    log_info "Creating service account $svc_name on $host..."
    
    ssh $SSH_OPTS \
        "${USERNAME}@${host}" bash -s "$svc_name" "$public_key" <<'REMOTE_SCRIPT'
        SVC_NAME=$1
        PUBLIC_KEY=$2
        
        # Check if user already exists
        if id "$SVC_NAME" &>/dev/null; then
            echo "User $SVC_NAME already exists"
            EXISTING_HOME=$(eval echo ~$SVC_NAME)
        else
            # Create service account with no login shell
            sudo useradd -r -s /bin/bash -m -d "/home/$SVC_NAME" "$SVC_NAME" || true
            EXISTING_HOME="/home/$SVC_NAME"
        fi
        
        # Set up SSH directory
        SSH_DIR="${EXISTING_HOME}/.ssh"
        mkdir -p "$SSH_DIR"
        
        # Add public key to authorized_keys
        echo "$PUBLIC_KEY" >> "${SSH_DIR}/authorized_keys"
        
        # Fix permissions
        sudo chown -R "$SVC_NAME:$SVC_NAME" "$SSH_DIR"
        sudo chmod 700 "$SSH_DIR"
        sudo chmod 600 "${SSH_DIR}/authorized_keys"
        
        echo "Service account $SVC_NAME configured on $HOSTNAME"
REMOTE_SCRIPT
    
    log_success "Service account $svc_name created/configured on $host"
}

# Test SSH connection
test_ssh_connection() {
    local from_host=$1
    local to_host=$2
    local svc_name=$3
    local key_path=${SECRETS_DIR}/${svc_name}/id_ed25519
    
    log_info "Testing SSH connection from $from_host to $to_host using $svc_name..."
    
    # First, need to copy the key to the source host
    scp $SSH_OPTS \
        "$key_path" "${USERNAME}@${from_host}:/tmp/${svc_name}_key" >/dev/null 2>&1
    
    # Test the connection
    ssh $SSH_OPTS \
        "${USERNAME}@${from_host}" bash -s "$svc_name" "$to_host" <<'TEST_SCRIPT'
        SVC_NAME=$1
        TO_HOST=$2
        KEY_FILE="/tmp/${SVC_NAME}_key"
        
        if ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
            -i "$KEY_FILE" "$SVC_NAME@$TO_HOST" "whoami" &>/dev/null; then
            echo "✓ Connection successful"
        else
            echo "✗ Connection failed"
        fi
        
        rm -f "$KEY_FILE"
TEST_SCRIPT
    
    log_info "SSH test completed"
}

# Store key in secrets manager (GSM fallback if Vault not available)
store_key_in_gsm() {
    local svc_name=$1
    local key_path=${SECRETS_DIR}/${svc_name}/id_ed25519
    
    if [ ! -f "$key_path" ]; then
        log_warn "Key file not found: $key_path"
        return 1
    fi
    
    # Try to store in Google Secret Manager
    if command -v gcloud &> /dev/null; then
        log_info "Storing $svc_name key in Google Secret Manager..."
        
        # Check if secret already exists
        if gcloud secrets describe "$svc_name" &>/dev/null; then
            if ! gcloud secrets versions add "$svc_name" --data-file="$key_path"; then
                log_error "Failed to add version to GSM secret: $svc_name"
                return 1
            fi
        else
            if ! gcloud secrets create "$svc_name" --data-file="$key_path"; then
                log_error "Failed to create GSM secret: $svc_name"
                return 1
            fi
        fi
        
        log_success "Stored $svc_name in GSM"
    fi
}

# Main execution
main() {
    log_info "Starting service account setup..."
    log_info "Workspace: $WORKSPACE_ROOT"
    log_info "Secrets directory: $SECRETS_DIR"
    
    mkdir -p "$SECRETS_DIR"
    
    for account in "${ACCOUNTS[@]}"; do
        IFS=':' read -r from_host to_host svc_name <<< "$account"
        
        log_info "========================================"
        log_info "Setting up: $svc_name"
        log_info "From: $from_host → To: $to_host"
        log_info "========================================"
        
        # Step 1: Generate local SSH key
        public_key=$(create_service_account_key "$svc_name")
        
        # Step 2: Create service account on target host
        create_remote_service_account "$to_host" "$svc_name" "$public_key"
        
        # Step 3: Store key in GSM
        store_key_in_gsm "$svc_name"
        
        # Step 4: Test connection
        test_ssh_connection "$from_host" "$to_host" "$svc_name"
        
        echo ""
    done
    
    log_success "Service account setup completed!"
    
    # Print summary
    echo ""
    echo "========================================"
    echo "Setup Summary:"
    echo "========================================"
    for account in "${ACCOUNTS[@]}"; do
        IFS=':' read -r from_host to_host svc_name <<< "$account"
        echo "✓ $svc_name: $from_host → $to_host"
        echo "  Key: ${SECRETS_DIR}/${svc_name}/id_ed25519"
    done
}

main "$@"
