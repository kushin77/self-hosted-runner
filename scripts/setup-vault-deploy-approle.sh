#!/usr/bin/env bash
# Vault AppRole Setup for Deploy Automation
# This script automates the Vault configuration for the deploy-immutable-ephemeral workflow
# Usage: bash setup-vault-deploy-approle.sh [--vault-addr] [--role-name]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
VAULT_ROLE_NAME="${VAULT_ROLE_NAME:-deploy-runner}"
VAULT_POLICY_NAME="${VAULT_POLICY_NAME:-deploy-runner-policy}"
VAULT_SECRET_PATH="secret/runnercloud/deploy-ssh-key"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

confirm() {
  local prompt="$1"
  local response
  read -p "$(echo -e ${YELLOW}$prompt${NC})" -r response
  [[ $response =~ ^[Yy]$ ]]
}

print_header() {
  echo ""
  echo "=================================================================================="
  echo "  $1"
  echo "=================================================================================="
  echo ""
}

# Verify prerequisites
verify_vault_access() {
  log_info "Verifying Vault access..."
  
  if [ -z "${VAULT_ADDR:-}" ]; then
    log_error "VAULT_ADDR is not set"
  fi
  
  if [ -z "${VAULT_TOKEN:-}" ]; then
    log_error "VAULT_TOKEN is not set. Please authenticate to Vault first."
  fi
  
  # Test connectivity
  if ! vault status &>/dev/null; then
    log_error "Cannot connect to Vault at $VAULT_ADDR"
  fi
  
  log_success "Connected to Vault: $VAULT_ADDR"
}

# Enable AppRole
enable_approle() {
  print_header "Step 1: Enable AppRole Auth Method"
  
  if vault auth list | grep -q "^approle/"; then
    log_success "AppRole auth method is already enabled"
  else
    log_info "Enabling AppRole auth method..."
    vault auth enable approle || log_error "Failed to enable AppRole"
    log_success "AppRole auth method enabled"
  fi
}

# Create AppRole
create_approle() {
  print_header "Step 2: Create AppRole"
  
  log_info "Creating AppRole: $VAULT_ROLE_NAME"
  
  vault write "auth/approle/role/$VAULT_ROLE_NAME" \
    token_policies="$VAULT_POLICY_NAME" \
    token_ttl="1h" \
    bind_secret_id="true" \
    secret_id_ttl="24h" || log_error "Failed to create AppRole"
  
  log_success "AppRole created: $VAULT_ROLE_NAME"
}

# Create policy
create_policy() {
  print_header "Step 3: Create Vault Policy"
  
  log_info "Creating policy: $VAULT_POLICY_NAME"
  
  vault policy write "$VAULT_POLICY_NAME" - <<'POLICY_EOF'
path "secret/data/runnercloud/deploy-ssh-key" {
  capabilities = ["read"]
}
path "secret/metadata/runnercloud/deploy-ssh-key" {
  capabilities = ["read"]
}
path "secret/data/runnercloud/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/runnercloud/*" {
  capabilities = ["read", "list"]
}
POLICY_EOF
  
  log_success "Policy created: $VAULT_POLICY_NAME"
}

# Store SSH key
store_ssh_key() {
  print_header "Step 4: Store SSH Key in Vault"
  
  # Check if SSH key file is provided
  local ssh_key_file="${1:-}"
  
  if [ -z "$ssh_key_file" ]; then
    log_warning "No SSH key file provided. Skipping key storage."
    log_info "To store SSH key later, run:"
    log_info "  vault kv put $VAULT_SECRET_PATH private_key=@/path/to/id_rsa"
    return 0
  fi
  
  if [ ! -f "$ssh_key_file" ]; then
    log_error "SSH key file not found: $ssh_key_file"
  fi
  
  log_info "Storing SSH key at: $VAULT_SECRET_PATH"
  
  vault kv put "$VAULT_SECRET_PATH" "private_key=@$ssh_key_file" || log_error "Failed to store SSH key"
  
  log_success "SSH key stored in Vault"
}

# Generate and display credentials
generate_credentials() {
  print_header "Step 5: Generate AppRole Credentials"
  
  log_info "Retrieving Role ID..."
  ROLE_ID=$(vault read "auth/approle/role/$VAULT_ROLE_NAME/role-id" -format=json | jq -r '.data.role_id')
  
  if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" = "null" ]; then
    log_error "Failed to retrieve Role ID"
  fi
  
  log_success "Role ID: $ROLE_ID"
  
  log_info "Generating Secret ID..."
  SECRET_ID=$(vault write -f "auth/approle/role/$VAULT_ROLE_NAME/secret-id" -format=json | jq -r '.data.secret_id')
  
  if [ -z "$SECRET_ID" ] || [ "$SECRET_ID" = "null" ]; then
    log_error "Failed to generate Secret ID"
  fi
  
  log_success "Secret ID: $SECRET_ID"
}

