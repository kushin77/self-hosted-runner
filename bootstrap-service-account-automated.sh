#!/bin/bash
# SERVICE ACCOUNT BOOTSTRAP - FULLY AUTOMATED
# Direct deployment with GSM credential management
# Idempotent, ephemeral, hands-off operation

set -euo pipefail
trap 'handle_error $? $LINENO' ERR

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$SCRIPT_DIR"
readonly WORKER_IP="192.168.168.42"
readonly WORKER_USER="elevatediq-svc-worker-dev"
readonly SSH_KEY="${WORKSPACE_ROOT}/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519"
readonly GSM_PROJECT="${GCP_PROJECT_ID:-nexusshield-prod}"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs/bootstrap"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_FILE="${LOG_DIR}/bootstrap-${TIMESTAMP}.log"

# SSH Key-Only Mandate
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}▶${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; }
log_phase() { echo -e "\n${MAGENTA}──────────────────────────────────────${NC}" | tee -a "$LOG_FILE"; echo -e "${MAGENTA}▶ $1${NC}" | tee -a "$LOG_FILE"; }

handle_error() {
    local exit_code=$1
    local line_no=$2
    log_error "Bootstrap failed at line $line_no with exit code $exit_code"
    log_info "Review log: $LOG_FILE"
    exit "$exit_code"
}

# Initialize directories
setup_logging() {
    mkdir -p "$LOG_DIR"
    log_info "Bootstrap started at $TIMESTAMP"
    log_info "Log file: $LOG_FILE"
}

# Verify prerequisites
verify_prerequisites() {
    log_phase "PHASE 1: VERIFYING PREREQUISITES"
    
    # Check SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "Service account SSH key not found: $SSH_KEY"
        return 1
    fi
    chmod 600 "$SSH_KEY"
    log_success "Service account SSH key found"
    
    # Check worker connectivity
    log_info "Testing network connectivity to $WORKER_IP..."
    if ! ping -c 1 -W 2 "$WORKER_IP" &>/dev/null; then
        log_error "Worker node $WORKER_IP unreachable"
        return 1
    fi
    log_success "Worker node reachable"
    
    # Verify required commands
    for cmd in ssh scp gcloud; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    log_success "All required commands available"
}

# Check if service account already exists on worker
check_existing_account() {
    log_phase "PHASE 2: CHECKING EXISTING SERVICE ACCOUNT"
    
    if timeout 5 ssh -o BatchMode=yes -i "$SSH_KEY" -o ConnectTimeout=2 \
        "$WORKER_USER@$WORKER_IP" "whoami" &>/dev/null 2>&1; then
        log_info "Service account $WORKER_USER already bootstrapped on $WORKER_IP"
        log_success "Bootstrap already complete (idempotent verification)"
        return 0
    else
        log_warn "Service account not yet bootstrapped"
        return 1
    fi
}

# Create bootstrap script for remote execution
create_bootstrap_script() {
    log_phase "PHASE 3: CREATING BOOTSTRAP SCRIPT"
    
    local bootstrap_script="/tmp/bootstrap-${TIMESTAMP}.sh"
    
    cat > "$bootstrap_script" << 'BOOTSTRAP_REMOTE'
#!/bin/bash
set -euo pipefail

SERVICE_ACCOUNT="elevatediq-svc-worker-dev"
PUBLIC_KEY="$1"

# Create service account (idempotent)
if ! id "$SERVICE_ACCOUNT" &>/dev/null 2>&1; then
    echo "[INFO] Creating service account: $SERVICE_ACCOUNT"
    sudo useradd -r -s /bin/bash -m -d "/home/$SERVICE_ACCOUNT" "$SERVICE_ACCOUNT" 2>/dev/null || true
else
    echo "[INFO] Service account $SERVICE_ACCOUNT already exists (idempotent)"
fi

# Create SSH directory
sudo mkdir -p "/home/$SERVICE_ACCOUNT/.ssh"
sudo chmod 700 "/home/$SERVICE_ACCOUNT/.ssh"

# Add public key (idempotent - checks for duplicates)
if ! sudo grep -q "$PUBLIC_KEY" "/home/$SERVICE_ACCOUNT/.ssh/authorized_keys" 2>/dev/null; then
    echo "[INFO] Adding public key to authorized_keys"
    echo "$PUBLIC_KEY" | sudo tee -a "/home/$SERVICE_ACCOUNT/.ssh/authorized_keys" > /dev/null
else
    echo "[INFO] Public key already in authorized_keys (idempotent)"
fi

# Fix permissions
sudo chmod 600 "/home/$SERVICE_ACCOUNT/.ssh/authorized_keys"
sudo chown -R "$SERVICE_ACCOUNT:$SERVICE_ACCOUNT" "/home/$SERVICE_ACCOUNT/.ssh"

# Create audit marker
echo "[✓] Service account bootstrap complete at $(date -u)" | \
    sudo tee "/home/$SERVICE_ACCOUNT/.bootstrap-complete" > /dev/null

echo "[SUCCESS] Bootstrap complete for $SERVICE_ACCOUNT"
BOOTSTRAP_REMOTE
    
    chmod +x "$bootstrap_script"
    log_success "Bootstrap script created: $bootstrap_script"
    echo "$bootstrap_script"
}

