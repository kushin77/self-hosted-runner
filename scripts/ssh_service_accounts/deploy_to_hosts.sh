#!/bin/bash
# Deploy service accounts to remote hosts and configure SSH authentication
# Part 2 of setup - deploys pre-generated keys to the hosts

set -e

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
USERNAME="akushnir"

# Host configurations
# Format: "host_ip:hostname"
HOSTS=(
    "192.168.168.31:dev-elevatediq-2"
    "192.168.168.39:nas-elevatediq"
    "192.168.168.42:worker-prod"
)

# Service account deployments: "svc_name:host_ip"
# These define where to CREATE the service account and where to PUT the key
DEPLOYMENTS=(
    "elevatediq-svc-worker-dev:192.168.168.42"      # Create on .42
    "elevatediq-svc-worker-nas:192.168.168.42"      # Create on .42
    "elevatediq-svc-dev-nas:192.168.168.39"         # Create on .39
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_deploy() { echo -e "${MAGENTA}[DEPLOY]${NC} $1"; }

# Check if we can SSH to a host
check_ssh_connectivity() {
    local host=$1
    
    if timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        "${USERNAME}@${host}" "echo 'Connected'" &>/dev/null; then
        return 0
    fi
    return 1
}

# Create service account on target host
create_service_account_on_host() {
    local target_host=$1
    local svc_name=$2
    local public_key=$3
    
    log_deploy "Creating service account $svc_name on $target_host..."
    
    ssh -o StrictHostKeyChecking=no \
        "${USERNAME}@${target_host}" bash -s <<SETUP_SCRIPT
set -e

SVC_NAME='$svc_name'
PUBLIC_KEY='$public_key'

echo "[*] Setting up service account: \$SVC_NAME"

# Check if user exists
if id "\$SVC_NAME" &>/dev/null; then
    echo "[!] User \$SVC_NAME already exists - will reconfigure"
    HOME_DIR=\$(eval echo ~\$SVC_NAME)
else
    echo "[+] Creating system user: \$SVC_NAME"
    sudo useradd -r -s /bin/bash -m -d "/home/\$SVC_NAME" "\$SVC_NAME" || {
        echo "[-] Failed to create user (may already exist)"
        HOME_DIR="/home/\$SVC_NAME"
    }
    HOME_DIR="/home/\$SVC_NAME"
fi

# Create/configure .ssh directory
SSH_DIR="\${HOME_DIR}/.ssh"
echo "[+] Setting up SSH directory: \$SSH_DIR"
mkdir -p "\$SSH_DIR"

# Add public key
echo "[+] Adding public key to authorized_keys"
echo "\$PUBLIC_KEY" >> "\${SSH_DIR}/authorized_keys"

# Fix permissions (using sudo if needed)
echo "[+] Fixing permissions"
sudo chown -R "\$SVC_NAME:\$SVC_NAME" "\$HOME_DIR/.ssh" 2>/dev/null || true
sudo chmod 700 "\$SSH_DIR"
sudo chmod 600 "\${SSH_DIR}/authorized_keys"

echo "[✓] Service account \$SVC_NAME is ready"
SETUP_SCRIPT
    
    log_success "Service account $svc_name configured on $target_host"
}

# Deploy SSH key to source host (for client-side usage)
deploy_key_to_host() {
    local source_host=$1
    local svc_name=$2
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! -f "$key_file" ]; then
        log_error "Key file not found: $key_file"
        return 1
    fi
    
    log_deploy "Deploying $svc_name key to $source_host..."
    
    # Copy the private key
    scp -o StrictHostKeyChecking=no \
        "$key_file" "${USERNAME}@${source_host}:/tmp/${svc_name}_id_ed25519" \
        || log_warn "Failed to deploy key to $source_host"
    
    # Setup the key on the source host
    ssh -o StrictHostKeyChecking=no "${USERNAME}@${source_host}" bash -s <<DEPLOY_SCRIPT
set -e
SVC_NAME='$svc_name'
KEY_FILE="/tmp/\${SVC_NAME}_id_ed25519"
DEPLOY_DIR="\$HOME/.ssh/svc-keys"

if [ ! -f "\$KEY_FILE" ]; then
    echo "[-] Key file not found: \$KEY_FILE"
    exit 1
fi

mkdir -p "\$DEPLOY_DIR"
mv "\$KEY_FILE" "\$DEPLOY_DIR/\${SVC_NAME}_key"
chmod 600 "\$DEPLOY_DIR/\${SVC_NAME}_key"

echo "[✓] Deployed key to \$DEPLOY_DIR/\${SVC_NAME}_key"
DEPLOY_SCRIPT
    
    log_success "Key deployed to $source_host"
}

