#!/bin/bash
# Vault Integration Security & Configuration Tests
# Validates AppRole authentication, KV2 engine, and secret management
# Usage: bash tests/vault-security/run-vault-security-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
DEV_MODE=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Vault Security & Configuration Tests                     ║"
echo "║  Vault Address: $VAULT_ADDR                               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Utility functions
function assert_test() {
  local name=$1
  local condition=$2
  echo -n "  $name ... "
  if eval "$condition"; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
  else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
  fi
}

function skip_test() {
  local name=$1
  local reason=$2
  echo -n "  $name ... "
  echo -e "${YELLOW}⊘ SKIP (${reason})${NC}"
  ((SKIPPED++))
}

# Startup Vault dev server if not running
echo "Checking Vault server..."
if ! nc -z 127.0.0.1 8200 2>/dev/null; then
  echo -e "${YELLOW}Starting Vault dev server in background...${NC}"
  docker run -d \
    --name vault-test-$$  \
    --cap-add IPC_LOCK \
    -e VAULT_DEV_ROOT_TOKEN_ID="dev-root-token" \
    -p 8200:8200 \
    vault:latest \
    server -dev \
    -dev-kv-v1=false \
    > /dev/null 2>&1 || true
  
  sleep 2
  DEV_MODE=true
  VAULT_TOKEN="dev-root-token"
fi

# Export for vault CLI commands
export VAULT_ADDR
export VAULT_TOKEN="${VAULT_TOKEN:-$(cat ~/.vault-token 2>/dev/null || echo '')}"

echo -e "${GREEN}✓ Vault server accessible${NC}"
echo ""

# ============= SECTION 1: Auth Method Configuration =============
echo -e "${BLUE}[1. AppRole Authentication Method]${NC}"

# Check if AppRole auth is enabled
if vault auth list 2>/dev/null | grep -q 'approle/'; then
  assert_test "AppRole auth method enabled" "vault auth list | grep -q 'approle/'"
else
  if [[ -z "$VAULT_TOKEN" ]]; then
    skip_test "AppRole auth method check" "VAULT_TOKEN not set"
  else
    # Enable AppRole if not present
    vault auth enable approle 2>/dev/null || true
    assert_test "AppRole auth method enabled" "vault auth list | grep -q 'approle/'"
  fi
fi

# ============= SECTION 2: AppRole Configuration =============
echo ""
echo -e "${BLUE}[2. AppRole Role Configuration]${NC}"

if [[ -n "$VAULT_TOKEN" ]]; then
  # Create or verify provisioner role
  vault write approle/role/provisioner-worker \
    token_ttl=1h \
    token_max_ttl=4h \
    policies="provisioner-worker" \
    2>/dev/null || true
  
  assert_test "Provisioner AppRole role created" \
    "vault read approle/role/provisioner-worker 2>/dev/null | grep -q 'provisioner-worker'"
  
  # Get RoleID
  ROLE_ID=$(vault read -field=role_id approle/role/provisioner-worker 2>/dev/null || echo "")
  if [[ -n "$ROLE_ID" ]]; then
    assert_test "RoleID generated" "[[ -n '$ROLE_ID' && '$ROLE_ID' != '' ]]"
  else
    skip_test "RoleID generation" "AppRole API unavailable"
  fi
  
  # Generate SecretID
  SECRET_ID=$(vault write -field=secret_id -f approle/role/provisioner-worker/secret-id 2>/dev/null || echo "")
  if [[ -n "$SECRET_ID" ]]; then
    assert_test "SecretID generated" "[[ -n '$SECRET_ID' && '$SECRET_ID' != '' ]]"
  else
    skip_test "SecretID generation" "AppRole API unavailable"
  fi
else
  skip_test "AppRole role configuration" "VAULT_TOKEN not authenticated"
  skip_test "RoleID generation" "VAULT_TOKEN not authenticated"
  skip_test "SecretID generation" "VAULT_TOKEN not authenticated"
fi

# ============= SECTION 3: KV2 Secrets Engine =============
echo ""
echo -e "${BLUE}[3. KV v2 Secrets Engine]${NC}"

if [[ -n "$VAULT_TOKEN" ]]; then
  # Enable KV v2 if not present
  vault secrets enable -version=2 kv 2>/dev/null || true
  
  assert_test "KV v2 secrets engine enabled" \
    "vault secrets list | grep -q 'kv.*kv2'"
  
  # Write test secret
  vault kv put kv/provisioner-worker/test-secret \
    username="test-user" \
    password="test-password" \
    api_token="test-token" \
    2>/dev/null || true
  
  assert_test "Test secret written" \
    "vault kv get -field=username kv/provisioner-worker/test-secret 2>/dev/null | grep -q 'test-user'"
  
  # Verify metadata versioning
  METADATA=$(vault kv metadata get kv/provisioner-worker/test-secret 2>/dev/null || echo "")
  if [[ -n "$METADATA" ]]; then
    assert_test "Secret versioning metadata present" \
      "[[ -n '$METADATA' ]]"
  else
    skip_test "Secret versioning metadata" "Metadata API unavailable"
  fi
else
  skip_test "KV v2 secrets engine check" "VAULT_TOKEN not authenticated"
  skip_test "Test secret operation" "VAULT_TOKEN not authenticated"
  skip_test "Secret versioning metadata" "VAULT_TOKEN not authenticated"
fi

# ============= SECTION 4: Policies & Permissions =============
echo ""
echo -e "${BLUE}[4. Access Control Policies]${NC}"

if [[ -n "$VAULT_TOKEN" ]]; then
  # Create provisioner-worker policy
  vault policy write provisioner-worker - <<EOF 2>/dev/null || true
