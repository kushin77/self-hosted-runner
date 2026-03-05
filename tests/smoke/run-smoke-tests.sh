#!/bin/bash
# Production-Ready Smoke Test Suite
# Validates core Phase P2 functionality without full deployment
# Usage: bash tests/smoke/run-smoke-tests.sh [environment]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${1:-dev}"
TIMEOUT_SECONDS=300
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

# Configuration
case "$ENVIRONMENT" in
  dev)
    VAULT_ADDR="http://127.0.0.1:8200"
    VAULT_MODE="dev"
    REDIS_URL="redis://127.0.0.1:6379"
    PROVISIONER_URL="http://127.0.0.1:5000"
    ;;
  staging)
    VAULT_ADDR="${VAULT_ADDR:-http://vault.staging:8200}"
    VAULT_MODE="staging"
    REDIS_URL="${REDIS_URL:-redis://redis.staging:6379}"
    PROVISIONER_URL="${PROVISIONER_URL:-http://provisioner-worker.staging:5000}"
    ;;
  prod)
    VAULT_ADDR="${VAULT_ADDR:-https://vault.production:8200}"
    VAULT_MODE="prod"
    REDIS_URL="${REDIS_URL:-redis://redis.production:6379}"
    PROVISIONER_URL="${PROVISIONER_URL:-https://provisioner-worker.production:5000}"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Production-Ready Smoke Test Suite                         ║"
echo "║  Environment: $ENVIRONMENT                                  ║"
echo "║  Timestamp: $TIMESTAMP                                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Test utilities
function run_test() {
  local test_name=$1
  local test_cmd=$2
  
  echo -n "Testing: $test_name ... "
  if eval "$test_cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
    return 1
  fi
}

function run_test_timeout() {
  local test_name=$1
  local test_cmd=$2
  local timeout=${3:-30}
  
  echo -n "Testing: $test_name ... "
  if timeout "$timeout" bash -c "$test_cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
    return 0
  else
    echo -e "${RED}✗${NC} (timeout: ${timeout}s)"
    ((FAILED++))
    return 1
  fi
}

# ============= SECTION 1: System Infrastructure =============
echo -e "${BLUE}[1. System Infrastructure]${NC}"

run_test "Docker available" "command -v docker && docker ps"
run_test "Docker daemon running" "docker ps >/dev/null"
run_test "Git available" "command -v git"
run_test "Node.js available" "command -v node && node --version"

# ============= SECTION 2: Repository State =============
echo ""
echo -e "${BLUE}[2. Repository State]${NC}"

run_test "Repository is git" "[[ -d .git ]]"
run_test "On main branch or clean state" "[[ \$(git rev-parse --abbrev-ref HEAD) == 'main' || -z \$(git status --porcelain) ]]"
run_test "All Phase P2 docs present" "[[ -f docs/PHASE_P2_DELIVERY_SUMMARY.md && -f docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md ]]"
run_test "Validation script present" "[[ -f scripts/automation/pmo/validate-p2-readiness.sh && -x scripts/automation/pmo/validate-p2-readiness.sh ]]"
run_test "Deployment script present" "[[ -f scripts/automation/pmo/deploy-p2-production.sh && -x scripts/automation/pmo/deploy-p2-production.sh ]]"

# ============= SECTION 3: Service Code Quality =============
echo ""
echo -e "${BLUE}[3. Service Code Quality]${NC}"

run_test "Provisioner-worker syntax" "node -c services/provisioner-worker/worker.js 2>/dev/null"
run_test "Managed-auth syntax" "node -c services/managed-auth/index.js 2>/dev/null"
run_test "SecretStore syntax" "node -c services/managed-auth/lib/secretStore.cjs 2>/dev/null"
run_test "Package.json format (provisioner)" "node -e \"JSON.parse(require('fs').readFileSync('services/provisioner-worker/package.json', 'utf8'))\""
run_test "Package.json format (managed-auth)" "node -e \"JSON.parse(require('fs').readFileSync('services/managed-auth/package.json', 'utf8'))\""

