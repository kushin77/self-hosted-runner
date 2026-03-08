#!/bin/bash

###############################################################################
# Vault JWT Auth Setup for GitHub Actions
# 
# This script configures Vault's JWT authentication to allow GitHub Actions
# to authenticate using GitHub's OIDC tokens without storing secrets.
#
# Requirements:
#   - Vault server running and accessible
#   - VAULT_ADDR and VAULT_TOKEN environment variables set
#   - Admin/root access to configure auth methods
#   - curl and jq installed
#
# Output:
#   - Vault JWT auth configuration
#   - VAULT_ADDR and VAULT_NAMESPACE for use in workflows
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

###############################################################################
# CONFIGURATION
###############################################################################

VAULT_ADDR="${VAULT_ADDR:=}"
VAULT_TOKEN="${VAULT_TOKEN:=}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:=}"
JWT_ROLE_NAME="${JWT_ROLE_NAME:=github-actions}"
GITHUB_REPO="${GITHUB_REPO:=kushin77/self-hosted-runner}"
GITHUB_OWNER="${GITHUB_OWNER:=kushin77}"

# Output file for credentials
OUTPUT_FILE="${OUTPUT_FILE:=/tmp/vault-jwt-credentials.txt}"

###############################################################################
# VALIDATION
###############################################################################

log_info "Starting Vault JWT Auth setup..."
echo ""

# Check required tools
for tool in curl jq; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "$tool is not installed. Please install it first."
        exit 1
    fi
done

log_success "Required tools found (curl, jq)"

# Get or request Vault address
if [[ -z "$VAULT_ADDR" ]]; then
    read -p "Enter Vault server address (e.g., https://vault.example.com:8200): " VAULT_ADDR
fi

# Validate Vault connectivity
log_info "Checking Vault connectivity: $VAULT_ADDR"

if ! curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
    log_error "Cannot connect to Vault at $VAULT_ADDR"
    exit 1
fi

log_success "Vault is reachable"

# Get or request Vault token
if [[ -z "$VAULT_TOKEN" ]]; then
    read -sp "Enter Vault token (should have admin access): " VAULT_TOKEN
    echo ""
fi

# Validate Vault token
log_info "Validating Vault token..."

TOKEN_LOOKUP=$(curl -s "$VAULT_ADDR/v1/auth/token/lookup-self" \
    -H "X-Vault-Token: $VAULT_TOKEN" 2>/dev/null || echo "")

if [[ -z "$TOKEN_LOOKUP" ]] || ! echo "$TOKEN_LOOKUP" | jq -e '.data' > /dev/null 2>/dev/null; then
    log_error "Invalid Vault token"
    exit 1
fi

log_success "Vault token validated"

# Get optional namespace
if [[ -z "$VAULT_NAMESPACE" ]]; then
    read -p "Enter Vault namespace (optional, press Enter to skip): " VAULT_NAMESPACE || true
fi

###############################################################################
# STEP 1: Enable JWT Auth Method
###############################################################################

log_info ""
log_info "Step 1: Checking/enabling JWT auth method..."

VAULT_HEADERS="-H 'X-Vault-Token: $VAULT_TOKEN'"
if [[ -n "$VAULT_NAMESPACE" ]]; then
    VAULT_HEADERS="$VAULT_HEADERS -H 'X-Vault-Namespace: $VAULT_NAMESPACE'"
fi

# Check if JWT auth is already enabled
JWT_CHECK=$(curl -s $VAULT_HEADERS "$VAULT_ADDR/v1/sys/auth" 2>/dev/null | jq '.data."jwt/"' || echo "")

if [[ "$JWT_CHECK" != "null" ]] && [[ -n "$JWT_CHECK" ]]; then
    log_warning "JWT auth method is already enabled"
else
    log_info "Enabling JWT auth method..."
    
    curl -s -X POST \
        $VAULT_HEADERS \
        "$VAULT_ADDR/v1/sys/auth/jwt" \
        -d '{"type":"jwt"}' > /dev/null
    
    log_success "JWT auth method enabled"
fi

###############################################################################
# STEP 2: Configure JWT Auth
###############################################################################

log_info ""
log_info "Step 2: Configuring JWT auth..."