# Display credentials for GitHub
display_github_secrets() {
  print_header "Step 6: GitHub Secrets Configuration"
  
  echo -e "${YELLOW}Add the following secrets to your GitHub repository:${NC}"
  echo "  Settings → Secrets and variables → Actions"
  echo ""
  echo "┌─────────────────────────────────────────────────────────────────┐"
  echo "│ Secret Name         │ Value                                     │"
  echo "├─────────────────────────────────────────────────────────────────┤"
  echo "│ VAULT_ADDR          │ $VAULT_ADDR"
  echo "│ VAULT_ROLE_ID       │ $ROLE_ID"
  echo "│ VAULT_SECRET_ID     │ $SECRET_ID"
  echo "└─────────────────────────────────────────────────────────────────┘"
  echo ""
  echo -e "${YELLOW}Using GitHub CLI:${NC}"
  echo "  gh secret set VAULT_ADDR --body \"$VAULT_ADDR\""
  echo "  gh secret set VAULT_ROLE_ID --body \"$ROLE_ID\""
  echo "  gh secret set VAULT_SECRET_ID --body \"$SECRET_ID\""
  echo ""
}

# Test AppRole authentication
test_approle() {
  print_header "Step 7: Test AppRole Authentication"
  
  log_info "Testing AppRole login..."
  
  TEST_RESPONSE=$(curl -s -X POST \
    "$VAULT_ADDR/v1/auth/approle/login" \
    -H "Content-Type: application/json" \
    -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}")
  
  TEST_TOKEN=$(echo "$TEST_RESPONSE" | jq -r '.auth.client_token // empty')
  
  if [ -z "$TEST_TOKEN" ]; then
    log_error "AppRole authentication test failed: $(echo $TEST_RESPONSE | jq '.errors')"
  fi
  
  log_success "AppRole authentication test passed"
  
  # Test SSH key retrieval
  log_info "Testing SSH key retrieval..."
  
  TEST_SSH_KEY=$(curl -s -X GET \
    "$VAULT_ADDR/v1/$VAULT_SECRET_PATH" \
    -H "X-Vault-Token: $TEST_TOKEN" \
    | jq -r '.data.data.private_key // empty')
  
  if [ -z "$TEST_SSH_KEY" ]; then
    log_warning "SSH key retrieval test inconclusive (key not yet stored or inaccessible)"
  else
    log_success "SSH key retrieval test passed"
  fi
}

# Save credentials to file
save_credentials() {
  print_header "Step 8: Save Credentials"
  
  if confirm "Save credentials to file? (y/n) "; then
    local output_file="vault-deploy-credentials.env"
    
    cat > "$output_file" <<EOF
# Vault Deploy Automation Credentials
# Generated: $(date)
# AppRole: $VAULT_ROLE_NAME
# DO NOT COMMIT THIS FILE - Use GitHub Secrets instead

export VAULT_ADDR="$VAULT_ADDR"
export VAULT_ROLE_ID="$ROLE_ID"
export VAULT_SECRET_ID="$SECRET_ID"
EOF
    
    chmod 600 "$output_file"
    log_success "Credentials saved to: $output_file"
    log_warning "⚠️  IMPORTANT: Add $output_file to .gitignore"
    log_warning "⚠️  IMPORTANT: Never commit this file to version control"
  fi
}

# Main
main() {
  print_header "Vault AppRole Setup for Deploy Automation"
  
  # Parse arguments
  SSH_KEY_FILE="${1:-}"
  
  if [ "$SSH_KEY_FILE" = "--help" ] || [ "$SSH_KEY_FILE" = "-h" ]; then
    echo "Usage: bash setup-vault-deploy-approle.sh [SSH_KEY_FILE]"
    echo ""
    echo "Arguments:"
    echo "  SSH_KEY_FILE      Path to SSH private key to store in Vault (optional)"
    echo ""
    echo "Environment Variables:"
    echo "  VAULT_ADDR        Vault server address (e.g., https://vault.internal:8200)"
    echo "  VAULT_TOKEN       Vault authentication token (must be admin)"
    echo "  VAULT_ROLE_NAME   AppRole name (default: deploy-runner)"
    echo "  VAULT_POLICY_NAME Vault policy name (default: deploy-runner-policy)"
    echo ""
    return 0
  fi
  
  # Verify prerequisites
  verify_vault_access
  
  # Show configuration
  echo ""
  log_info "Configuration:"
  log_info "  Vault Address:  $VAULT_ADDR"
  log_info "  AppRole Name:   $VAULT_ROLE_NAME"
  log_info "  Policy Name:    $VAULT_POLICY_NAME"
  log_info "  Secret Path:    $VAULT_SECRET_PATH"
  
  if [ -n "$SSH_KEY_FILE" ]; then
    log_info "  SSH Key File:   $SSH_KEY_FILE"
  fi
  echo ""
  
  if ! confirm "Proceed with Vault setup? (y/n) "; then
    log_warning "Aborted by user"
    return 1
  fi
  
  # Run setup steps
  enable_approle
  create_approle
  create_policy
  store_ssh_key "$SSH_KEY_FILE"
  generate_credentials
  test_approle
  
  # Display results
  display_github_secrets
  save_credentials
  
  print_header "Setup Complete!"
  log_success "AppRole configured successfully"
  log_info "Next steps:"
  log_info "  1. Add GitHub Secrets (see output above)"
  log_info "  2. Configure deploy user on runner hosts"
  log_info "  3. Trigger deploy workflow"
  
  echo ""
}

# Run main
main "$@"