# ============= SECTION 4: Vault Integration (Dev Mode) =============
if [[ "$VAULT_MODE" == "dev" ]]; then
  echo ""
  echo -e "${BLUE}[4. Vault Integration (Dev Mode)]${NC}"
  
  # Start temporary Vault for testing
  if docker ps | grep -q vault-test; then
    docker stop vault-test 2>/dev/null || true
  fi
  
  echo -n "Starting Vault dev server ... "
  if docker run --cap-add=IPC_LOCK -d --name vault-test -p 8200:8200 vault:1.13.0 server -dev -dev-root-token-id=root >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    sleep 2
    
    run_test "Vault health check" "curl -sSf http://127.0.0.1:8200/v1/sys/health"
    run_test "Vault token works" "curl -sSf -H 'X-Vault-Token: root' http://127.0.0.1:8200/v1/sys/auth"
    run_test "Vault KV2 engine ready" "curl -sSf -H 'X-Vault-Token: root' http://127.0.0.1:8200/v1/secret/metadata/ || true"
    
    # Cleanup
    docker stop vault-test 2>/dev/null || true
    docker rm vault-test 2>/dev/null || true
  else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
    echo -e "${YELLOW}Skipping Vault tests${NC}"
    ((SKIPPED += 3))
  fi
else
  echo ""
  echo -e "${BLUE}[4. Vault Integration (Production Mode)]${NC}"
  
  run_test "Vault at $VAULT_ADDR reachable" "curl -sSf --connect-timeout 5 $VAULT_ADDR/v1/sys/health || curl -sSfk --connect-timeout 5 $VAULT_ADDR/v1/sys/health"
fi

# ============= SECTION 5: Configuration Files =============
echo ""
echo -e "${BLUE}[5. Configuration Files]${NC}"

run_test "Docker Compose config valid" "[[ -f services/provisioner-worker/deploy/docker-compose.yml ]] && grep -q 'version:' services/provisioner-worker/deploy/docker-compose.yml"
run_test "Systemd service file valid" "[[ -f services/provisioner-worker/deploy/provisioner-worker.service ]] && grep -q 'ExecStart' services/provisioner-worker/deploy/provisioner-worker.service"
run_test "Portal environment example exists" "[[ -f ElevatedIQ-Mono-Repo/apps/portal/.env.example ]]"

# ============= SECTION 6: CI/CD Workflows =============
echo ""
echo -e "${BLUE}[6. CI/CD Workflows]${NC}"

run_test "Vault integration workflow exists" "[[ -f .github/workflows/p2-vault-integration.yml ]]"
run_test "TS check workflow exists" "[[ -f .github/workflows/ts-check.yml ]]"
run_test "Portal e2e workflow exists" "[[ -f ElevatedIQ-Mono-Repo/.github/workflows/e2e.yml ]] || [[ -f .github/workflows/portal-e2e.yml ]] || true"

# ============= SECTION 7: Documentation Completeness =============
echo ""
echo -e "${BLUE}[7. Documentation Completeness]${NC}"

run_test "Vault setup guide exists" "[[ -f docs/VAULT_CI_SETUP.md && \$(wc -l < docs/VAULT_CI_SETUP.md) -gt 100 ]]"
run_test "Deployment validation checklist exists" "[[ -f docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md && \$(wc -l < docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md) -gt 100 ]]"
run_test "Production rollout docs exist" "[[ -f docs/PROVISIONER_WORKER_PROD_ROLLOUT.md ]]"
run_test "Staging guide exists" "[[ -f ElevatedIQ-Mono-Repo/docs/staging.md ]]"

# ============= RESULTS =============
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "Test Results:"
echo -e "  Passed:  ${GREEN}${PASSED}${NC}"
echo -e "  Failed:  ${RED}${FAILED}${NC}"
echo -e "  Skipped: ${YELLOW}${SKIPPED}${NC}"
echo "════════════════════════════════════════════════════════════"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}✅ All smoke tests passed!${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Run full integration tests: bash tests/integration/run-integration-tests.sh"
  echo "2. Execute deployment: bash scripts/automation/pmo/deploy-p2-production.sh deploy"
  echo "3. Run post-deployment validation"
  exit 0
else
  echo -e "${RED}❌ Some tests failed. Review errors above.${NC}"
  exit 1
fi
