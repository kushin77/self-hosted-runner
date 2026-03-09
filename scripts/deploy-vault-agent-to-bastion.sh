#!/bin/bash
################################################################################
# Deploy Vault Agent to Bastion Host
# Description: Deploys vault-agent configured with AppRole credentials to bastion
#              for secure credential distribution and automatic secret rotation
# Usage: ./deploy-vault-agent-to-bastion.sh [--dry-run] [--verbose]
# Requires: SSH access to bastion (192.168.168.31), vault CLI, jq
################################################################################

set -e

# Configuration
BASTION_HOST="${BASTION_HOST:-192.168.168.31}"
BASTION_USER="${BASTION_USER:-ec2-user}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.aws.example.com:8200}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"

# Vault AppRole credentials (from Phase 1)
VAULT_ROLE_ID="${VAULT_ROLE_ID:-51bc5a46-c34b-4c79-5bb5-9afea8acf424}"
VAULT_SECRET_ID_FILE="${VAULT_SECRET_ID_FILE:-/tmp/vault-approle-credentials.json}"

# Flags
DRY_RUN=${DRY_RUN:-false}
VERBOSE=${VERBOSE:-false}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    local level=$1; shift
    local message="$@"
    local timestamp=$(date '+[%Y-%m-%d %H:%M:%S]')
    
    case "$level" in
        INFO)   echo -e "${BLUE}${timestamp} ℹ️  ${message}${NC}" ;;
        SUCCESS) echo -e "${GREEN}${timestamp} ✅ ${message}${NC}" ;;
        WARN)   echo -e "${YELLOW}${timestamp} ⚠️  ${message}${NC}" ;;
        ERROR)  echo -e "${RED}${timestamp} ❌ ${message}${NC}" ;;
        *)      echo -e "${timestamp} ${message}" ;;
    esac
}

run_cmd() {
    local cmd="$@"
    if [[ "$VERBOSE" == "true" ]]; then
        log INFO "Executing: $cmd"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    eval "$cmd"
}

# Verify prerequisites
verify_prerequisites() {
    log INFO "Verifying prerequisites..."
    
    local missing_tools=0
    
    # Check SSH connectivity to bastion
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${BASTION_USER}@${BASTION_HOST}" "echo ok" &>/dev/null; then
        log ERROR "Cannot SSH to ${BASTION_USER}@${BASTION_HOST}:22"
        missing_tools=1
    else
        log SUCCESS "SSH connectivity to bastion verified"
    fi
    
    # Check Vault AppRole credentials
    if [[ ! -f "$VAULT_SECRET_ID_FILE" ]]; then
        log ERROR "Vault credentials file not found: $VAULT_SECRET_ID_FILE"
        log INFO "  Run: bash scripts/complete-credential-provisioning.sh --phase 1"
        missing_tools=1
    else
        log SUCCESS "Vault AppRole credentials available"
    fi
    
    # Check vault CLI
    if ! command -v vault &>/dev/null; then
        log WARN "vault CLI not found - will use curl for operations"
    else
        log SUCCESS "vault CLI available"
    fi
    
    if [[ $missing_tools -gt 0 ]]; then
        log ERROR "Missing prerequisites, cannot proceed"
        return 1
    fi
}

