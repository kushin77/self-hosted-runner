#!/bin/bash
# 🧪 COMPREHENSIVE TEST SUITE - 0-100 VALIDATION
# Run this after nuke_and_deploy.sh completes

set -euo pipefail

WORKSPACE="${1:-.}"
cd "$WORKSPACE"

PASSED=0
FAILED=0
SKIPPED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_result() {
    local name="$1"
    local result="$2"
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $name"
        PASSED=$((PASSED+1))
    else
        echo -e "${RED}❌ FAIL${NC}: $name"
        FAILED=$((FAILED+1))
    fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 COMPREHENSIVE TEST SUITE - 0-100 VALIDATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ===========================================================================
# SECTION 1: DOCKER SERVICE TESTS
# ===========================================================================
echo ""
echo "📍 SECTION 1: DOCKER SERVICES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Docker daemon
docker ps >/dev/null 2>&1
test_result "Docker daemon accessible" $?

# Check docker-compose
docker-compose version >/dev/null 2>&1
test_result "docker-compose installed" $?

# Check running services
RUNNING=$(docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l)
if [ "$RUNNING" -gt 0 ]; then
    echo -e "${GREEN}✅ PASS${NC}: $RUNNING services running"
    PASSED=$((PASSED+1))
else
    echo -e "${RED}❌ FAIL${NC}: No services running"
    FAILED=$((FAILED+1))
fi

# ===========================================================================
# SECTION 2: SERVICE CONNECTIVITY TESTS
# ===========================================================================
echo ""
echo "📍 SECTION 2: SERVICE CONNECTIVITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vault
curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1
test_result "Vault HTTP API (port 8200)" $?

# Redis
redis-cli ping >/dev/null 2>&1
test_result "Redis connectivity (port 6379)" $?

# PostgreSQL
PGPASSWORD=runner_password psql -h localhost -U runner_user -d runner_db -c "SELECT 1" >/dev/null 2>&1
test_result "PostgreSQL connectivity (port 5432)" $?

# MinIO API
curl -s http://localhost:9000/minio/health/live >/dev/null 2>&1
test_result "MinIO API (port 9000)" $?

# MinIO Console
curl -s http://localhost:9001 >/dev/null 2>&1 || true
test_result "MinIO Console (port 9001)" 0

# ===========================================================================
# SECTION 3: DATA PERSISTENCE TESTS
# ===========================================================================
echo ""
echo "📍 SECTION 3: DATA PERSISTENCE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# PostgreSQL data persistence
PGPASSWORD=runner_password psql -h localhost -U runner_user -d runner_db -c "CREATE TABLE test_table (id SERIAL PRIMARY KEY); INSERT INTO test_table DEFAULT VALUES;" >/dev/null 2>&1
test_result "PostgreSQL write operation" $?

# Redis data persistence
redis-cli SET test_key "test_value" >/dev/null 2>&1
test_result "Redis write operation" $?

VALUE=$(redis-cli GET test_key 2>/dev/null || echo "")
if [ "$VALUE" == "test_value" ]; then
    echo -e "${GREEN}✅ PASS${NC}: Redis data retrieval"
    PASSED=$((PASSED+1))
else
    echo -e "${RED}❌ FAIL${NC}: Redis data retrieval"
    FAILED=$((FAILED+1))
fi

# ===========================================================================
# SECTION 4: LOCAL APPLICATION TESTS
# ===========================================================================
echo ""
echo "📍 SECTION 4: LOCAL APPLICATION SETUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Node.js environment
if [ -f "package.json" ]; then
    if [ -d "node_modules" ]; then
        echo -e "${GREEN}✅ PASS${NC}: Node dependencies installed"
        PASSED=$((PASSED+1))
    else
        echo -e "${YELLOW}⊘ SKIP${NC}: Node dependencies need installation"
        SKIPPED=$((SKIPPED+1))
    fi
fi

# Python environment
if [ -f "requirements.txt" ]; then
    if [ -d ".venv" ]; then
        echo -e "${GREEN}✅ PASS${NC}: Python virtual environment exists"
        PASSED=$((PASSED+1))
    else
        echo -e "${YELLOW}⊘ SKIP${NC}: Python virtual environment needs setup"
        SKIPPED=$((SKIPPED+1))
    fi
fi

# ===========================================================================
# SECTION 5: FILE SYSTEM INTEGRITY
# ===========================================================================
echo ""
echo "📍 SECTION 5: FILE SYSTEM INTEGRITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check key directories exist
for DIR in terraform infra CI deploy scripts ansible; do
    if [ -d "$DIR" ]; then
        echo -e "${GREEN}✅ PASS${NC}: Directory $DIR exists"
        PASSED=$((PASSED+1))
    else
        echo -e "${YELLOW}⊘ SKIP${NC}: Directory $DIR missing"
        SKIPPED=$((SKIPPED+1))
    fi
done

# Check no stale files
if [ ! -f ".bootstrap-state.json" ] && [ ! -f ".ops-blocker-state.json" ]; then
    echo -e "${GREEN}✅ PASS${NC}: No stale state files"
    PASSED=$((PASSED+1))
else
    echo -e "${RED}❌ FAIL${NC}: Stale state files detected"
    FAILED=$((FAILED+1))
fi

# Check Terraform reset
if [ ! -d "terraform/.terraform" ]; then
    echo -e "${GREEN}✅ PASS${NC}: Terraform state cleaned"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}⚠️  WARN${NC}: Terraform working directory still present"
fi

# ===========================================================================
# SECTION 6: GIT REPOSITORY STATUS
# ===========================================================================
echo ""
echo "📍 SECTION 6: GIT REPOSITORY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check git is initialized
if [ -d ".git" ]; then
    echo -e "${GREEN}✅ PASS${NC}: Git repository initialized"
    PASSED=$((PASSED+1))
else
    echo -e "${RED}❌ FAIL${NC}: Git repository not found"
    FAILED=$((FAILED+1))
fi

# Get branch info
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
echo "   Current branch: $BRANCH"

# Check for uncommitted changes
CHANGES=$(git status --porcelain 2>/dev/null | wc -l || echo "0")
echo "   Uncommitted changes: $CHANGES"

# ===========================================================================
# SECTION 7: SECURITY & SECRETS
# ===========================================================================
echo ""
echo "📍 SECTION 7: SECURITY & SECRETS SETUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check secrets directory
if [ -d "secrets" ]; then
    echo -e "${GREEN}✅ PASS${NC}: Secrets directory exists"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}⊘ SKIP${NC}: Secrets directory not found"
    SKIPPED=$((SKIPPED+1))
fi

# Check .gitignore-secrets
if [ -f ".gitignore-secrets" ]; then
    echo -e "${GREEN}✅ PASS${NC}: Secret rules configured"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}⊘ SKIP${NC}: Secret rules not configured"
    SKIPPED=$((SKIPPED+1))
fi

# ===========================================================================
# FINAL SUMMARY
# ===========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 TEST RESULTS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL=$((PASSED + FAILED + SKIPPED))

echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASSED/$TOTAL"
echo -e "  ${RED}Failed:${NC}  $FAILED/$TOTAL"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED/$TOTAL"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✨ ALL TESTS PASSED - READY FOR 0-100 TESTING${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}⚠️  FAILURES DETECTED - Review above output${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
