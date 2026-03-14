#!/bin/bash
################################################################################
# FRESH BUILD MANDATE - INTEGRATION TEST SUITE
#
# Tests for fresh build deployment mandate enforcement:
# - Fresh build script files exist
# - Deployment scripts have fresh build support
# - Documentation covers fresh build mandate
#
# Usage: bash scripts/enforce/test-fresh-build-mandate.sh
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

# Helper functions
pass() { echo -e "${GREEN}[PASS]${NC} $1" && ((PASSED++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1" && ((FAILED++)); }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     FRESH BUILD MANDATE - INTEGRATION TEST SUITE               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Fresh build mandate library
echo -e "${BLUE}=== Files and Scripts ===${NC}"
[[ -f "scripts/enforce/fresh-build-mandate.sh" ]] && pass "fresh-build-mandate.sh exists" || fail "fresh-build-mandate.sh not found"
[[ -x "scripts/enforce/fresh-build-mandate.sh" ]] && pass "fresh-build-mandate.sh is executable" || fail "fresh-build-mandate.sh is not executable"
[[ -f "scripts/enforce/verify-fresh-build-deployment.sh" ]] && pass "verify-fresh-build-deployment.sh exists" || fail "verify-fresh-build-deployment.sh not found"
[[ -x "scripts/enforce/verify-fresh-build-deployment.sh" ]] && pass "verify-fresh-build-deployment.sh is executable" || fail "verify-fresh-build-deployment.sh is not executable"
echo ""

# Test 2: Deployment script integration
echo -e "${BLUE}=== Deployment Scripts ===${NC}"
grep -q "PHASE 1: MANDATE VALIDATION" deploy-worker-node.sh && pass "deploy-worker-node.sh has fresh build phases" || fail "deploy-worker-node.sh missing fresh build phases"
grep -q "enforce_fresh_build_mandate" deploy-onprem.sh && pass "deploy-onprem.sh calls fresh build enforcement" || fail "deploy-onprem.sh missing fresh build enforcement"
grep -q "enforce_fresh_build_mandate" deploy-standalone.sh && pass "deploy-standalone.sh calls fresh build enforcement" || fail "deploy-standalone.sh missing fresh build enforcement"
echo ""

# Test 3: Documentation
echo -e "${BLUE}=== Documentation ===${NC}"
grep -q "ENFORCEMENT RULE #6" ENFORCEMENT_RULES.md && pass "ENFORCEMENT_RULES.md documents Rule #6" || fail "ENFORCEMENT_RULES.md missing Rule #6"
grep -q "Mandate #6" CODE_MANDATES.md && pass "CODE_MANDATES.md documents Mandate #6" || fail "CODE_MANDATES.md missing Mandate #6"
grep -q "Fresh Build Deployment" DEPLOYMENT_INSTRUCTIONS.md && pass "DEPLOYMENT_INSTRUCTIONS.md covers fresh builds" || fail "DEPLOYMENT_INSTRUCTIONS.md missing fresh build docs"
echo ""

# Test 4: Git
echo -e "${BLUE}=== Git Integration ===${NC}"
git log --oneline -10 | grep -q "fresh\|Fresh\|FRESH" && pass "Recent commits include fresh build work" || fail "No fresh build commits"
echo ""

# Print summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    TEST RESULTS                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ Passed:${NC}  $PASSED tests"
echo -e "${RED}❌ Failed:${NC}  $FAILED tests"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}⚠️  SOME TESTS FAILED${NC}"
    exit 1
fi
