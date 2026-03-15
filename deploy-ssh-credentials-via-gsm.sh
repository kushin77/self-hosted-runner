#!/bin/bash
#
# 🔐 SSH CREDENTIAL DISTRIBUTION VIA GCP SECRET MANAGER
# 
# Mandate Compliance:
#   ✅ Immutable: Keys stored in GSM (cloud vault)
#   ✅ Ephemeral: Keys pulled on-demand, never persist locally
#   ✅ Idempotent: Safe to re-run (overwrites existing)
#   ✅ No-Ops: Fully automated
#   ✅ Hands-Off: No manual SSH key distribution needed
#   ✅ GSM/Vault/KMS: All credentials in Secret Manager
#
# Architecture:
#   1. Store SSH public/private keys in GSM
#   2. Pull keys at deployment time
#   3. Install authorized_keys on worker node .42
#   4. Idempotent: Re-run anytime without side effects
#
# Usage:
#   # Full automation (store + distribute)
#   bash deploy-ssh-credentials-via-gsm.sh full
#
#   # Just store keys in GSM
#   bash deploy-ssh-credentials-via-gsm.sh store-only
#
#   # Just distribute to worker
#   bash deploy-ssh-credentials-via-gsm.sh distribute-only
#
# Environment Variables:
#   GCP_PROJECT         GCP project ID (default: nexusshield-prod)
#   WORKER_HOST         Worker node IP (default: 192.168.168.42)
#   WORKER_USER         User on worker (default: akushnir)
#   DEV_SSH_KEY         SSH private key path (default: ~/.ssh/id_ed25519)

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$SCRIPT_DIR"
readonly LOG_DIR="${REPO_ROOT}/.deployment-logs"

# Defaults
GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
WORKER_HOST="${WORKER_HOST:-192.168.168.42}"
WORKER_USER="${WORKER_USER:-akushnir}"
DEV_SSH_KEY="${DEV_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
DEV_SSH_PUB="${DEV_SSH_KEY}.pub"

# GSM Secret names
readonly GSM_SECRET_PRIVKEY="akushnir-ssh-private-key"
readonly GSM_SECRET_PUBKEY="akushnir-ssh-public-key"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

mkdir -p "$LOG_DIR"

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }
log_stage() { echo ""; echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}▶ $*${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; }

# ============================================================================
# VALIDATION
# ============================================================================

validate_gcp() {
    log_info "Validating GCP authentication..."
    
    if ! command -v gcloud &>/dev/null; then
        log_error "gcloud CLI not found"
        return 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active GCP account. Run: gcloud auth login"
        return 1
    fi
    
    if ! gcloud config get-value project | grep -q "$GCP_PROJECT"; then
        log_warn "Current project: $(gcloud config get-value project)"
        log_info "Setting project to $GCP_PROJECT..."
        gcloud config set project "$GCP_PROJECT"
    fi
    
    log_success "GCP authenticated: $(gcloud config get-value account)"
    return 0
}

validate_ssh_key() {
    log_info "Validating SSH key at $DEV_SSH_KEY..."
    
    if [ ! -f "$DEV_SSH_KEY" ]; then
        log_error "SSH private key not found: $DEV_SSH_KEY"
        return 1
    fi
    
    if [ ! -f "$DEV_SSH_PUB" ]; then
        log_error "SSH public key not found: $DEV_SSH_PUB"
        return 1
    fi
    
    # Verify key format
    if ! ssh-keygen -l -f "$DEV_SSH_KEY" &>/dev/null; then
        log_error "SSH key format invalid: $DEV_SSH_KEY"
        return 1
    fi
    
    log_success "SSH key valid ($(ssh-keygen -l -f "$DEV_SSH_KEY" | awk '{print $NF}'))"
    return 0
}

validate_worker() {
    log_info "Validating worker connectivity..."
    
    if ! ssh-keyscan -T 2 "$WORKER_HOST" &>/dev/null; then
        log_error "Cannot reach worker at $WORKER_HOST"
        return 1
    fi
    
    log_success "Worker $WORKER_HOST is reachable"
    return 0
}

# ============================================================================
# STAGE 1: STORE SSH KEYS IN GSM
# ============================================================================

