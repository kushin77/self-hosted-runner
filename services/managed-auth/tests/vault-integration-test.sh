#!/bin/bash
# Test script for Vault-backed secretStore integration
# Usage: SECRETS_BACKEND=vault VAULT_ADDR=http://localhost:8200 bash tests/vault-integration-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[Vault Integration Test]${NC}"
echo "Backend: ${SECRETS_BACKEND:-memory}"
echo "Vault Addr: ${VAULT_ADDR:-not set}"

# Test 1: Import secretStore module
echo -e "\n${YELLOW}Test 1: Load secretStore module${NC}"
if node -e "const ss = require('./lib/secretStore.cjs'); console.log('Module loaded')"; then
  echo -e "${GREEN}✓ secretStore module loaded successfully${NC}"
else
  echo -e "${RED}✗ Failed to load secretStore module${NC}"
  exit 1
fi

# Test 2: Set and Get Token (memory backend)
echo -e "\n${YELLOW}Test 2: Set/Get Token Test${NC}"
TEST_TOKEN=$(node -e "
const ss = require('./lib/secretStore.cjs');
const token = 'test-token-' + Date.now();
const tokenObj = { token, created: new Date().toISOString(), username: 'test-user' };
(async () => {
  await ss.setToken(tokenObj);
  const retrieved = await ss.getToken(token);
  if (retrieved && retrieved.token === token) {
    console.log('SUCCESS');
  } else {
    console.log('FAILED');
    process.exit(1);
  }
})();
")

if [[ "$TEST_TOKEN" == "SUCCESS" ]]; then
  echo -e "${GREEN}✓ Token storage working${NC}"
else
  echo -e "${RED}✗ Token storage failed${NC}"
  exit 1
fi

# Test 3: Vault connection (if using vault backend)
if [[ "${SECRETS_BACKEND:-memory}" == "vault" ]]; then
  echo -e "\n${YELLOW}Test 3: Vault Connectivity${NC}"
  
  if [[ -z "${VAULT_ADDR:-}" ]]; then
    echo -e "${RED}✗ VAULT_ADDR not set${NC}"
    exit 1
  fi
  
  # Try to reach Vault health endpoint
  if curl -sSf "${VAULT_ADDR}/v1/sys/health" -k >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Vault health check passed${NC}"
  else
    echo -e "${RED}✗ Cannot connect to Vault at ${VAULT_ADDR}${NC}"
    exit 1
  fi
  
  # Test Vault token retrieval
  echo -e "\n${YELLOW}Test 4: Vault AppRole Auth${NC}"
  
  if [[ -z "${VAULT_ROLE_ID:-}" ]] || [[ -z "${VAULT_SECRET_ID:-}" ]]; then
    echo -e "${YELLOW}⚠ AppRole credentials not provided, skipping auth test${NC}"
  else
    AUTH_RESULT=$(node -e "
const ss = require('./lib/secretStore.cjs');
(async () => {
  try {
    const tokenObj = { 
      token: 'vault-test-' + Date.now(), 
      created: new Date().toISOString(),
      backend_test: true
    };
    await ss.setToken(tokenObj);
    console.log('Vault auth successful');
  } catch (e) {
    console.error('Vault auth failed: ' + e.message);
    process.exit(1);
  }
})();
" 2>&1 || echo "failed")
    
    if [[ "$AUTH_RESULT" == *"successful"* ]]; then
      echo -e "${GREEN}✓ Vault AppRole auth test passed${NC}"
    else
      echo -e "${RED}✗ Vault AppRole auth failed${NC}"
      echo "$AUTH_RESULT"
      exit 1
    fi
  fi
else
  echo -e "${YELLOW}⊘ Using memory backend, Vault tests skipped${NC}"
fi

echo -e "\n${GREEN}✓ All tests passed!${NC}"
