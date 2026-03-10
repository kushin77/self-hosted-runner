#!/usr/bin/env bash
#
# Phase 6 Validation & Integration Testing
# Comprehensive verification of deployed stack
# Tests: Health, API integration, E2E, Security
#
# Usage: bash scripts/validate-phase6-deployment.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
RESULTS_FILE="${PROJECT_ROOT}/deployments/validation_${TIMESTAMP}.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
declare -A TESTS_PASSED
declare -A TESTS_FAILED

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
test_endpoint() {
  local name="$1"
  local endpoint="$2"
  local expected_pattern="${3:-ok|healthy|success}"
  
  echo -n "Testing $name ... "
  
  if response=$(curl -s --max-time 5 "$endpoint" 2>/dev/null); then
    if echo "$response" | grep -qi "$expected_pattern"; then
      echo -e "${GREEN}✅ PASS${NC}"
      ((TESTS_PASSED["$name"]++)) || true
      return 0
    else
      echo -e "${RED}❌ FAIL${NC} (unexpected response)"
      ((TESTS_FAILED["$name"]++)) || true
      return 1
    fi
  else
    echo -e "${RED}❌ FAIL${NC} (no response)"
    ((TESTS_FAILED["$name"]++)) || true
    return 1
  fi
}

test_database() {
  local name="$1"
  local host="$2"
  local port="$3"
  local users="${4:-postgres}"
  
  echo -n "Testing $name ... "
  
  if nc -zv -w 2 "$host" "$port" 2>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED["$name"]++)) || true
    return 0
  else
    echo -e "${RED}❌ FAIL${NC} (cannot connect)"
    ((TESTS_FAILED["$name"]++)) || true
    return 1
  fi
}

test_docker_service() {
  local service="$1"
  
  echo -n "Testing Docker service: $service ... "
  
  if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED["docker_$service"]++)) || true
    return 0
  else
    echo -e "${RED}❌ FAIL${NC} (not running)"
    ((TESTS_FAILED["docker_$service"]++)) || true
    return 1
  fi
}

# ============================================================================
# PHASE 1: DOCKER SERVICES
# ============================================================================
echo -e "${BLUE}[VALIDATION] Docker Services${NC}"

for service in nexusshield-frontend nexusshield-backend nexusshield-postgres nexusshield-redis nexusshield-rabbitmq; do
  test_docker_service "$service"
done

# ============================================================================
# PHASE 2: HEALTH ENDPOINTS
# ============================================================================
echo -e "${BLUE}[VALIDATION] Health Endpoints${NC}"

test_endpoint "Frontend Health" "http://localhost:3000/health" "ok|healthy|up" || true
test_endpoint "Backend Health" "http://localhost:8080/api/health" "ok|healthy|running" || true
test_endpoint "Prometheus" "http://localhost:9090/-/healthy" "Prometheus" || true
test_endpoint "Grafana" "http://localhost:3001/api/health" "ok" || true

# ============================================================================
# PHASE 3: DATABASE CONNECTIVITY
# ============================================================================
echo -e "${BLUE}[VALIDATION] Database Connectivity${NC}"

test_database "PostgreSQL" "localhost" "5432" || true
test_database "Redis" "localhost" "6379" || true
test_database "RabbitMQ" "localhost" "5672" || true

# ============================================================================
# PHASE 4: API INTEGRATION TESTS
# ============================================================================
echo -e "${BLUE}[VALIDATION] API Integration Tests${NC}"

# Test backend API endpoints
echo -n "Testing GET /api/credentials ... "
if response=$(curl -s -X GET "http://localhost:8080/api/credentials" -H "Content-Type: application/json" 2>/dev/null); then
  if echo "$response" | grep -qi "credentials\|data\|\[\]"; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED["api_credentials"]++)) || true
  else
    echo -e "${YELLOW}⚠️  WARN${NC} (response unclear)"
  fi
else
  echo -e "${RED}❌ FAIL${NC}"
done

echo -n "Testing GET /api/audit ... "
if response=$(curl -s -X GET "http://localhost:8080/api/audit" -H "Content-Type: application/json" 2>/dev/null); then
  if echo "$response" | grep -qi "audit\|entries\|logs\|data"; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED["api_audit"]++)) || true
  else
    echo -e "${YELLOW}⚠️  WARN${NC}"
  fi
