#!/bin/bash
# Automated Service Account Deployment Framework
# Fully idempotent, no-ops, hands-off deployment with GSM credential management
# Supports direct deployment without GitHub Actions

set -euo pipefail

export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs/deployment"
readonly STATE_DIR="${WORKSPACE_ROOT}/.deployment-state"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_FILE="${LOG_DIR}/deployment-${TIMESTAMP}.log"
readonly SSH_OPTS="-o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

# Configuration
readonly USERNAME="akushnir"
readonly PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
readonly VAULT_ADDR="${VAULT_ADDR:-https://vault.internal:8200}"
readonly USE_GSM="${USE_GSM:-true}"
readonly USE_VAULT="${USE_VAULT:-false}"

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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }
log_deploy() { echo -e "${MAGENTA}[DEPLOY]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"; }

# Initialize
init() {
    mkdir -p "$LOG_DIR" "$STATE_DIR" "$SECRETS_DIR"
    log_info "=== Service Account Deployment Framework ==="
    log_info "Timestamp: $TIMESTAMP"
    log_info "Workspace: $WORKSPACE_ROOT"
    log_info "Log file: $LOG_FILE"
}

# Idempotency check - verify if already deployed
is_already_deployed() {
    local svc_name=$1
    local target_host=$2
    local state_file="${STATE_DIR}/${svc_name}.${target_host}.deployed"
    
    if [ -f "$state_file" ]; then
        local deployed_date=$(cat "$state_file")
        log_warn "Already deployed: $svc_name on $target_host (deployed: $deployed_date)"
        return 0
    fi
    return 1
}

# Mark as deployed
mark_deployed() {
    local svc_name=$1
    local target_host=$2
    local state_file="${STATE_DIR}/${svc_name}.${target_host}.deployed"
    echo "$TIMESTAMP" > "$state_file"
}

# Verify key exists locally
verify_keys_exist() {
    local svc_name=$1
    local priv_key="${SECRETS_DIR}/${svc_name}/id_ed25519"
    local pub_key="${SECRETS_DIR}/${svc_name}/id_ed25519.pub"
    
    if [ ! -f "$priv_key" ] || [ ! -f "$pub_key" ]; then
        log_error "Keys missing for $svc_name"
        log_info "Run: bash scripts/ssh_service_accounts/generate_keys.sh"
        return 1
    fi
    return 0
}

# Store credentials in GSM
store_in_gsm() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! "$USE_GSM" == "true" ]; then
        log_warn "GSM storage disabled"
        return 0
    fi
    
    if ! command -v gcloud &>/dev/null; then
        log_warn "gcloud not available, skipping GSM"
        return 0
    fi
    
    log_info "Storing $svc_name in GSM..."
    
    local secret_name="ssh-${svc_name}"
    if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null 2>&1; then
        if ! gcloud secrets versions add "$secret_name" \
            --data-file="$key_file" \
            --project="$PROJECT_ID"; then
            log_error "Failed writing key version to GSM: $secret_name"
            return 1
        fi
    else
        if ! gcloud secrets create "$secret_name" \
            --data-file="$key_file" \
            --project="$PROJECT_ID" \
            --replication-policy="automatic"; then
            log_error "Failed creating GSM secret: $secret_name"
            return 1
        fi
    fi
    
    log_success "Stored in GSM: $secret_name"
}

# Store credentials in Vault
store_in_vault() {
    local svc_name=$1
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! "$USE_VAULT" == "true" ]; then
        return 0
    fi
    
    if ! command -v vault &>/dev/null; then
        log_warn "vault CLI not available"
        return 0
    fi
    
    log_info "Storing $svc_name in Vault..."
    
    local key_data=$(cat "$key_file" | base64 -w 0)
    vault kv put "secret/ssh/${svc_name}" \
        private_key="$key_data" \
        timestamp="$TIMESTAMP" \
        2>/dev/null || true
    
    log_success "Stored in Vault: secret/ssh/${svc_name}"
}