# Create JWT configuration
JWT_CONFIG=$(cat <<'EOF'
{
  "oidc_discovery_url": "https://token.actions.githubusercontent.com",
  "bound_issuer": "https://token.actions.githubusercontent.com",
  "default_role": "github-actions"
}
EOF
)

log_info "Setting JWT auth configuration..."

curl -s -X POST \
    $VAULT_HEADERS \
    "$VAULT_ADDR/v1/auth/jwt/config" \
    -d "$JWT_CONFIG" > /dev/null

log_success "JWT auth configured"

###############################################################################
# STEP 3: Create JWT Role
###############################################################################

log_info ""
log_info "Step 3: Creating/updating JWT role..."

# Create role configuration
JWT_ROLE=$(cat <<EOF
{
  "bound_audiences": "https://github.com/$GITHUB_OWNER",
  "user_claim": "actor",
  "role_type": "jwt",
  "policies": ["github-actions-policy"],
  "ttl": "3600",
  "max_ttl": "86400",
  "claim_mappings": {
    "actor": "actor",
    "repository": "repository",
    "repository_owner": "repository_owner"
  }
}
EOF
)

log_info "Creating role: $JWT_ROLE_NAME"

curl -s -X POST \
    $VAULT_HEADERS \
    "$VAULT_ADDR/v1/auth/jwt/role/$JWT_ROLE_NAME" \
    -d "$JWT_ROLE" > /dev/null

log_success "JWT role created: $JWT_ROLE_NAME"

###############################################################################
# STEP 4: Create Secret Policy
###############################################################################

log_info ""
log_info "Step 4: Creating secret policy..."

POLICY_NAME="github-actions-policy"

# Check if policy exists
POLICY_CHECK=$(curl -s \
    $VAULT_HEADERS \
    "$VAULT_ADDR/v1/sys/policies/acl/$POLICY_NAME" 2>/dev/null || echo "")

POLICY_CONTENT=$(cat <<'EOF'
# GitHub Actions Policy
# Allows GitHub Actions to read secrets and manage tokens

# Read GitHub secrets
path "secret/data/github/*" {
  capabilities = ["read", "list"]
}

# Read deployment secrets
path "secret/data/deploy/*" {
  capabilities = ["read", "list"]
}

# Read application secrets
path "secret/data/app/*" {
  capabilities = ["read", "list"]
}

# List secret paths
path "secret/metadata/*" {
  capabilities = ["list"]
}

# For dynamic database credentials (optional)
path "database/creds/*" {
  capabilities = ["read"]
}

# For dynamic AWS credentials (optional)
path "aws/creds/*" {
  capabilities = ["read"]
}

# Self-renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Check token validity
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
)

log_info "Creating/updating policy: $POLICY_NAME"

# Write policy (using base64 to avoid escaping issues)
curl -s -X POST \
    $VAULT_HEADERS \
    "$VAULT_ADDR/v1/sys/policies/acl/$POLICY_NAME" \
    -d "{\"policy\":$(echo "$POLICY_CONTENT" | jq -Rs .)}" > /dev/null

log_success "Policy created: $POLICY_NAME"

###############################################################################
# STEP 5: Create Sample Secrets
###############################################################################

log_info ""
log_info "Step 5: Creating sample secrets..."

SECRETS=(
    "secret/data/github/pat-core:github_pat_placeholder"
    "secret/data/github/deploy-ssh-key:ssh_private_key_placeholder"
    "secret/data/deploy/runner-token:runner_token_placeholder"
)

for secret_spec in "${SECRETS[@]}"; do
    secret_path="${secret_spec%:*}"
    secret_value="${secret_spec#*:}"
    
    log_info "Creating secret: $secret_path"
    
    curl -s -X POST \
        $VAULT_HEADERS \
        "$VAULT_ADDR/v1/$secret_path" \
        -d "{\"data\":{\"value\":\"$secret_value\"}}" > /dev/null || \
        log_warning "Failed to create $secret_path (may already exist)"
done

log_success "Sample secrets created"

###############################################################################
# STEP 6: Verify Configuration
###############################################################################

log_info ""
log_info "Step 6: Verifying JWT auth configuration..."