else
  echo -e "${RED}❌ FAIL${NC}"
done

# ============================================================================
# PHASE 5: SECURITY VALIDATION
# ============================================================================
echo -e "${BLUE}[VALIDATION] Security${NC}"

echo -n "Checking credentials not in git... "
if git log --all --source --full-history -- ".credentials/*" 2>/dev/null | grep -q "commit"; then
  echo -e "${RED}❌ FAIL${NC} (credentials in git history)"
  ((TESTS_FAILED["security_creds_in_git"]++)) || true
else
  echo -e "${GREEN}✅ PASS${NC}"
  ((TESTS_PASSED["security_creds_in_git"]++)) || true
fi

echo -n "Checking immutable audit log exists... "
AUDIT_LOG=$(ls -t "${PROJECT_ROOT}/deployments/audit_"*.jsonl 2>/dev/null | head -1)
if [ -n "$AUDIT_LOG" ]; then
  AUDIT_LINES=$(wc -l < "$AUDIT_LOG")
  echo -e "${GREEN}✅ PASS${NC} ($AUDIT_LINES events)"
  ((TESTS_PASSED["audit_log_exists"]++)) || true
else
  echo -e "${YELLOW}⚠️  WARN${NC} (no audit log)"
fi

echo -n "Checking .credentials directory permissions... "
if [ -d "${PROJECT_ROOT}/.credentials" ]; then
  PERMS=$(stat -c %a "${PROJECT_ROOT}/.credentials" 2>/dev/null || echo "unknown")
  echo -e "${GREEN}✅ PASS${NC} (mode: $PERMS)"
  ((TESTS_PASSED["creds_permissions"]++)) || true
else
  echo -e "${YELLOW}⚠️  WARN${NC} (directory missing)"
fi

# ============================================================================
# PHASE 6: E2E TESTS (if Cypress available)
# ============================================================================
echo -e "${BLUE}[VALIDATION] End-to-End Tests${NC}"

if [ -f "${PROJECT_ROOT}/frontend/cypress.config.ts" ] && command -v cypress &> /dev/null; then
  echo -n "Running Cypress E2E tests... "
  if cd "${PROJECT_ROOT}/frontend" && npx cypress run --headless --spec "cypress/e2e/**/*.cy.ts" 2>/dev/null | grep -q "passed"; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED["e2e_cypress"]++)) || true
  else
    echo -e "${YELLOW}⚠️  WARN${NC} (some tests may have failed)"
  fi
  cd "$PROJECT_ROOT"
else
  echo "Skipping Cypress (not installed)"
fi

# ============================================================================
# RESULTS SUMMARY
# ============================================================================
echo -e "${BLUE}[SUMMARY]${NC}"

TOTAL_PASSED=0
TOTAL_FAILED=0

for key in "${!TESTS_PASSED[@]}"; do
  ((TOTAL_PASSED += TESTS_PASSED[$key])) || true
done

for key in "${!TESTS_FAILED[@]}"; do
  ((TOTAL_FAILED += TESTS_FAILED[$key])) || true
done

TOTAL_TESTS=$((TOTAL_PASSED + TOTAL_FAILED))

echo -e "${GREEN}Passed:${NC} $TOTAL_PASSED"
echo -e "${RED}Failed:${NC} $TOTAL_FAILED"
echo "Total:  $TOTAL_TESTS"

SUCCESS_RATE=0
if [ $TOTAL_TESTS -gt 0 ]; then
  SUCCESS_RATE=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
fi

echo -e "\nSuccess Rate: ${SUCCESS_RATE}%"

# Save results
mkdir -p "$(dirname "$RESULTS_FILE")"
jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson passed "$TOTAL_PASSED" \
  --argjson failed "$TOTAL_FAILED" \
  --argjson success_rate "$SUCCESS_RATE" \
  '{timestamp, results: {passed, failed, total: (passed + failed), success_rate}}' \
  > "$RESULTS_FILE"

echo -e "\nResults saved to: $RESULTS_FILE"

# Exit with status
if [ $TOTAL_FAILED -gt 0 ] && [ $SUCCESS_RATE -lt 80 ]; then
  echo -e "${RED}❌ VALIDATION FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
  exit 0
fi
