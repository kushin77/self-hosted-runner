#!/bin/bash

###############################################################################
# VAULT-BOOTSTRAP.SH
# 
# Automated Vault setup for direct-deploy credential provisioning.
# 
# Supports:
#   1. Local Docker-based dev Vault (requires docker-compose)
#   2. Remote SSH-based Vault initialization (requires ssh access + vault CLI)
#   3. Managed Vault endpoint (requires VAULT_ADDR + admin token)
# 
# Usage:
#   # Local dev setup (requires docker-compose)
#   bash scripts/vault-bootstrap.sh --mode=docker
#
#   # Remote Vault initialization (requires ssh access to vault-host)
#   bash scripts/vault-bootstrap.sh --mode=remote --vault-host=vault.example.com --vault-port=8200
#
#   # Use existing Vault (requires VAULT_ADDR + VAULT_TOKEN env vars)
#   export VAULT_ADDR="https://vault.example.com:8200"
#   export VAULT_TOKEN="your-admin-token"
#   bash scripts/vault-bootstrap.sh --mode=existing
#
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
MODE="${MODE:-auto}"
VAULT_HOST="${VAULT_HOST:-vault.example.com}"
VAULT_PORT="${VAULT_PORT:-8200}"
VAULT_SCHEME="${VAULT_SCHEME:-https}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode=*)
            MODE="${1#*=}"
            ;;
        --vault-host=*)
            VAULT_HOST="${1#*=}"
            ;;
        --vault-port=*)
            VAULT_PORT="${1#*=}"
            ;;
        --vault-scheme=*)
            VAULT_SCHEME="${1#*=}"
            ;;
        --help)
            grep "^# Usage:" "$0" -A 10
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            ;;
    esac
    shift
done

# Auto-detect mode
if [[ "$MODE" == "auto" ]]; then
    if command -v docker-compose >/dev/null 2>&1; then
        MODE="docker"
        log_info "Auto-detected docker-compose available; using docker mode"
    elif [[ -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" ]]; then
        MODE="existing"
        log_info "Auto-detected VAULT_ADDR and VAULT_TOKEN; using existing mode"
    else
        log_warn "Could not auto-detect Vault mode; defaulting to 'existing'."
        log_warn "Ensure VAULT_ADDR and VAULT_TOKEN are set in environment."
        MODE="existing"
    fi
fi

# ============================================================================
# DOCKER MODE: Start Vault via docker-compose
# ============================================================================
if [[ "$MODE" == "docker" ]]; then
    log_info "Starting Vault via docker-compose..."
    
    if [[ ! -f "$REPO_DIR/docker-compose.dev.yml" ]]; then
        log_error "docker-compose.dev.yml not found at $REPO_DIR"
    fi
    
    cd "$REPO_DIR"
    docker-compose -f docker-compose.dev.yml up -d vault
    sleep 3
    
    # Wait for health check
    max_retries=30
    retry_count=0
    while ! docker exec runner-vault-dev vault status >/dev/null 2>&1; do
        if (( retry_count >= max_retries )); then
            log_error "Vault failed to start after $max_retries retries"
        fi
        log_info "Waiting for Vault to be healthy... ($retry_count/$max_retries)"
        sleep 2
        ((retry_count++))
    done
    
    log_ok "Vault is healthy"
    
    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN="dev-token-12345"
    export VAULT_SKIP_VERIFY="true"
    
    log_ok "Set VAULT_ADDR=$VAULT_ADDR VAULT_TOKEN=***"

# ============================================================================
# REMOTE MODE: Initialize Vault on a remote host via SSH
# ============================================================================
elif [[ "$MODE" == "remote" ]]; then
    log_info "Setting up Vault on remote host $VAULT_HOST:$VAULT_PORT..."
    
    if ! command -v ssh >/dev/null 2>&1; then
        log_error "ssh command not found"
    fi
    
    # SSH into remote host and start Vault (if not already running)
    ssh -o ConnectTimeout=10 "root@$VAULT_HOST" << 'REMOTE_EOF'
        set -euo pipefail
        echo "[INFO] Checking Vault service..."
        
        if ! command -v vault >/dev/null 2>&1; then
            echo "[INFO] Installing Vault..."
            curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
            apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
            apt-get update && apt-get install -y vault
        fi
        
        if ! systemctl is-active --quiet vault; then
            echo "[INFO] Starting Vault service..."
            systemctl start vault || vault server -dev -dev-root-token-id="remote-token-$(date +%s)" &
            sleep 3
        fi
        
        echo "[OK] Vault is running"
REMOTE_EOF
    
    export VAULT_ADDR="$VAULT_SCHEME://$VAULT_HOST:$VAULT_PORT"
    # Token should be provided by operator
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warn "VAULT_TOKEN not set; you must provide it:"
        log_warn "  export VAULT_TOKEN='<your-admin-token>'"
    fi
    
    log_ok "Set VAULT_ADDR=$VAULT_ADDR"

# ============================================================================
# EXISTING MODE: Use pre-configured Vault endpoint
# ============================================================================
elif [[ "$MODE" == "existing" ]]; then
    log_info "Using existing Vault configuration..."
    
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_error "VAULT_ADDR not set. Export it: export VAULT_ADDR='https://vault.example.com:8200'"
    fi
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_TOKEN not set. Export it: export VAULT_TOKEN='your-admin-token'"
    fi
    
    log_ok "Using VAULT_ADDR=$VAULT_ADDR"
else
    log_error "Unknown mode: $MODE"
fi

# ============================================================================
# VERIFY VAULT CONNECTIVITY
# ============================================================================
log_info "Verifying Vault connectivity..."

if ! vault status >/dev/null 2>&1; then
    log_error "Cannot connect to Vault at $VAULT_ADDR. Check connectivity and token."
fi

log_ok "Vault is accessible"

# ============================================================================
# SETUP KV V2 SECRET ENGINE
# ============================================================================
log_info "Setting up KV v2 secret engine..."

if vault secrets list -format=json | jq -e '.["secret/"]' >/dev/null 2>&1; then
    log_ok "secret/ KV v2 engine already exists"
else
    log_info "Enabling secret/ KV v2 engine..."
    vault secrets enable -version=2 -path=secret kv >/dev/null 2>&1 || true
    log_ok "secret/ KV v2 engine enabled"
fi

# ============================================================================
# SETUP AUTH METHODS
# ============================================================================
log_info "Setting up auth methods..."

if vault auth list -format=json | jq -e '.["userpass/"]' >/dev/null 2>&1; then
    log_ok "userpass auth method already enabled"
else
    log_info "Enabling userpass auth method..."
    vault auth enable userpass >/dev/null 2>&1 || true
    log_ok "userpass auth method enabled"
fi

# ============================================================================
# OUTPUT CONFIGURATION
# ============================================================================
log_ok "=========================================="
log_ok "Vault Bootstrap Complete"
log_ok "=========================================="
echo ""
echo "Export these variables to use Vault:"
echo "  export VAULT_ADDR='$VAULT_ADDR'"
echo "  export VAULT_TOKEN='$VAULT_TOKEN'"
if [[ "${VAULT_SKIP_VERIFY:-}" == "true" ]]; then
    echo "  export VAULT_SKIP_VERIFY='true'"
fi
echo ""
echo "Next step: Provision SSH credentials"
echo "  bash scripts/deploy-operator-credentials.sh vault"
echo ""
