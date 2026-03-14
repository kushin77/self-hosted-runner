#!/bin/bash
# OPERATOR INJECTION: Create New AppRole on Local Vault
# Creates a new AppRole if the original Vault cluster is unavailable
# Usage: bash scripts/ops/OPERATOR_CREATE_NEW_APPROLE.sh --vault-root-token s.xxx

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly VAULT_CONFIG="/etc/vault/vault.hcl"
readonly VAULT_AUDIT_LOG="${WORKSPACE_ROOT}/logs/vault-recreate-audit.jsonl"
readonly VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
readonly TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
readonly APPROLE_NAME="nexusshield-prod-agent"
readonly POLICY_NAME="database-dynamic-credentials"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_step() { echo -e "${YELLOW}▶${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_secret() { echo -e "${YELLOW}[SECRET]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vault-root-token) VAULT_ROOT_TOKEN="$2"; shift 2 ;;
        --vault-server) VAULT_ADDR="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "${VAULT_ROOT_TOKEN:-}" ]; then
    log_error "Missing required argument: --vault-root-token"
    echo "Usage: $0 --vault-root-token s.xxx [--vault-server http://127.0.0.1:8200]"
    exit 1
fi

# Initialize audit log
mkdir -p "$(dirname "$VAULT_AUDIT_LOG")"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_creation_started\",\"vault_addr\":\"$VAULT_ADDR\",\"user\":\"${USER}\"}" >> "$VAULT_AUDIT_LOG"

log_step "Creating new AppRole on local Vault"
log_info "Vault Address: $VAULT_ADDR"
log_info "AppRole Name: $APPROLE_NAME"

# Export Vault token (temporary, to be revoked)
export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
export VAULT_ADDR="$VAULT_ADDR"

# Verify root token works
log_step "Verifying Vault access with provided token..."
if ! vault token lookup 2>/dev/null | grep -q "display_name"; then
    log_error "Vault root token is invalid or unreachable"
    log_error "Verify VAULT_ADDR=$VAULT_ADDR is correct"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"token_verification\",\"status\":\"failed\",\"vault_addr\":\"$VAULT_ADDR\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi
log_success "Vault access verified"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"token_verified\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"

# Check if AppRole already exists
log_step "Checking for existing AppRole..."
if vault read "auth/approle/role/${APPROLE_NAME}" 2>/dev/null | grep -q "auth_num_uses"; then
    log_info "AppRole already exists. Deleting previous version..."
    vault delete "auth/approle/role/${APPROLE_NAME}" 2>/dev/null || true
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_deleted\",\"approle\":\"$APPROLE_NAME\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
    sleep 1
fi

# Create new AppRole
log_step "Creating AppRole: $APPROLE_NAME"
if vault write "auth/approle/role/${APPROLE_NAME}" \
    policies="${POLICY_NAME}" \
    token_ttl=1h \
    token_max_ttl=4h \
    >/dev/null 2>&1; then
    log_success "AppRole created"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_created\",\"approle\":\"$APPROLE_NAME\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Failed to create AppRole"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_creation\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi

# Generate Role ID
log_step "Generating Role ID..."
ROLE_ID=$(vault read -field=role_id "auth/approle/role/${APPROLE_NAME}/role-id" 2>/dev/null)
if [ -z "$ROLE_ID" ]; then
    log_error "Failed to retrieve Role ID"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"role_id_retrieval\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi
log_success "Role ID generated"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"role_id_generated\",\"status\":\"success\",\"role_id_length\":${#ROLE_ID}}" >> "$VAULT_AUDIT_LOG"

# Generate Secret ID
log_step "Generating Secret ID..."
SECRET_ID=$(vault write -field=secret_id -f "auth/approle/role/${APPROLE_NAME}/secret-id" 2>/dev/null)
if [ -z "$SECRET_ID" ]; then
    log_error "Failed to generate Secret ID"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_id_generation\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi
log_success "Secret ID generated"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"secret_id_generated\",\"status\":\"success\",\"secret_id_length\":${#SECRET_ID}}" >> "$VAULT_AUDIT_LOG"

# Update local credential files
log_step "Updating local credential files..."
mkdir -p /etc/vault 2>/dev/null || {
    log_error "Cannot write to /etc/vault (permission denied)"
    log_info "Try running with sudo: sudo bash $0 $@"
    unset VAULT_TOKEN
    exit 1
}

echo "$ROLE_ID" | sudo tee /etc/vault/role-id.txt >/dev/null 2>&1 || {
    log_error "Failed to write role-id.txt"
    exit 1
}
echo "$SECRET_ID" | sudo tee /etc/vault/secret-id.txt >/dev/null 2>&1 || {
    log_error "Failed to write secret-id.txt"
    exit 1
}
sudo chmod 600 /etc/vault/role-id.txt /etc/vault/secret-id.txt

log_success "Credential files updated"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"credentials_written\",\"files\":[\"/etc/vault/role-id.txt\",\"/etc/vault/secret-id.txt\"],\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"

# Restart Vault Agent with new credentials
log_step "Restarting Vault Agent service..."
if sudo systemctl restart vault 2>/dev/null; then
    log_success "Vault Agent restarted"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_service_restarted\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Failed to restart Vault Agent (elevated permissions required)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_service_restart\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi

sleep 3

# Verify new AppRole works
log_step "Verifying new AppRole authentication..."
if vault read "auth/approle/role/${APPROLE_NAME}/role-id" 2>/dev/null | grep -q "$ROLE_ID"; then
    log_success "New AppRole verified and accessible"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_verification\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Failed to verify new AppRole"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_verification\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi

# Verify Agent can authenticate
log_step "Verifying Vault Agent authentication..."
sleep 2
if curl -s "http://127.0.0.1:8100/health" | grep -q "\"ok\""; then
    log_success "Vault Agent successfully authenticated with new AppRole"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"agent_authentication\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Vault Agent authentication failed"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"agent_authentication\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    unset VAULT_TOKEN
    exit 1
fi

# Revoke root token
log_step "Revoking temporary root token..."
if vault token revoke -self >/dev/null 2>&1; then
    log_success "Root token revoked (token will not be stored anywhere)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"root_token_revoked\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
fi

# Clear token from memory
unset VAULT_TOKEN

# Final success report
log_success "=== AppRole Creation Complete ==="
log_info "AppRole: $APPROLE_NAME"
log_info "Policy: $POLICY_NAME"
log_info "Token TTL: 1h"
log_info "Credentials: /etc/vault/{role-id,secret-id}.txt"
log_info "Agent Service: vault (active and running)"
log_info "Audit Trail: $VAULT_AUDIT_LOG"

echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_creation_completed\",\"approle\":\"$APPROLE_NAME\",\"status\":\"success\",\"note\":\"root_token_revoked_and_not_stored\"}" >> "$VAULT_AUDIT_LOG"

log_info ""
log_info "✓ New AppRole is now operational"
log_info "✓ Vault Agent authenticating successfully"
log_info "✓ Ready for dynamic secret generation"