# Execute bootstrap on worker (with fallback for initial connection)
execute_bootstrap() {
    log_phase "PHASE 4: EXECUTING BOOTSTRAP ON WORKER"
    
    local bootstrap_script=$(create_bootstrap_script)
    local public_key_file="${SSH_KEY}.pub"
    
    if [[ ! -f "$public_key_file" ]]; then
        log_error "Public key file not found: $public_key_file"
        return 1
    fi
    
    local public_key=$(cat "$public_key_file")
    
    # Try to execute bootstrap script
    log_info "Executing bootstrap script on $WORKER_IP..."
    
    # First attempt: direct SSH as root (if initial key auth works)
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
        -i "$SSH_KEY" "elevatediq@$WORKER_IP" \
        bash "$bootstrap_script" "$public_key" 2>/dev/null; then
        log_success "Bootstrap executed successfully"
        return 0
    fi
    
    # Second attempt: copy script and execute via sudo
    log_info "Executing via alternative method..."
    if scp -o ConnectTimeout=2 -i "$SSH_KEY" "$bootstrap_script" \
        "elevatediq@$WORKER_IP:/tmp/" 2>/dev/null && \
       ssh -o ConnectTimeout=2 -i "$SSH_KEY" "elevatediq@$WORKER_IP" \
        "bash /tmp/$(basename "$bootstrap_script") '$public_key'" 2>/dev/null; then
        log_success "Bootstrap executed via SCP method"
        return 0
    fi
    
    # Note: If both fail, the service account may need manual setup
    log_warn "Bootstrap execution requires administrative access to $WORKER_IP"
    log_info "Please run manually or provide BMC/console access"
    return 1
}

# Verify bootstrap completion
verify_bootstrap() {
    log_phase "PHASE 5: VERIFYING BOOTSTRAP"
    
    if timeout 5 ssh -o BatchMode=yes -i "$SSH_KEY" -o ConnectTimeout=2 \
        "$WORKER_USER@$WORKER_IP" "whoami && hostname" > /dev/null 2>&1; then
        log_success "Service account SSH access verified"
        log_success "Worker node: $WORKER_IP"
        log_success "Service account: $WORKER_USER"
        return 0
    else
        log_error "Service account SSH access verification failed"
        return 1
    fi
}

# Store verification in GSM
store_bootstrap_record() {
    log_phase "PHASE 6: STORING BOOTSTRAP AUDIT RECORD"
    
    local record_file="/tmp/bootstrap-record-${TIMESTAMP}.json"
    
    cat > "$record_file" << EOF
{
  "timestamp": "$TIMESTAMP",
  "hostname": "$(hostname -f)",
  "user": "$(whoami)",
  "worker_ip": "$WORKER_IP",
  "service_account": "$WORKER_USER",
  "status": "complete",
  "method": "automated_bootstrap_script",
  "ssh_key_type": "Ed25519",
  "audit_log": "$(cat "$LOG_FILE" | base64 -w0)"
}
EOF

    log_info "Bootstrap record created: $record_file"
    
    # Store in GSM if available
    if command -v gcloud &>/dev/null; then
        if gcloud secrets create "nas-monitoring-bootstrap-${TIMESTAMP}" \
            --data-file="$record_file" \
            --project="$GSM_PROJECT" 2>/dev/null; then
            log_success "Bootstrap record stored in GSM"
        else
            log_warn "GSM storage failed (non-critical)"
        fi
    fi
    
    log_success "Audit record: $record_file"
}

# Show deployment readiness
show_readiness() {
    log_phase "DEPLOYMENT READINESS STATUS"
    
    echo ""
    echo "  ${GREEN}✓${NC} Service account bootstrapped"
    echo "  ${GREEN}✓${NC} SSH key-based authentication verified"
    echo "  ${GREEN}✓${NC} Worker node connectivity confirmed"
    echo "  ${GREEN}✓${NC} Audit trail recorded"
    echo ""
    echo "  ${BLUE}Ready for NAS monitoring deployment:${NC}"
    echo "  ${YELLOW}$ cd $WORKSPACE_ROOT${NC}"
    echo "  ${YELLOW}$ ./deploy-nas-monitoring-now.sh${NC}"
    echo ""
}

# Main execution flow
main() {
    setup_logging
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  SERVICE ACCOUNT BOOTSTRAP - FULLY AUTOMATED                  ║"
    echo "║  Worker: $WORKER_IP                                    ║"
    echo "║  Service Account: $WORKER_USER                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    verify_prerequisites
    
    # Check if already bootstrapped (idempotent)
    if check_existing_account; then
        log_success "Service account already initialized"
    else
        # Execute bootstrap
        execute_bootstrap || {
            log_warn "Automated bootstrap requires administrator access to worker"
            log_info "Alternative: Manual bootstrap via SERVICE_ACCOUNT_BOOTSTRAP.md"
            echo ""
            echo "  To proceed manually, copy these commands to 192.168.168.42:"
            echo ""
            grep -A 1 "^##" "$SCRIPT_DIR/SERVICE_ACCOUNT_BOOTSTRAP.md" | head -30 || true
            return 1
        }
    fi
    
    # Verify bootstrap success
    verify_bootstrap
    
    # Store audit record
    store_bootstrap_record
    
    # Show next steps
    show_readiness
    
    log_success "Bootstrap complete!"
}

# Execute
main "$@"