# Deploy vault-agent configuration
deploy_vault_agent_config() {
    log INFO "Deploying vault-agent configuration..."
    
    # Read AppRole credentials
    if [[ ! -f "$VAULT_SECRET_ID_FILE" ]]; then
        log ERROR "Vault credentials file not found: $VAULT_SECRET_ID_FILE"
        return 1
    fi
    
    local role_id=$(jq -r '.role_id // empty' "$VAULT_SECRET_ID_FILE")
    local secret_id=$(jq -r '.secret_id // empty' "$VAULT_SECRET_ID_FILE")
    
    if [[ -z "$role_id" && -z "$secret_id" ]]; then
        log ERROR "Cannot read Vault credentials from: $VAULT_SECRET_ID_FILE"
        return 1
    fi
    
    log SUCCESS "Vault credentials loaded (role_id: ${role_id:0:8}...)"
    
    # Create vault-agent config file
    local config_dir="/etc/vault"
    local config_file="$config_dir/agent-config.hcl"
    
    log INFO "Creating vault-agent configuration at $config_file..."
    
    # Create the HCL config
    local vault_hcl=$(cat <<'EOF'
vault {
  address = "http://vault.service.consul:8200"
}

auto_auth {
  method {
    type = "approle"
    
    config = {
      role_id_file_path = "/etc/vault/role-id.txt"
      secret_id_file_path = "/etc/vault/secret-id.txt"
      remove_secret_id_file_after_reading = true
    }
  }
  
  sink {
    type = "file"
    config = {
      path = "/var/run/vault/.vault-token"
      mode = 0600
    }
  }
}

cache {
  use_auto_auth_token = true
  when_inconsistent = "retry"
}

listener "unix" {
  address = "/var/run/vault/agent.sock"
  tls_disable = true
}

listener "tcp" {
  address = "127.0.0.1:8100"
  tls_disable = true
}

listener "tcp" {
  address = "0.0.0.0:8100"
  tls_disable = true
}

# Template for SSH key rotation
template {
  source = "/etc/vault/templates/ssh-key.tpl"
  destination = "/home/runner/.ssh/id_rsa"
  command = "systemctl reload wait-and-deploy"
  error_on_missing_key = false
}

# Template for AWS credentials
template {
  source = "/etc/vault/templates/aws-creds.tpl"
  destination = "/var/run/secrets/aws-credentials.env"
  command = "systemctl reload wait-and-deploy"
  error_on_missing_key = false
}

# Template for GCP service account
template {
  source = "/etc/vault/templates/gcp-sa.tpl"
  destination = "/var/run/secrets/gcp-sa.json"
  command = "systemctl reload wait-and-deploy"
  error_on_missing_key = false
}
EOF
    )
    
    # Deploy via SSH
    run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} 'mkdir -p $config_dir /var/run/vault && touch $config_dir/role-id.txt $config_dir/secret-id.txt'"
    
    # Write credentials securely
    run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} \"echo '$role_id' > $config_dir/role-id.txt && chmod 600 $config_dir/role-id.txt\""
    run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} \"echo '$secret_id' > $config_dir/secret-id.txt && chmod 600 $config_dir/secret-id.txt\""
    
    # Write vault config
    run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} \"cat > $config_file <<< '$vault_hcl' && chmod 600 $config_file\""
    
    log SUCCESS "Vault agent configuration deployed"
}

# Install vault-agent systemd service
deploy_vault_agent_service() {
    log INFO "Deploying vault-agent systemd service..."
    
    local service_file="/etc/systemd/system/vault-agent.service"
    local service_content=$(cat <<'EOF'
[Unit]
Description=Vault Agent for Credential Management
Documentation=https://www.vaultproject.io/docs/agent
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault/agent-config.hcl

[Service]
Type=notify
ProtectSystem=full
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
LimitNOFILE=65000
LimitNPROC=512
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitBurst=3
StartLimitInterval=60

StandardOutput=journal
StandardError=journal

# Uncomment if using Vault with HashiCorp Cloud Platform
# Environment="VAULT_SKIP_VERIFY=false"

ExecStart=/usr/local/bin/vault agent -config=/etc/vault/agent-config.hcl
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
Alias=vault-agent.service
EOF
    )
    
    run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} \"cat > $service_file <<< '$service_content' && chmod 644 $service_file\""
    
    # Reload systemd and enable service
    run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} 'systemctl daemon-reload && systemctl enable vault-agent.service && systemctl start vault-agent.service'"
    
    log SUCCESS "Vault agent service deployed and started"
}

# Verify deployment
verify_deployment() {
    log INFO "Verifying vault-agent deployment..."
    
    local status=$(run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} 'systemctl is-active vault-agent.service' 2>/dev/null" || echo "inactive")
    
    if [[ "$status" == "active" ]]; then
        log SUCCESS "Vault agent service is active and running"
        
        # Check vault-agent logs
        log INFO "Recent vault-agent logs:"
        run_cmd "ssh ${BASTION_USER}@${BASTION_HOST} 'journalctl -u vault-agent.service -n 20 --no-pager' | sed 's/^/  /'"
        
    else
        log WARN "Vault agent service is not active (status: $status)"
        log INFO "Check logs with: ssh ${BASTION_USER}@${BASTION_HOST} journalctl -u vault-agent.service -f"
    fi
}

# Main execution
main() {
    log INFO "================================"
    log INFO "Vault Agent Deployment"
    log INFO "================================"
    log INFO "Target: ${BASTION_USER}@${BASTION_HOST}:22"
    log INFO "Vault Address: $VAULT_ADDR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "DRY-RUN MODE: No changes will be made"
    fi
    
    # Execute deployment steps
    verify_prerequisites || exit 1
    deploy_vault_agent_config || exit 1
    deploy_vault_agent_service || exit 1
    verify_deployment || exit 1
    
    log SUCCESS "================================"
    log SUCCESS "Vault Agent Deployment Complete"
    log SUCCESS "================================"
    log SUCCESS "Vault agent is now managing credentials on bastion"
    log SUCCESS "Next: Deploy wait-and-deploy watcher service"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --bastion)
            BASTION_HOST="$2"
            shift 2
            ;;
        --vault-addr)
            VAULT_ADDR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose] [--bastion HOST] [--vault-addr ADDR]"
            exit 1
            ;;
    esac
done

main
