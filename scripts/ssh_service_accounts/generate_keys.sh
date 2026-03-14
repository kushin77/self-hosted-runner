#!/bin/bash
# Generate SSH keys for service accounts and store them in GSM
# This is part 1 of the setup - generates keys locally before remote deployment

set -e

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_DIR="${WORKSPACE_ROOT}/secrets/ssh"

# Service account names (sourced from key pairs needed)
SERVICE_ACCOUNTS=(
    "elevatediq-svc-worker-dev"      # .31 → .42
    "elevatediq-svc-worker-nas"      # .39 → .42
    "elevatediq-svc-dev-nas"         # .31 → .39
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

create_key() {
    local svc_name=$1
    local key_dir="${SECRETS_DIR}/${svc_name}"
    
    if [ -f "${key_dir}/id_ed25519" ]; then
        log_warn "Key already exists for $svc_name, skipping generation"
        cat "${key_dir}/id_ed25519.pub"
        return 0
    fi
    
    mkdir -p "$key_dir"
    
    log_info "Generating SSH key pair for $svc_name..."
    ssh-keygen -t ed25519 -f "${key_dir}/id_ed25519" -N "" \
        -C "${svc_name}@$(hostname -f)" >/dev/null 2>&1
    
    chmod 600 "${key_dir}/id_ed25519"
    chmod 644 "${key_dir}/id_ed25519.pub"
    
    log_success "Generated key: ${key_dir}/id_ed25519"
    cat "${key_dir}/id_ed25519.pub"
}

store_in_gsm() {
    local svc_name=$1
    local key_path="${SECRETS_DIR}/${svc_name}/id_ed25519"
    
    if [ ! -f "$key_path" ]; then
        log_error "Key file not found: $key_path"
        return 1
    fi
    
    if ! command -v gcloud &> /dev/null; then
        log_warn "gcloud not found, skipping GSM storage"
        return 0
    fi
    
    log_info "Storing $svc_name private key in Google Secret Manager..."
    
    if gcloud secrets describe "$svc_name" &>/dev/null 2>&1; then
        gcloud secrets versions add "$svc_name" --data-file="$key_path" 2>/dev/null || true
        log_success "Added new version to GSM secret: $svc_name"
    else
        gcloud secrets create "$svc_name" --data-file="$key_path" 2>/dev/null || true
        log_success "Created GSM secret: $svc_name"
    fi
}

main() {
    log_info "Starting SSH key generation for service accounts..."
    mkdir -p "$SECRETS_DIR"
    
    for svc_name in "${SERVICE_ACCOUNTS[@]}"; do
        echo ""
        log_info "Processing: $svc_name"
        log_info "========================================"
        
        public_key=$(create_key "$svc_name")
        store_in_gsm "$svc_name"
        
        echo ""
        echo "Public key for $svc_name:"
        echo "$public_key"
        echo ""
    done
    
    log_success "Key generation completed!"
    echo ""
    echo "Summary:"
    echo "========================================="
    for svc_name in "${SERVICE_ACCOUNTS[@]}"; do
        if [ -f "${SECRETS_DIR}/${svc_name}/id_ed25519" ]; then
            echo "✓ $svc_name"
            echo "  Private key: ${SECRETS_DIR}/${svc_name}/id_ed25519"
            echo "  Public key:  ${SECRETS_DIR}/${svc_name}/id_ed25519.pub"
        fi
    done
}

main "$@"
