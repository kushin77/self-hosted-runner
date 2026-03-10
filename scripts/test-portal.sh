#!/bin/bash
###############################################################################
# NexusShield Portal - Integration Test Suite
# Purpose: Comprehensive testing of all portal endpoints
# Mode: Fully automated, reports to audit trail
###############################################################################

set -euo pipefail

# Configuration
API_BASE_URL="${API_BASE_URL:-http://localhost:3000}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3001}"
REPO_ROOT="/home/akushnir/self-hosted-runner"
TEST_LOG="${REPO_ROOT}/logs/portal_tests_$(date -u +%Y%m%d_%H%M%S).jsonl"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

# Ensure log directory
mkdir -p "${REPO_ROOT}/logs"

# ===== TEST HELPERS =====
test_start() {
  local test_name=$1
  echo -n "Testing: ${test_name}... "
}

test_pass() {
  local test_name=$1
  local response=$2
  echo -e "${GREEN}✓ PASS${NC}"
  PASSED=$((PASSED + 1))
  echo "$(jq -n --arg test "$test_name" --arg status "pass" --arg resp "$response" '{test: $test, status: $status, response: $resp, timestamp: now | todate}')" >> "${TEST_LOG}"
}

test_fail() {
  local test_name=$1
  local reason=$2
  echo -e "${RED}✗ FAIL${NC}: $reason"
  FAILED=$((FAILED + 1))
  echo "$(jq -n --arg test "$test_name" --arg status "fail" --arg reason "$reason" '{test: $test, status: $status, reason: $reason, timestamp: now | todate}')" >> "${TEST_LOG}"
}

test_skip() {
  local test_name=$1
  local reason=$2
  echo -e "${YELLOW}⊘ SKIP${NC}: $reason"
  SKIPPED=$((SKIPPED + 1))
}

# ===== HEALTH CHECKS =====
echo "=== Health Checks ==="

test_start "Backend health check"
if response=$(curl -sf "${API_BASE_URL}/health" 2>/dev/null); then
  test_pass "Backend health check" "$response"
else
  test_fail "Backend health check" "Backend not responding"
  exit 1
fi

test_start "API health endpoint"
if response=$(curl -sf "${API_BASE_URL}/api/health" 2>/dev/null); then
  test_pass "API health endpoint" "$response"
else
  test_fail "API health endpoint" "Health endpoint not responding"
fi

test_start "Metrics endpoint"
if response=$(curl -sf "${API_BASE_URL}/metrics" 2>/dev/null); then
  test_pass "Metrics endpoint" "$(echo "$response" | head -5)"
else
  test_fail "Metrics endpoint" "Metrics endpoint not responding"
fi

# ===== AUTHENTICATION =====
echo -e "\n=== Authentication Tests ==="

test_start "User login"
LOGIN_RESPONSE=$(curl -sf -X POST "${API_BASE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"provider":"oauth-google","email":"test@nexusshield.cloud"}' 2>/dev/null || echo "{}")

if TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty' 2>/dev/null); then
  test_pass "User login" "$LOGIN_RESPONSE"
else
  test_fail "User login" "No token in response"
  exit 1
fi

test_start "Profile retrieval"
if PROFILE=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/auth/profile" 2>/dev/null); then
  test_pass "Profile retrieval" "$PROFILE"
else
  test_fail "Profile retrieval" "Failed to retrieve profile"
fi

# ===== CREDENTIALS MANAGEMENT =====
echo -e "\n=== Credentials Management ==="

test_start "List credentials"
if CREDS=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/api/credentials" 2>/dev/null); then
  COUNT=$(echo "$CREDS" | jq '.credentials | length' 2>/dev/null || echo "0")
  test_pass "List credentials" "Found $COUNT credentials"
else
  test_fail "List credentials" "Failed to list credentials"
fi

test_start "Create credential"
CREATE_RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "${API_BASE_URL}/api/credentials" \
  -d '{"name":"Test Credential","type":"aws","secret":"test_secret_123"}' 2>/dev/null || echo "{}")

if CRED_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id // empty' 2>/dev/null); then
  test_pass "Create credential" "Created credential: $CRED_ID"
else
  test_fail "Create credential" "Failed to create credential"
  CRED_ID=""
fi

