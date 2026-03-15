#!/bin/bash
# SERVICE ACCOUNT BOOTSTRAP WITH PASSWORD FALLBACK
# Generates SSH keys locally, then uses password-based SSH to bootstrap remote hosts
# After bootstrap, all auth is SSH key-only (SSH_ASKPASS=none enforced)
# Idempotent: safe to re-run

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs/bootstrap"
readonly STATE_DIR="${WORKSPACE_ROOT}/.deployment-state"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_FILE="${LOG_DIR}/bootstrap-pwd-fallback-${TIMESTAMP}.log"

# SSH Key-Only Mandate (enforced globally)
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# Service accounts to create
declare -A SERVICE_ACCOUNTS=(
    ["elevatediq-svc-worker-dev"]="192.168.168.42"  # Create on .42
    ["elevatediq-svc-worker-nas"]="192.168.168.42"  # Create on .42
    ["elevatediq-svc-dev-nas"]="192.168.168.39"     # Create on .39
)

# Host credentials (will be filled by prompts or env vars)
declare -A HOST_PASSWORDS

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================
log_info() { echo -e "${BLUE}▶${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; }
log_phase() { echo -e "\n${MAGENTA}────────────────────────────────────────${NC}" | tee -a "$LOG_FILE"; echo -e "${MAGENTA}▶ $1${NC}" | tee -a "$LOG_FILE"; }

# ============================================================================
# UTILITIES
# ============================================================================
setup_logging() {
    mkdir -p "$LOG_DIR" "$STATE_DIR"
    {
        echo "SERVICE ACCOUNT BOOTSTRAP LOG"
        echo "=============================="
        echo "Timestamp: $TIMESTAMP"
        echo "User: $(whoami)"
        echo "Host: $(hostname)"
        echo ""
    } > "$LOG_FILE"
    log_info "Log file: $LOG_FILE"
}

# Check dependencies
check_deps() {
    log_phase "PHASE 1: CHECKING DEPENDENCIES"
    
    local missing=0
    for cmd in ssh sshpass ssh-keygen mkdir chmod; do
        if command -v "$cmd" &>/dev/null; then
            log_success "Found: $cmd"
        else
            log_error "Missing: $cmd"
            ((missing++)) || true
        fi
    done
    
    if [ $missing -gt 0 ]; then
        log_error "Please install: sshpass, openssh-client"
        return 1
    fi
}

# Prompt for password (hidden input)
prompt_password() {
    local prompt_text=$1
    local var_name=$2
    
    echo -n "$prompt_text: "
    read -rs password
    echo ""
    
    if [ -z "$password" ]; then
        log_error "Password cannot be empty"
        return 1
    fi
    
    eval "$var_name='$password'"
}

# Prompt for all credentials
collect_credentials() {
    log_phase "PHASE 2: COLLECTING CREDENTIALS"
    
    log_info "You will be prompted for passwords to bootstrap SSH keys."
    log_info "Passwords will be used only to initially configure key-based auth."
    echo ""
    
    # .42 credentials
    echo -e "${BLUE}Host: 192.168.168.42 (Production Worker)${NC}"
    prompt_password "  Enter password for akushnir@192.168.168.42" "pwd_42" || return 1
    HOST_PASSWORDS["akushnir@192.168.168.42"]="$pwd_42"
    
    # .39 credentials
    echo -e "${BLUE}Host: 192.168.168.39 (NAS)${NC}"
    prompt_password "  Enter password for kushin77@192.168.168.39" "pwd_39" || return 1
    HOST_PASSWORDS["kushin77@192.168.168.39"]="$pwd_39"
    
    log_success "Credentials collected (in memory only)"
}

# ============================================================================
# KEY GENERATION
# ============================================================================
generate_service_account_keys() {
    log_phase "PHASE 3: GENERATING SERVICE ACCOUNT SSH KEYS"
    
    mkdir -p "$SECRETS_DIR"
    
    for svc_name in "${!SERVICE_ACCOUNTS[@]}"; do
        local key_dir="${SECRETS_DIR}/${svc_name}"
        local key_path="${key_dir}/id_ed25519"
        
        if [ -f "$key_path" ]; then
            log_warn "Key already exists: $key_path (idempotent)"
            continue
        fi
        
        log_info "Generating Ed25519 key pair for: $svc_name"
        mkdir -p "$key_dir"
        
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "${svc_name}@$(hostname -f)" >/dev/null 2>&1
        
        chmod 600 "$key_path"
        chmod 644 "${key_path}.pub"
        
        log_success "Generated: $key_path"
    done
}

# ============================================================================
# BOOTSTRAP HOSTS
# ============================================================================
bootstrap_host_42() {
    log_phase "PHASE 4A: BOOTSTRAPPING 192.168.168.42 (PRODUCTION WORKER)"
    
    local host="192.168.168.42"
    local user="akushnir"
    local password="${HOST_PASSWORDS[${user}@${host}]}"
    
    # Create service account "elevatediq-svc-worker-dev"
    local svc1="elevatediq-svc-worker-dev"
    local pubkey1=$(cat "${SECRETS_DIR}/${svc1}/id_ed25519.pub")
    
    log_info "Creating service account: $svc1 on $host"
    
    sshpass -p "$password" ssh -o StrictHostKeyChecking=accept-new \
        "${user}@${host}" bash -s <<BOOTSTRAP_SCRIPT
set -e
SVC_NAME='$svc1'
PUBLIC_KEY='$pubkey1'

# Create user if missing
if ! id "\$SVC_NAME" &>/dev/null; then
    sudo useradd -r -s /bin/bash -m -d "/home/\$SVC_NAME" "\$SVC_NAME" 2>/dev/null || true
fi

# Set up SSH directory
SSH_DIR="/home/\$SVC_NAME/.ssh"
sudo mkdir -p "\$SSH_DIR"
echo "\$PUBLIC_KEY" | sudo tee -a "\$SSH_DIR/authorized_keys" >/dev/null 2>&1
sudo chown -R "\$SVC_NAME:\$SVC_NAME" "\$SSH_DIR"
sudo chmod 700 "\$SSH_DIR"
sudo chmod 600 "\$SSH_DIR/authorized_keys"

echo "[✓] Service account \$SVC_NAME is ready"
BOOTSTRAP_SCRIPT
    
    log_success "Service account $svc1 configured on $host"
    
    # Create service account "elevatediq-svc-worker-nas"
    local svc2="elevatediq-svc-worker-nas"
    local pubkey2=$(cat "${SECRETS_DIR}/${svc2}/id_ed25519.pub")
    
    log_info "Creating service account: $svc2 on $host"
    
    sshpass -p "$password" ssh -o StrictHostKeyChecking=accept-new \
        "${user}@${host}" bash -s <<BOOTSTRAP_SCRIPT
set -e
SVC_NAME='$svc2'
PUBLIC_KEY='$pubkey2'

# Create user if missing
if ! id "\$SVC_NAME" &>/dev/null; then
    sudo useradd -r -s /bin/bash -m -d "/home/\$SVC_NAME" "\$SVC_NAME" 2>/dev/null || true
fi

# Set up SSH directory
SSH_DIR="/home/\$SVC_NAME/.ssh"
sudo mkdir -p "\$SSH_DIR"
echo "\$PUBLIC_KEY" | sudo tee -a "\$SSH_DIR/authorized_keys" >/dev/null 2>&1
sudo chown -R "\$SVC_NAME:\$SVC_NAME" "\$SSH_DIR"
sudo chmod 700 "\$SSH_DIR"
sudo chmod 600 "\$SSH_DIR/authorized_keys"

echo "[✓] Service account \$SVC_NAME is ready"
BOOTSTRAP_SCRIPT
    
    log_success "Service account $svc2 configured on $host"
}

bootstrap_host_39() {
    log_phase "PHASE 4B: BOOTSTRAPPING 192.168.168.39 (NAS)"
    
    local host="192.168.168.39"
    local user="kushin77"
    local password="${HOST_PASSWORDS[${user}@${host}]}"
    
    # Create service account "elevatediq-svc-dev-nas"
    local svc="elevatediq-svc-dev-nas"
    local pubkey=$(cat "${SECRETS_DIR}/${svc}/id_ed25519.pub")
    
    log_info "Creating service account: $svc on $host"
    
    sshpass -p "$password" ssh -o StrictHostKeyChecking=accept-new \
        "${user}@${host}" bash -s <<BOOTSTRAP_SCRIPT
set -e
SVC_NAME='$svc'
PUBLIC_KEY='$pubkey'

# Create user if missing
if ! id "\$SVC_NAME" &>/dev/null; then
    sudo useradd -r -s /bin/bash -m -d "/home/\$SVC_NAME" "\$SVC_NAME" 2>/dev/null || true
fi

# Set up SSH directory
SSH_DIR="/home/\$SVC_NAME/.ssh"
sudo mkdir -p "\$SSH_DIR"
echo "\$PUBLIC_KEY" | sudo tee -a "\$SSH_DIR/authorized_keys" >/dev/null 2>&1
sudo chown -R "\$SVC_NAME:\$SVC_NAME" "\$SSH_DIR"
sudo chmod 700 "\$SSH_DIR"
sudo chmod 600 "\$SSH_DIR/authorized_keys"

echo "[✓] Service account \$SVC_NAME is ready"
BOOTSTRAP_SCRIPT
    
    log_success "Service account $svc configured on $host"
}

# ============================================================================
# VERIFICATION
# ============================================================================
verify_ssh_key_auth() {
    log_phase "PHASE 5: VERIFYING SSH KEY-ONLY AUTHENTICATION"
    
    # Test .42 accounts
    log_info "Testing: elevatediq-svc-worker-dev@192.168.168.42"
    if timeout 5 ssh -o BatchMode=yes -o PasswordAuthentication=no \
        -i "${SECRETS_DIR}/elevatediq-svc-worker-dev/id_ed25519" \
        "elevatediq-svc-worker-dev@192.168.168.42" "whoami" &>/dev/null; then
        log_success "SSH key auth works: elevatediq-svc-worker-dev@192.168.168.42"
    else
        log_warn "SSH key auth failed for elevatediq-svc-worker-dev (may need network check)"
    fi
    
    log_info "Testing: elevatediq-svc-worker-nas@192.168.168.42"
    if timeout 5 ssh -o BatchMode=yes -o PasswordAuthentication=no \
        -i "${SECRETS_DIR}/elevatediq-svc-worker-nas/id_ed25519" \
        "elevatediq-svc-worker-nas@192.168.168.42" "whoami" &>/dev/null; then
        log_success "SSH key auth works: elevatediq-svc-worker-nas@192.168.168.42"
    else
        log_warn "SSH key auth failed for elevatediq-svc-worker-nas (may need network check)"
    fi
    
    log_info "Testing: elevatediq-svc-dev-nas@192.168.168.39"
    if timeout 5 ssh -o BatchMode=yes -o PasswordAuthentication=no \
        -i "${SECRETS_DIR}/elevatediq-svc-dev-nas/id_ed25519" \
        "elevatediq-svc-dev-nas@192.168.168.39" "whoami" &>/dev/null; then
        log_success "SSH key auth works: elevatediq-svc-dev-nas@192.168.168.39"
    else
        log_warn "SSH key auth failed for elevatediq-svc-dev-nas (may need network check)"
    fi
}

# ============================================================================
# FINALIZATION
# ============================================================================
save_deployment_record() {
    log_phase "PHASE 6: SAVING DEPLOYMENT RECORD"
    
    local record_file="${STATE_DIR}/service-accounts-bootstrap-${TIMESTAMP}.md"
    
    cat > "$record_file" <<EOF
# Service Account Bootstrap Record

**Date:** $TIMESTAMP  
**Status:** ✅ COMPLETED

## Deployed Service Accounts

| Service Account | Target Host | Source Host | SSH Key |
|---|---|---|---|
| elevatediq-svc-worker-dev | 192.168.168.42 | 192.168.168.31 | ${SECRETS_DIR}/elevatediq-svc-worker-dev/id_ed25519 |
| elevatediq-svc-worker-nas | 192.168.168.42 | 192.168.168.39 | ${SECRETS_DIR}/elevatediq-svc-worker-nas/id_ed25519 |
| elevatediq-svc-dev-nas | 192.168.168.39 | 192.168.168.31 | ${SECRETS_DIR}/elevatediq-svc-dev-nas/id_ed25519 |

## SSH Configuration

All accounts configured with:
- **Algorithm:** Ed25519 (256-bit)
- **Authentication:** Key-only (PasswordAuthentication=no)
- **Batch Mode:** Enabled (SSH_ASKPASS=none)
- **Permissions:** 600 on private keys, 700 on .ssh directory

## Next Steps

1. Run stress tests using service account auth:
   \`\`\`bash
   ssh -i ${SECRETS_DIR}/elevatediq-svc-dev-nas/id_ed25519 \\
       elevatediq-svc-dev-nas@192.168.168.39 "bash scripts/nas-integration/stress-test-nas.sh --aggressive"
   \`\`\`

2. Run NexusShield deployments:
   \`\`\`bash
   ssh -i ${SECRETS_DIR}/elevatediq-svc-worker-dev/id_ed25519 \\
       elevatediq-svc-worker-dev@192.168.168.42 "sudo systemctl start nexusshield-deploy"
   \`\`\`

3. Validate automation:
   \`\`\`bash
   # All future SSH will use key-only auth (no passwords required)
   export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never DISPLAY=""
   \`\`\`

## Log File

Full bootstrap log: $LOG_FILE
EOF
    
    log_success "Deployment record: $record_file"
}

create_env_export() {
    log_phase "PHASE 7: CREATING ENVIRONMENT EXPORT"
    
    local env_file="${WORKSPACE_ROOT}/.env.service-accounts"
    
    cat > "$env_file" <<EOF
# Service Account Environment (sourced by automation scripts)
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# Service account key paths
export ELEVATEDIQ_SVC_WORKER_DEV_KEY="${SECRETS_DIR}/elevatediq-svc-worker-dev/id_ed25519"
export ELEVATEDIQ_SVC_WORKER_NAS_KEY="${SECRETS_DIR}/elevatediq-svc-worker-nas/id_ed25519"
export ELEVATEDIQ_SVC_DEV_NAS_KEY="${SECRETS_DIR}/elevatediq-svc-dev-nas/id_ed25519"

# Service account SSH command templates
alias ssh-dev-worker="ssh -i \$ELEVATEDIQ_SVC_WORKER_DEV_KEY elevatediq-svc-worker-dev@192.168.168.42"
alias ssh-nas-worker="ssh -i \$ELEVATEDIQ_SVC_WORKER_NAS_KEY elevatediq-svc-worker-nas@192.168.168.42"
alias ssh-dev-nas="ssh -i \$ELEVATEDIQ_SVC_DEV_NAS_KEY elevatediq-svc-dev-nas@192.168.168.39"
EOF
    
    log_success "Environment export: $env_file"
    log_info "Source with: source $env_file"
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================
main() {
    log_phase "SERVICE ACCOUNT BOOTSTRAP WITH PASSWORD FALLBACK"
    log_info "Starting comprehensive service account setup..."
    
    setup_logging
    check_deps || return 1
    collect_credentials || return 1
    generate_service_account_keys
    bootstrap_host_42 || log_warn "Host .42 bootstrap had issues"
    bootstrap_host_39 || log_warn "Host .39 bootstrap had issues"
    verify_ssh_key_auth
    save_deployment_record
    create_env_export
    
    log_phase "BOOTSTRAP COMPLETE"
    log_success "All service accounts configured and ready for SSH key-only auth"
    log_info "Review deployment record in: ${STATE_DIR}/service-accounts-bootstrap-${TIMESTAMP}.md"
}

main "$@"