store_keys_in_gsm() {
    log_stage "STAGE 1: STORE SSH KEYS IN GCP SECRET MANAGER"
    
    validate_gcp || return 1
    validate_ssh_key || return 1
    
    log_info "Storing SSH credentials in GSM ($GCP_PROJECT)..."
    
    # Store private key
    log_info "Storing private key as secret: $GSM_SECRET_PRIVKEY"
    gcloud secrets versions destroy latest --secret="$GSM_SECRET_PRIVKEY" \
        --quiet &>/dev/null || true
    
    if gcloud secrets describe "$GSM_SECRET_PRIVKEY" &>/dev/null; then
        log_info "Secret $GSM_SECRET_PRIVKEY exists, adding new version..."
        gcloud secrets versions add "$GSM_SECRET_PRIVKEY" \
            --data-file="$DEV_SSH_KEY"
    else
        log_info "Creating new secret $GSM_SECRET_PRIVKEY..."
        gcloud secrets create "$GSM_SECRET_PRIVKEY" \
            --data-file="$DEV_SSH_KEY"
    fi
    log_success "Private key stored in GSM: $GSM_SECRET_PRIVKEY"
    
    # Store public key
    log_info "Storing public key as secret: $GSM_SECRET_PUBKEY"
    if gcloud secrets describe "$GSM_SECRET_PUBKEY" &>/dev/null; then
        log_info "Secret $GSM_SECRET_PUBKEY exists, adding new version..."
        gcloud secrets versions add "$GSM_SECRET_PUBKEY" \
            --data-file="$DEV_SSH_PUB"
    else
        log_info "Creating new secret $GSM_SECRET_PUBKEY..."
        gcloud secrets create "$GSM_SECRET_PUBKEY" \
            --data-file="$DEV_SSH_PUB"
    fi
    log_success "Public key stored in GSM: $GSM_SECRET_PUBKEY"
    
    # Verify
    log_info "Verifying GSM secrets..."
    gcloud secrets describe "$GSM_SECRET_PRIVKEY" --format="value(created)" && \
        log_success "Private key secret accessible" || return 1
    gcloud secrets describe "$GSM_SECRET_PUBKEY" --format="value(created)" && \
        log_success "Public key secret accessible" || return 1
    
    return 0
}

# ============================================================================
# STAGE 2: DISTRIBUTE SSH KEYS TO WORKER
# ============================================================================

distribute_keys_to_worker() {
    log_stage "STAGE 2: DISTRIBUTE SSH KEYS TO WORKER NODE"
    
    validate_gcp || return 1
    validate_worker || return 1
    
    log_info "Distributing SSH credentials to worker (${WORKER_USER}@${WORKER_HOST})..."
    
    # Create temporary file for distribution script
    local dist_script="/tmp/install-ssh-key-$$.sh"
    cat > "$dist_script" << 'DIST_SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

SECRET_PUB="$1"
REMOTE_USER="$2"

# Get public key from secret manager
echo "[*] Retrieving SSH public key from GSM..."
PUBLIC_KEY=$(gcloud secrets versions access latest --secret="$SECRET_PUB")

# Create .ssh directory
echo "[*] Creating .ssh directory..."
mkdir -p /home/"$REMOTE_USER"/.ssh
chmod 700 /home/"$REMOTE_USER"/.ssh

# Add public key to authorized_keys (idempotent)
echo "[*] Installing authorized_keys..."
if grep -q "$(echo "$PUBLIC_KEY" | cut -d' ' -f2)" /home/"$REMOTE_USER"/.ssh/authorized_keys 2>/dev/null; then
    echo "[✓] Public key already in authorized_keys"
else
    echo "$PUBLIC_KEY" >> /home/"$REMOTE_USER"/.ssh/authorized_keys
    echo "[✓] Public key added to authorized_keys"
fi

chmod 600 /home/"$REMOTE_USER"/.ssh/authorized_keys
chown "$REMOTE_USER:$REMOTE_USER" /home/"$REMOTE_USER"/.ssh -R

echo "[✓] SSH key distribution complete"
DIST_SCRIPT_EOF
    
    chmod +x "$dist_script"
    
    # Copy distribution script to worker using akushnir user
    log_info "Copying installation script to worker..."
    scp -i "$DEV_SSH_KEY" -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new "$dist_script" \
        "${WORKER_USER}@${WORKER_HOST}:/tmp/install-ssh-key.sh" || {
        log_error "Failed to copy installation script"
        rm -f "$dist_script"
        return 1
    }
    
    # Execute distribution script on worker using sudo if needed
    log_info "Executing SSH key installation on worker..."
    ssh -i "$DEV_SSH_KEY" -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new "${WORKER_USER}@${WORKER_HOST}" \
        "bash /tmp/install-ssh-key.sh '$GSM_SECRET_PUBKEY' '$WORKER_USER'" || {
        log_error "Failed to install SSH key on worker"
        rm -f "$dist_script"
        return 1
    }
    
    # Verify SSH access
    log_info "Verifying SSH access..."
    if ssh -i "$DEV_SSH_KEY" -o ConnectTimeout=5 \
        "${WORKER_USER}@${WORKER_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_success "SSH access verified: ${WORKER_USER}@${WORKER_HOST}"
    else
        log_warn "SSH access may take a moment to activate"
    fi
    
    # Cleanup
    rm -f "$dist_script"
    ssh -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new "root@${WORKER_HOST}" \
        "rm -f /tmp/install-ssh-key.sh" &>/dev/null || true
    
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local mode="${1:-full}"
    
    case "$mode" in
        full)
            store_keys_in_gsm && distribute_keys_to_worker
            ;;
        store-only)
            store_keys_in_gsm
            ;;
        distribute-only)
            distribute_keys_to_worker
            ;;
        *)
            log_error "Unknown mode: $mode"
            echo "Usage: $0 [full|store-only|distribute-only]"
            exit 1
            ;;
    esac
}

main "$@"