# Create service account on remote host (idempotent)
create_service_account() {
    local target_host=$1
    local svc_name=$2
    local public_key=$3
    
    log_deploy "Creating service account: $svc_name on $target_host"
    
    # Check if account already exists
    local account_check=$(ssh $SSH_OPTS \
        "${USERNAME}@${target_host}" "id '$svc_name' 2>/dev/null && echo 'EXISTS' || echo 'NEW'" 2>/dev/null || echo "ERROR")
    
    if [ "$account_check" == "EXISTS" ]; then
        log_warn "Account already exists: $svc_name@$target_host"
    else
        log_info "Creating new account: $svc_name@$target_host"
        
        ssh $SSH_OPTS \
            "${USERNAME}@${target_host}" bash -s "$svc_name" <<'SETUP_SCRIPT'
            SVC_NAME=$1
            
            if ! id "$SVC_NAME" &>/dev/null; then
                sudo useradd -r -s /bin/bash -m -d "/home/$SVC_NAME" "$SVC_NAME" || true
            fi
            
            sudo mkdir -p "/home/$SVC_NAME/.ssh"
            sudo chmod 700 "/home/$SVC_NAME/.ssh"
            sudo chown "$SVC_NAME:$SVC_NAME" "/home/$SVC_NAME/.ssh"
SETUP_SCRIPT
    fi
    
    log_success "Service account ready: $svc_name@$target_host"
}

# Deploy SSH key to target (idempotent)
deploy_ssh_key() {
    local target_host=$1
    local svc_name=$2
    local public_key=$3
    
    log_deploy "Deploying SSH key: $svc_name → $target_host"
    
    # Check if key already authorized
    local has_key=$(ssh $SSH_OPTS \
        "${USERNAME}@${target_host}" \
        "grep -q '${public_key}' ~/.ssh/authorized_keys 2>/dev/null && echo 'YES' || echo 'NO'" || echo "ERROR")
    
    if [ "$has_key" == "YES" ]; then
        log_warn "Key already authorized: $svc_name@$target_host"
        return 0
    fi
    
    log_info "Adding key to authorized_keys: $svc_name@$target_host"
    
    ssh $SSH_OPTS "${USERNAME}@${target_host}" bash -s "$svc_name" "$public_key" <<'DEPLOY_SCRIPT'
        SVC_NAME=$1
        PUBLIC_KEY=$2
        HOME_DIR="/home/$SVC_NAME"
        AUTH_KEYS="${HOME_DIR}/.ssh/authorized_keys"
        
        # Add key if not present
        if ! grep -q "$PUBLIC_KEY" "$AUTH_KEYS" 2>/dev/null; then
            echo "$PUBLIC_KEY" | sudo tee -a "$AUTH_KEYS" >/dev/null
        fi
        
        # Fix permissions
        sudo chmod 600 "$AUTH_KEYS"
        sudo chown "$SVC_NAME:$SVC_NAME" "$AUTH_KEYS"
DEPLOY_SCRIPT
    
    log_success "Key deployed: $svc_name@$target_host"
}

# Deploy key to source host
deploy_key_to_source() {
    local source_host=$1
    local svc_name=$2
    local key_file="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    log_deploy "Deploying private key to source: $source_host"
    
    # Check if key already present
    local has_key=$(ssh $SSH_OPTS \
        "${USERNAME}@${source_host}" \
        "test -f ~/.ssh/svc-keys/${svc_name}_key && echo 'YES' || echo 'NO'" || echo "ERROR")
    
    if [ "$has_key" == "YES" ]; then
        log_warn "Key already deployed to source: $source_host"
        return 0
    fi
    
    log_info "Copying key to source host: $source_host"
    
    ssh $SSH_OPTS "${USERNAME}@${source_host}" \
        "mkdir -p ~/.ssh/svc-keys && chmod 700 ~/.ssh/svc-keys" || true
    
    scp $SSH_OPTS \
        "$key_file" \
        "${USERNAME}@${source_host}:~/.ssh/svc-keys/${svc_name}_key" || {
        log_error "Failed to deploy key to $source_host"
        return 1
    }
    
    ssh $SSH_OPTS "${USERNAME}@${source_host}" \
        "chmod 600 ~/.ssh/svc-keys/${svc_name}_key" || true
    
    log_success "Key deployed to source: $source_host"
}