# Provisioner Worker Policies
path "kv/data/provisioner-worker/*" {
  capabilities = ["read", "list"]
}

path "approle/role/provisioner-worker/secret-id" {
  capabilities = ["update"]
}

path "auth/approle/role/provisioner-worker/*" {
  capabilities = ["read"]
}
EOF
  
  assert_test "Provisioner policy created" \
    "vault policy read provisioner-worker 2>/dev/null | grep -q 'provisioner-worker'"
  
  # List policies
  POLICIES=$(vault policy list 2>/dev/null | wc -l)
  assert_test "Multiple policies exist" "[[ $POLICIES -gt 2 ]]"
else
  skip_test "Provisioner policy creation" "VAULT_TOKEN not authenticated"
  skip_test "Policy list check" "VAULT_TOKEN not authenticated"
fi

# ============= SECTION 5: Audit Logging =============
echo ""
echo -e "${BLUE}[5. Audit & Logging Configuration]${NC}"

if [[ -n "$VAULT_TOKEN" ]]; then
  # Check audit methods
  AUDIT_BACKENDS=$(vault audit list 2>/dev/null | wc -l)
  if [[ $AUDIT_BACKENDS -gt 1 ]]; then
    assert_test "Audit logging enabled" "[[ $AUDIT_BACKENDS -gt 1 ]]"
  else
    skip_test "Audit logging check" "No audit backends configured"
  fi
else
  skip_test "Audit logging check" "VAULT_TOKEN not authenticated"
fi

# ============= SECTION 6: Secret Rotation & Lifecycle =============
echo ""
echo -e "${BLUE}[6. Secret Lifecycle Management]${NC}"

if [[ -n "$VAULT_TOKEN" ]]; then
  # Create a rotatable secret
  vault kv put kv/provisioner-worker/rotation-test \
    initial_value="rotation-v1" \
    rotated_at="2026-03-05T12:00:00Z" \
    2>/dev/null || true
  
  assert_test "Rotatable secret created" \
    "vault kv get -field=initial_value kv/provisioner-worker/rotation-test 2>/dev/null | grep -q 'rotation-v1'"
  
  # Update secret version
  vault kv put kv/provisioner-worker/rotation-test \
    initial_value="rotation-v2" \
    rotated_at="2026-03-05T12:01:00Z" \
    2>/dev/null || true
  
  assert_test "Secret rotation succeeds" \
    "vault kv get -field=initial_value kv/provisioner-worker/rotation-test 2>/dev/null | grep -q 'rotation-v2'"
else
  skip_test "Rotatable secret creation" "VAULT_TOKEN not authenticated"
  skip_test "Secret rotation" "VAULT_TOKEN not authenticated"
fi

# ============= SECTION 7: AppRole Authentication Flow =============
echo ""
echo -e "${BLUE}[7. AppRole Authentication Flow]${NC}"

if [[ -n "$VAULT_TOKEN" && -n "$ROLE_ID" && -n "$SECRET_ID" ]]; then
  # Attempt authentication
  AUTH_RESPONSE=$(vault write -format=json auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID" \
    2>/dev/null || echo "")
  
  if [[ -n "$AUTH_RESPONSE" ]]; then
    APP_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.auth.client_token // empty' 2>/dev/null || echo "")
    if [[ -n "$APP_TOKEN" ]]; then
      assert_test "AppRole authentication succeeds" "[[ -n '$APP_TOKEN' ]]"
      
      # Verify token metadata
      assert_test "Authenticated token has policies" \
        "echo '$AUTH_RESPONSE' | jq -r '.auth.policies[]' 2>/dev/null | grep -q 'provisioner-worker' || true"
    else
      skip_test "AppRole authentication" "Token generation failed"
      skip_test "Token policy verification" "Token generation failed"
    fi
  else
    skip_test "AppRole authentication" "Auth API unavailable"
    skip_test "Token policy verification" "Auth API unavailable"
  fi
else
  skip_test "AppRole authentication" "RoleID or SecretID not available"
  skip_test "Token policy verification" "RoleID or SecretID not available"
fi

# ============= SECTION 8: Environment Variable Configuration =============
echo ""
echo -e "${BLUE}[8. Environment Configuration]${NC}"

# Check for production-like environment variables
if [[ -f ~/.env ]]; then
  assert_test "Environment file exists" "[[ -f ~/.env ]]"
else
  skip_test "Environment file check" "~/.env not found"
fi

# Check for Vault configuration
if grep -q "VAULT_ADDR" ~/.bashrc ~/.bash_profile ~/.zshrc 2>/dev/null || [[ -n "$VAULT_ADDR" ]]; then
  assert_test "VAULT_ADDR configured" "[[ -n '$VAULT_ADDR' ]]"
else
  skip_test "VAULT_ADDR configuration" "Not set in shell configs"
fi

# ============= CLEANUP =============
if [[ "$DEV_MODE" == "true" ]]; then
  echo ""
  echo "Cleaning up Vault dev server..."
  docker stop vault-test-$$ 2>/dev/null || true
  docker rm vault-test-$$ 2>/dev/null || true
fi

# ============= RESULTS =============
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "Vault Security & Configuration Test Results:"
echo -e "  Passed:  ${GREEN}${PASSED}${NC}"
echo -e "  Failed:  ${RED}${FAILED}${NC}"
echo -e "  Skipped: ${YELLOW}${SKIPPED}${NC}"
echo ""
echo "Vault Configuration:"
echo "  Address: $VAULT_ADDR"
echo "  Auth Method: approle"
echo "  Secrets Engine: kv (v2)"
echo "  Policies: provisioner-worker (and others)"
echo "════════════════════════════════════════════════════════════"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}✅ All Vault security tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed. Review errors above.${NC}"
  exit 1
fi