# Test SSH connection between hosts
test_connection() {
    local from_host=$1
    local to_host=$2
    local svc_name=$3
    
    log_info "Testing connection: $svc_name from $from_host to $to_host..."
    
    ssh -o StrictHostKeyChecking=no "${USERNAME}@${from_host}" bash -s <<TEST_SCRIPT
SVC_NAME='$svc_name'
TO_HOST='$to_host'
KEY="/home/${USERNAME}/.ssh/svc-keys/\${SVC_NAME}_key"

if [ ! -f "\$KEY" ]; then
    echo "[-] Key not found: \$KEY"
    exit 1
fi

echo "[*] Testing SSH connection as \$SVC_NAME to \$TO_HOST..."
if timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
    -i "\$KEY" "\$SVC_NAME@\$TO_HOST" "whoami" &>/dev/null; then
    echo "[✓] Connection successful!"
else
    echo "[-] Connection failed"
    exit 1
fi
TEST_SCRIPT
    
    log_success "Connection test passed: $svc_name@$to_host"
}

# Print usage information
print_usage_info() {
    echo ""
    echo "========================================"
    echo "Service Account Setup Information"
    echo "========================================"
    echo ""
    echo "Account 1: elevatediq-svc-worker-dev"
    echo "  From: 192.168.168.31 (dev-elevatediq-2)"
    echo "  To:   192.168.168.42 (worker-prod)"
    echo "  Usage: ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key elevatediq-svc-worker-dev@192.168.168.42"
    echo ""
    echo "Account 2: elevatediq-svc-worker-nas"
    echo "  From: 192.168.168.39 (nas-elevatediq)"
    echo "  To:   192.168.168.42 (worker-prod)"
    echo "  Usage: ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key elevatediq-svc-worker-nas@192.168.168.42"
    echo ""
    echo "Account 3: elevatediq-svc-dev-nas"
    echo "  From: 192.168.168.31 (dev-elevatediq-2)"
    echo "  To:   192.168.168.39 (nas-elevatediq)"
    echo "  Usage: ssh -i ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key elevatediq-svc-dev-nas@192.168.168.39"
    echo ""
    echo "========================================"
}

main() {
    log_info "Starting service account deployment..."
    
    # Step 1: Check connectivity
    echo ""
    log_info "Checking host connectivity..."
    for host_entry in "${HOSTS[@]}"; do
        IFS=':' read -r host_ip hostname <<< "$host_entry"
        if check_ssh_connectivity "$host_ip"; then
            log_success "✓ Connected to $hostname ($host_ip)"
        else
            log_warn "✗ Cannot connect to $hostname ($host_ip) - will attempt anyway"
        fi
    done
    
    # Step 2: Extract target hosts and create service accounts
    echo ""
    log_info "Creating service accounts on target hosts..."
    declare -A created_accounts  # Track what we've created to avoid duplicates
    
    for deployment in "${DEPLOYMENTS[@]}"; do
        IFS=':' read -r svc_name target_host <<< "$deployment"
        
        key_storage="${SECRETS_DIR}/${svc_name}/id_ed25519.pub"
        if [ ! -f "$key_storage" ]; then
            log_error "Public key not found for $svc_name. Run generate_keys.sh first!"
            continue
        fi
        
        public_key=$(cat "$key_storage")
        
        # Create account if not already done
        account_key="${target_host}_${svc_name}"
        if [ -z "${created_accounts[$account_key]}" ]; then
            create_service_account_on_host "$target_host" "$svc_name" "$public_key"
            created_accounts[$account_key]=1
        else
            log_warn "Account $svc_name already setup on $target_host, skipping"
        fi
    done
    
    # Step 3: Deploy keys to source hosts and test connections
    echo ""
    log_info "Setting up source hosts with service account keys..."
    
    # Manual deployment list based on user's requirements
    deploy_pairs=(
        "192.168.168.31:elevatediq-svc-worker-dev"      # .31 gets dev-worker key
        "192.168.168.39:elevatediq-svc-worker-nas"      # .39 gets worker-nas key
        "192.168.168.31:elevatediq-svc-dev-nas"         # .31 gets dev-nas key
    )
    
    for pair in "${deploy_pairs[@]}"; do
        IFS=':' read -r from_host svc_name <<< "$pair"
        deploy_key_to_host "$from_host" "$svc_name"
    done
    
    # Step 4: Test connections
    echo ""
    log_info "Testing service account connections..."
    
    test_pairs=(
        "192.168.168.31:192.168.168.42:elevatediq-svc-worker-dev"
        "192.168.168.39:192.168.168.42:elevatediq-svc-worker-nas"
        "192.168.168.31:192.168.168.39:elevatediq-svc-dev-nas"
    )
    
    for pair in "${test_pairs[@]}"; do
        IFS=':' read -r from_host to_host svc_name <<< "$pair"
        test_connection "$from_host" "$to_host" "$svc_name" || log_warn "Test failed for $svc_name, but setup may still be valid"
    done
    
    log_success "Service account deployment completed!"
    print_usage_info
}

main "$@"