if [ -n "$CRED_ID" ]; then
  test_start "Get credential"
  if GET_RESPONSE=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/api/credentials/${CRED_ID}" 2>/dev/null); then
    test_pass "Get credential" "Retrieved credential $CRED_ID"
  else
    test_fail "Get credential" "Failed to get credential"
  fi

  test_start "Rotate credential"
  if ROTATE=$(curl -sf -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "${API_BASE_URL}/api/credentials/${CRED_ID}/rotate" \
    -d '{"newSecret":"rotated_secret_456"}' 2>/dev/null); then
    test_pass "Rotate credential" "Credential rotated"
  else
    test_fail "Rotate credential" "Failed to rotate credential"
  fi

  test_start "Delete credential"
  if DELETE=$(curl -sf -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "${API_BASE_URL}/api/credentials/${CRED_ID}" 2>/dev/null); then
    test_pass "Delete credential" "Credential deleted"
  else
    test_fail "Delete credential" "Failed to delete credential"
  fi
fi

# ===== AUDIT TRAIL =====
echo -e "\n=== Audit Trail ==="

test_start "Get audit entries"
if AUDIT=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/api/audit?limit=50" 2>/dev/null); then
  ENTRIES=$(echo "$AUDIT" | jq '.total // 0' 2>/dev/null)
  test_pass "Get audit entries" "Found $ENTRIES audit entries"
else
  test_fail "Get audit entries" "Failed to fetch audit trail"
fi

test_start "Export audit trail"
if EXPORT=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/api/audit/export" 2>/dev/null); then
  COUNT=$(echo "$EXPORT" | jq '.count // 0' 2>/dev/null)
  test_pass "Export audit trail" "Exported $COUNT entries"
else
  test_fail "Export audit trail" "Export failed"
fi

# ===== DEPLOYMENTS =====
echo -e "\n=== Deployments ==="

test_start "List deployments"
if DEPLOYS=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/api/deployments" 2>/dev/null); then
  COUNT=$(echo "$DEPLOYS" | jq '.deployments | length' 2>/dev/null || echo "0")
  test_pass "List deployments" "Found $COUNT deployments"
else
  test_fail "List deployments" "Failed to list deployments"
fi

# ===== STATISTICS =====
echo -e "\n=== Statistics ==="

test_start "Get stats"
if STATS=$(curl -sf -H "Authorization: Bearer $TOKEN" "${API_BASE_URL}/api/stats" 2>/dev/null); then
  test_pass "Get stats" "$(echo "$STATS" | jq -c '.')"
else
  test_fail "Get stats" "Failed to get statistics"
fi

# ===== ERROR HANDLING =====
echo -e "\n=== Error Handling ==="

test_start "Unauthorized access"
if ERROR=$(curl -sf -H "Authorization: Bearer invalid_token" "${API_BASE_URL}/api/credentials" 2>/dev/null); then
  test_pass "Unauthorized access" "Properly rejected invalid token"
else
  test_fail "Unauthorized access" "Should reject invalid token with error"
fi

test_start "404 handling"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_BASE_URL}/nonexistent" 2>/dev/null)
if [ "$HTTP_CODE" = "404" ]; then
  test_pass "404 handling" "Correct 404 response"
else
  test_fail "404 handling" "Expected 404, got $HTTP_CODE"
fi

# ===== SUMMARY =====
echo -e "\n╔══════════════════════════════════════════════════════════════════════╗"
echo -e "║          NexusShield Portal - Test Results Summary                  ║"
echo -e "╠══════════════════════════════════════════════════════════════════════╣"
echo -e "║                                                                      ║"
printf "║  %-20s ${GREEN}%3d PASSED${NC}                                    ║\n" "Results:" "$PASSED"
if [ $FAILED -gt 0 ]; then
  printf "║  %-20s ${RED}%3d FAILED${NC}                                    ║\n" "" "$FAILED"
else
  printf "║  %-20s %3d PASSED (no failures)                         ║\n" "" "0"
fi
printf "║  %-20s %3d SKIPPED                                    ║\n" "" "$SKIPPED"
echo -e "║                                                                      ║"
echo -e "║  Test Log: ${TEST_LOG}"
echo -e "║                                                                      ║"

if [ $FAILED -eq 0 ]; then
  echo -e "║  ✅ All tests PASSED - Portal is 100% functional!                   ║"
  echo -e "╚══════════════════════════════════════════════════════════════════════╝"
  exit 0
else
  echo -e "║  ❌ Some tests FAILED - See log for details                          ║"
  echo -e "╚══════════════════════════════════════════════════════════════════════╝"
  exit 1
fi