# Get JWT config
JWT_CONFIG_RESULT=$(curl -s \
    $VAULT_HEADERS \
    "$VAULT_ADDR/v1/auth/jwt/config" 2>/dev/null)

if echo "$JWT_CONFIG_RESULT" | jq -e '.data.oidc_discovery_url' > /dev/null 2>/dev/null; then
    OIDC_URL=$(echo "$JWT_CONFIG_RESULT" | jq -r '.data.oidc_discovery_url')
    log_success "JWT OIDC Discovery URL: $OIDC_URL"
fi

# Verify role exists
JWT_ROLE_RESULT=$(curl -s \
    $VAULT_HEADERS \
    "$VAULT_ADDR/v1/auth/jwt/role/$JWT_ROLE_NAME" 2>/dev/null)

if echo "$JWT_ROLE_RESULT" | jq -e '.data.bound_audiences' > /dev/null 2>/dev/null; then
    BOUND_AUD=$(echo "$JWT_ROLE_RESULT" | jq -r '.data.bound_audiences')
    log_success "JWT Role bound audiences: $BOUND_AUD"
fi

###############################################################################
# STEP 7: Save Credentials to File
###############################################################################

log_info ""
log_info "Step 7: Saving credentials..."

cat > "$OUTPUT_FILE" <<EOF
###############################################################################
# Vault JWT Auth - GitHub Actions Setup
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
###############################################################################

# 1. Vault Server Information
# ⭐ Save to GitHub secret: VAULT_ADDR
VAULT_ADDR=${VAULT_ADDR}

# Optional: If using namespaces
# ⭐ Save to GitHub secret: VAULT_NAMESPACE (optional)
VAULT_NAMESPACE=${VAULT_NAMESPACE}

# 2. JWT Configuration
JWT_ROLE_NAME=${JWT_ROLE_NAME}
JWT_AUTH_PATH=jwt
BOUND_AUDIENCES=https://github.com/${GITHUB_OWNER}

# 3. GitHub Configuration
GITHUB_REPO=${GITHUB_REPO}
GITHUB_OWNER=${GITHUB_OWNER}

###############################################################################
# How to use in GitHub Actions workflows:
###############################################################################

# In your workflow, add this step to authenticate:

jobs:
  example:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - name: Get Vault token using GitHub OIDC
        id: vault-auth
        run: |
          # Get GitHub's OIDC token
          GITHUB_TOKEN=\$(curl -s -H "Authorization: bearer \$ACTIONS_ID_TOKEN_REQUEST_TOKEN" \\
            "\$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://github.com/\${{ github.repository_owner }}" \\
            | jq -r '.token')
          
          # Exchange for Vault token
          VAULT_TOKEN=\$(curl -s -X POST \\
            \${{ secrets.VAULT_ADDR }}/v1/auth/jwt/login \\
            -d "{\\\"role\\\":\\\"${JWT_ROLE_NAME}\\\",\\\"jwt\\\":\\\"\$GITHUB_TOKEN\\\"}" \\
            | jq -r '.auth.client_token')
          
          echo "::add-mask::\$VAULT_TOKEN"
          echo "vault_token=\$VAULT_TOKEN" >> \$GITHUB_OUTPUT
      
      - name: Retrieve secret from Vault
        env:
          VAULT_TOKEN: \${{ steps.vault-auth.outputs.vault_token }}
          VAULT_ADDR: \${{ secrets.VAULT_ADDR }}
        run: |
          curl -s -H "X-Vault-Token: \$VAULT_TOKEN" \\
            \$VAULT_ADDR/v1/secret/data/github/pat-core \\
            | jq -r '.data.data.value'

###############################################################################
# Create these GitHub Secrets:
###############################################################################

1. VAULT_ADDR = ${VAULT_ADDR}
2. VAULT_NAMESPACE = ${VAULT_NAMESPACE} (optional, if using namespaces)

###############################################################################
# Verify Setup:
###############################################################################

# Read JWT config:
vault read auth/jwt/config

# Read JWT role:
vault read auth/jwt/role/${JWT_ROLE_NAME}

# Read policy:
vault policy read ${POLICY_NAME}