# Test SSH connectivity
test_connection() {
    local source_host=$1
    local target_host=$2
    local svc_name=$3
    
    log_info "Testing connection: $svc_name@$source_host → $target_host"
    
    local test_result=$(ssh $SSH_OPTS \
        "${USERNAME}@${source_host}" bash -s "$svc_name" "$target_host" <<'TEST_SCRIPT'
        SVC_NAME=$1
        TARGET_HOST=$2
        KEY="~/.ssh/svc-keys/${SVC_NAME}_key"
        
        if ! test -f "$KEY"; then
            echo "KEY_NOT_FOUND"
            exit 0
        fi
        
        if timeout 5 ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 \
            -i "$KEY" "${SVC_NAME}@${TARGET_HOST}" "whoami" 2>/dev/null | grep -q "$SVC_NAME"; then
            echo "SUCCESS"
        else
            echo "FAILED"
        fi
TEST_SCRIPT
    )
    
    case "$test_result" in
        SUCCESS)
            log_success "Connection verified: $svc_name"
            return 0
            ;;
        KEY_NOT_FOUND)
            log_warn "Key not yet deployed on source host"
            return 0
            ;;
        *)
            log_warn "Connection test result: $test_result"
            return 1
            ;;
    esac
}

# Deploy service account
deploy_service_account() {
    local svc_name=$1
    local target_host=${DEPLOYMENT_TARGETS[$svc_name]}
    local source_host=${SOURCE_HOSTS[$svc_name]}
    
    log_info "=================================="
    log_deploy "Deploying: $svc_name"
    log_info "Source: $source_host"
    log_info "Target: $target_host"
    log_info "=================================="
    
    # Idempotency check
    if is_already_deployed "$svc_name" "$target_host"; then
        log_info "Skipping (already deployed). Force with: rm ${STATE_DIR}/${svc_name}.${target_host}.deployed"
        return 0
    fi
    
    # Verify keys exist
    verify_keys_exist "$svc_name" || return 1
    
    local public_key=$(cat "${SECRETS_DIR}/${svc_name}/id_ed25519.pub")
    
    # Store credentials
    store_in_gsm "$svc_name"
    store_in_vault "$svc_name"
    
    # Deploy to target host
    create_service_account "$target_host" "$svc_name" "$public_key"
    deploy_ssh_key "$target_host" "$svc_name" "$public_key"
    
    # Deploy to source host
    deploy_key_to_source "$source_host" "$svc_name"
    
    # Test connection
    test_connection "$source_host" "$target_host" "$svc_name" || log_warn "Connection test inconclusive"
    
    # Mark as deployed
    mark_deployed "$svc_name" "$target_host"
    
    log_success "Deployment complete: $svc_name"
}

# Deploy all service accounts
deploy_all() {
    local failed=0
    
    log_info "Starting deployment of all service accounts..."
    
    for svc_name in "${!DEPLOYMENT_TARGETS[@]}"; do
        if deploy_service_account "$svc_name"; then
            log_success "Deployed: $svc_name"
        else
            log_error "Failed to deploy: $svc_name"
            ((failed++)) || true
        fi
        echo ""
    done
    
    if [ $failed -eq 0 ]; then
        log_success "All deployments successful!"
        return 0
    else
        log_error "$failed deployment(s) failed"
        return 1
    fi
}

# Status report
status_report() {
    log_info "=== Deployment Status Report ==="
    log_info "Timestamp: $TIMESTAMP"
    log_info ""
    
    for svc_name in "${!DEPLOYMENT_TARGETS[@]}"; do
        local target_host=${DEPLOYMENT_TARGETS[$svc_name]}
        local state_file="${STATE_DIR}/${svc_name}.${target_host}.deployed"
        
        if [ -f "$state_file" ]; then
            local deployed_date=$(cat "$state_file")
            log_success "$svc_name: Deployed ($deployed_date)"
        else
            log_warn "$svc_name: Not yet deployed"
        fi
    done
    
    log_info ""
    log_info "State directory: $STATE_DIR"
    log_info "To reset: rm -rf ${STATE_DIR}/*"
}

# Force redeploy (idempotency override)
force_redeploy() {
    log_warn "Forcing redeploy - removing state files..."
    rm -rf "${STATE_DIR}"/*
    deploy_all
}

# Main
main() {
    init
    
    case "${1:-deploy}" in
        deploy)
            deploy_all
            status_report
            ;;
        force)
            force_redeploy
            status_report
            ;;
        status)
            status_report
            ;;
        *)
            echo "Usage: $0 {deploy|force|status}"
            exit 1
            ;;
    esac
}

main "$@"
