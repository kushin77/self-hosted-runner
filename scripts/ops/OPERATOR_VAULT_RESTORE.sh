#!/bin/bash
# OPERATOR INJECTION: Vault AppRole Restoration
# Restores Vault AppRole connectivity by pointing to original Vault cluster
# Usage: bash scripts/ops/OPERATOR_VAULT_RESTORE.sh --vault-server https://vault.original:8200

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly VAULT_CONFIG="/etc/vault/vault.hcl"
readonly VAULT_AUDIT_LOG="${WORKSPACE_ROOT}/logs/vault-restore-audit.jsonl"
readonly TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }
log_step() { echo -e "${YELLOW}▶${NC} $1" | tee -a "$VAULT_AUDIT_LOG"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vault-server) VAULT_ADDR="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "${VAULT_ADDR:-}" ]; then
    log_error "Missing required argument: --vault-server"
    echo "Usage: $0 --vault-server https://vault.original.cluster:8200"
    exit 1
fi

# Initialize audit log
mkdir -p "$(dirname "$VAULT_AUDIT_LOG")"
{
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_restore_started\",\"vault_server\":\"$VAULT_ADDR\",\"user\":\"${USER}\"}"
} | tee -a "$VAULT_AUDIT_LOG"

log_step "Restoring Vault AppRole configuration"
log_info "Target Vault Server: $VAULT_ADDR"

# Backup current config
if [ -f "$VAULT_CONFIG" ]; then
    local backup_dir="${WORKSPACE_ROOT}/.backups/vault/$(date -u +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp "$VAULT_CONFIG" "$backup_dir/"
    log_success "Backed up existing Vault config: $backup_dir"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_config_backed_up\",\"backup_path\":\"$backup_dir\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
fi

# Update vault.hcl with new server address
log_step "Updating Vault configuration"
if [ -f "$VAULT_CONFIG" ]; then
    # Update vault address line
    sudo sed -i "s|address = \".*\"|address = \"$VAULT_ADDR\"|g" "$VAULT_CONFIG" || {
        log_error "Failed to update VAULT_ADDR in config"
        echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"config_update\",\"status\":\"failed\",\"error\":\"sed failed\"}" >> "$VAULT_AUDIT_LOG"
        exit 1
    }
    log_success "Updated vault.hcl with new server address"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"config_updated\",\"vault_server\":\"$VAULT_ADDR\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Vault config file not found: $VAULT_CONFIG"
    exit 1
fi

# Restart Vault Agent
log_step "Restarting Vault Agent service"
if sudo systemctl restart vault 2>/dev/null; then
    log_success "Vault Agent restarted"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_service_restarted\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Failed to restart Vault Agent (elevated permissions required)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_service_restart\",\"status\":\"failed\",\"error\":\"systemctl restart failed\"}" >> "$VAULT_AUDIT_LOG"
    exit 1
fi

# Wait for Vault to be ready
log_step "Waiting for Vault Agent to be ready..."
sleep 3

# Verify AppRole resolves
log_step "Verifying AppRole configuration on new Vault server"
export VAULT_ADDR="$VAULT_ADDR"

if timeout 10 vault read auth/approle/role/nexusshield-prod-agent/role-id >/dev/null 2>&1; then
    log_success "AppRole verified on original Vault cluster!"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_verified\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "AppRole not found or unreachable on $VAULT_ADDR"
    log_info "Possible causes:"
    log_info "  - AppRole doesn't exist on this Vault cluster"
    log_info "  - Network connectivity issue"
    log_info "  - Vault permissions issue"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"approle_verification\",\"status\":\"failed\",\"vault_server\":\"$VAULT_ADDR\"}" >> "$VAULT_AUDIT_LOG"
    exit 1
fi

log_step "Running health checks"
if curl -s "http://127.0.0.1:8100/health" | grep -q "\"ok\""; then
    log_success "Vault Agent health check passed"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"health_check\",\"status\":\"success\"}" >> "$VAULT_AUDIT_LOG"
else
    log_error "Vault Agent health check failed"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"health_check\",\"status\":\"failed\"}" >> "$VAULT_AUDIT_LOG"
    exit 1
fi

# Final success
log_success "=== Vault AppRole Restoration Complete ==="
log_info "Vault Server: $VAULT_ADDR"
log_info "AppRole: nexusshield-prod-agent"
log_info "Agent Service: vault (active and running)"
log_info "Audit Trail: $VAULT_AUDIT_LOG"

echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"vault_restore_completed\",\"status\":\"success\",\"vault_server\":\"$VAULT_ADDR\"}" >> "$VAULT_AUDIT_LOG"