# List secrets:
vault kv list secret/github
vault kv list secret/deploy

# Test with a curl command (requires GitHub OIDC token):
# VAULT_TOKEN=\$(curl -X POST \\
#   ${VAULT_ADDR}/v1/auth/jwt/login \\
#   -d '{"role":"${JWT_ROLE_NAME}","jwt":"<GITHUB_OIDC_TOKEN>"}' \\
#   | jq -r '.auth.client_token')

###############################################################################
# AppRole (Alternative Authentication - Deprecated, not using)
###############################################################################

# For legacy AppRole support (not recommended for GitHub Actions):
# Enable: vault auth enable approle
# Create role: vault write auth/approle/role/github-actions policies="github-actions-policy"
# Get RoleID: vault read auth/approle/role/github-actions/role-id
# Create SecretID: vault write -f auth/approle/role/github-actions/secret-id

EOF

log_success "Credentials saved to $OUTPUT_FILE"

###############################################################################
# STEP 8: Provide Testing Instructions
###############################################################################

log_info ""
log_info "Creating test script..."

cat > "/tmp/vault-jwt-test.sh" <<'TESTEOF'
#!/bin/bash

# Vault JWT Testing Script
# This script helps verify your Vault JWT auth setup

VAULT_ADDR="${1:?Usage: $0 <VAULT_ADDR> <JWT_TOKEN>}"
GITHUB_JWT="${2:?Usage: $0 <VAULT_ADDR> <JWT_TOKEN>}"

echo "Testing Vault JWT authentication..."
echo "Vault: $VAULT_ADDR"
echo ""

# Attempt to login with GitHub JWT
LOGIN_RESPONSE=$(curl -s -X POST \
  "$VAULT_ADDR/v1/auth/jwt/login" \
  -d "{\"role\":\"github-actions\",\"jwt\":\"$GITHUB_JWT\"}")

if echo "$LOGIN_RESPONSE" | jq -e '.auth.client_token' > /dev/null 2>/dev/null; then
  VAULT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.client_token')
  TTL=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.lease_duration')
  
  echo "✅ Authentication successful!"
  echo "   Token TTL: ${TTL}s"
  echo "   Token: ${VAULT_TOKEN:0:20}..."
  echo ""
  
  # Try to read a secret
  echo "Reading test secret..."
  curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/github/pat-core" | jq '.'
else
  echo "❌ Authentication failed!"
  echo "$LOGIN_RESPONSE" | jq '.'
fi
TESTEOF

chmod +x "/tmp/vault-jwt-test.sh"

log_success "Test script created at /tmp/vault-jwt-test.sh"

###############################################################################
# SUMMARY
###############################################################################

log_info ""
log_info "═══════════════════════════════════════════════════════════════════════"
log_success "Vault JWT Auth Setup Complete!"
log_info "═══════════════════════════════════════════════════════════════════════"
echo ""

echo "✅ JWT Auth Enabled"
echo "✅ JWT Role: $JWT_ROLE_NAME"
echo "✅ Policy: github-actions-policy"
echo "✅ Sample Secrets Created"
echo ""

echo "📋 Create these GitHub Secrets:"
echo "   1. VAULT_ADDR = $VAULT_ADDR"
if [[ -n "$VAULT_NAMESPACE" ]]; then
    echo "   2. VAULT_NAMESPACE = $VAULT_NAMESPACE"
fi
echo ""

echo "📝 Full configuration saved to: $OUTPUT_FILE"
echo "📝 Test script saved to: /tmp/vault-jwt-test.sh"
echo ""

echo "🚀 Next steps:"
echo "   1. Copy VAULT_ADDR and add to GitHub repository secrets"
echo "      gh secret set VAULT_ADDR --body '$VAULT_ADDR'"
if [[ -n "$VAULT_NAMESPACE" ]]; then
    echo "   2. Add VAULT_NAMESPACE to secrets:"
    echo "      gh secret set VAULT_NAMESPACE --body '$VAULT_NAMESPACE'"
fi
echo "   2. Update your workflow to use retrieve-secret-vault action"
echo "   3. Test with: .github/workflows/test-credential-helpers.yml"
echo ""

log_success "Setup complete!"
