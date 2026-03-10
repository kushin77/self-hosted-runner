#!/bin/bash
# Phase 6: Complete Health Check & Integration Status Report
# Purpose: Validate all Portal MVP components are healthy and integrated
# Output: Terminal report + JSON audit log

set -euo pipefail

# Configuration
PROJECT="${GCP_PROJECT:-unknown}"
AUDIT_LOG="logs/phase6-health-check-$(date +%Y%m%d-%H%M%S).jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p logs

# Track results
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

# Initialize audit
{
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"6\",\"action\":\"health_check_start\",\"project\":\"$PROJECT\",\"hostname\":\"$(hostname)\"}"
} | tee -a "$AUDIT_LOG"

print_section() {
  echo ""
  echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}│ $1${NC}"
  echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
}

check_pass() {
  local name="$1"
  local details="${2:-}"
  echo -e "${GREEN}✓${NC} $name${details:+" ($details)"}"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"6\",\"check\":\"$name\",\"status\":\"pass\"}" | tee -a "$AUDIT_LOG"
  ((PASS_COUNT++))
}

check_fail() {
  local name="$1"
  local error="${2:-unknown error}"
  echo -e "${RED}✗${NC} $name - $error"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"6\",\"check\":\"$name\",\"status\":\"fail\",\"error\":\"$error\"}" | tee -a "$AUDIT_LOG"
  ((FAIL_COUNT++))
}

check_warn() {
  local name="$1"
  local warning="${2:-}"
  echo -e "${YELLOW}⚠${NC} $name${warning:+" - $warning"}"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"6\",\"check\":\"$name\",\"status\":\"warn\"}" | tee -a "$AUDIT_LOG"
  ((WARN_COUNT++))
}

check_skip() {
  local name="$1"
  local reason="${2:-not available}"
  echo -e "${YELLOW}⊘${NC} $name (skipped: $reason)"
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"6\",\"check\":\"$name\",\"status\":\"skip\",\"reason\":\"$reason\"}" | tee -a "$AUDIT_LOG"
  ((SKIP_COUNT++))
}

# ========== INFRASTRUCTURE CHECKS ==========
print_section "1. INFRASTRUCTURE & NETWORK"

# Docker availability
if command -v docker >/dev/null 2>&1; then
  if docker ps >/dev/null 2>&1; then
    RUNNING=$(docker ps --format "{{.Names}}" | grep -c "nexusshield" || true)
    if [ "$RUNNING" -gt 0 ]; then
      check_pass "Docker Engine" "running with $RUNNING nexusshield containers"
    else
      check_warn "Docker Engine" "available but no nexusshield containers running"
    fi
  else
    check_fail "Docker Engine" "docker daemon not responding"
  fi
else
  check_skip "Docker Engine" "docker not installed"
fi

# Docker Compose
if command -v docker-compose >/dev/null 2>&1; then
  VER=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
  check_pass "Docker Compose" "$VER"
else
  check_skip "Docker Compose" "not installed"
fi

# Network connectivity
if nc -zv localhost 3000 2>/dev/null; then
  check_pass "Port 3000 (Frontend)" "accessible"
else
  check_warn "Port 3000 (Frontend)" "not listening (container may not be running)"
fi

if nc -zv localhost 8080 2>/dev/null; then
  check_pass "Port 8080 (API)" "accessible"
else
  check_warn "Port 8080 (API)" "not listening"
fi

if nc -zv localhost 5432 2>/dev/null; then
  check_pass "Port 5432 (Database)" "accessible"
else
  check_warn "Port 5432 (Database)" "not listening"
fi

# ========== FRONTEND CHECKS ==========
print_section "2. FRONTEND"

if [ -d "frontend" ]; then
  check_pass "Frontend directory" "exists"
  
  if [ -d "frontend/dist" ]; then
    SIZE=$(du -sh frontend/dist | cut -f1)
    check_pass "Frontend build" "production build ready ($SIZE)"
  else
    check_warn "Frontend build" "dist not found (run: npm run build)"
  fi
  
  if [ -f "frontend/package.json" ]; then
    VERSION=$(grep '"version"' frontend/package.json | head -1 | cut -d'"' -f4)
    check_pass "Frontend package.json" "v$VERSION"
  else
    check_warn "Frontend package.json" "not found"
  fi
  
  if [ -d "frontend/cypress" ]; then
    TEST_COUNT=$(find frontend/cypress/e2e -name "*.cy.ts" 2>/dev/null | wc -l || true)
    if [ "$TEST_COUNT" -gt 0 ]; then
      check_pass "Cypress E2E tests" "$TEST_COUNT test files"
    else
      check_warn "Cypress E2E tests" "no test files found"
    fi
  else
    check_warn "Cypress E2E tests" "directory not found"
  fi
else
  check_fail "Frontend directory" "not found"
fi

# ========== BACKEND CHECKS ==========
print_section "3. BACKEND API"

if [ -d "backend" ]; then
  check_pass "Backend directory" "exists"
  
  if [ -f "backend/requirements.txt" ] || [ -f "backend/Pipfile" ]; then
    check_pass "Backend dependencies" "specified"
  else
    check_warn "Backend dependencies" "no requirements file found"
  fi
  
  if [ -d "backend/migrations" ]; then
    MIGRATION_COUNT=$(find backend/migrations -name "*.sql" 2>/dev/null | wc -l || true)
    if [ "$MIGRATION_COUNT" -gt 0 ]; then
      check_pass "Database migrations" "$MIGRATION_COUNT migrations"
    else
      check_warn "Database migrations" "directory exists but empty"
    fi
  else
    check_warn "Database migrations" "directory not found"
  fi
  
  if [ -d "backend/tests" ]; then
    TEST_COUNT=$(find backend/tests -name "*.py" -o -name "*.go" 2>/dev/null | wc -l || true)
    if [ "$TEST_COUNT" -gt 0 ]; then
      check_pass "Backend tests" "$TEST_COUNT test files"
    else
      check_warn "Backend tests" "directory exists but empty"
    fi
  else
    check_warn "Backend tests" "directory not found"
  fi
else
  check_fail "Backend directory" "not found"
fi

# API endpoint check
if curl -s -f http://localhost:8080/health >/dev/null 2>&1; then
  HEALTH=$(curl -s http://localhost:8080/health | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
  check_pass "API /health endpoint" "responding ($HEALTH)"
else
  check_warn "API /health endpoint" "not responding (API may not be running)"
fi

# ========== DATABASE CHECKS ==========
print_section "4. DATABASE"

if command -v psql >/dev/null 2>&1; then
  if psql -U portal_user -d portal_db -c "SELECT 1" >/dev/null 2>&1; then
    TABLE_COUNT=$(psql -U portal_user -d portal_db -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo "0")
    check_pass "PostgreSQL connection" "$TABLE_COUNT tables"
  else
    check_warn "PostgreSQL connection" "cannot connect (may not be running)"
  fi
else
  check_skip "PostgreSQL" "psql client not available"
fi

# ========== OBSERVABILITY CHECKS ==========
print_section "5. OBSERVABILITY"

# Prometheus
if curl -s -f http://localhost:9090/-/ready >/dev/null 2>&1; then
  TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets | length' 2>/dev/null || echo "0")
  check_pass "Prometheus" "running with $TARGETS active targets"
else
  check_warn "Prometheus" "not responding (http://localhost:9090)"
fi

# Grafana
if curl -s -f http://localhost:3001/api/health >/dev/null 2>&1; then
  check_pass "Grafana" "running (http://localhost:3001)"
else
  check_warn "Grafana" "not responding (http://localhost:3001)"
fi

# Loki
if curl -s -f http://localhost:3100/ready >/dev/null 2>&1; then
  check_pass "Loki" "running"
else
  check_warn "Loki" "not responding (http://localhost:3100)"
fi

# Jaeger
if curl -s -f http://localhost:16686 >/dev/null 2>&1; then
  check_pass "Jaeger" "running (http://localhost:16686)"
else
  check_warn "Jaeger" "not responding (http://localhost:16686)"
fi

# ========== CACHE & MESSAGING CHECKS ==========
print_section "6. CACHE & MESSAGING"

# Redis
if command -v redis-cli >/dev/null 2>&1; then
  if redis-cli -h localhost ping >/dev/null 2>&1; then
    SIZE=$(redis-cli dbsize 2>/dev/null | cut -d':' -f2 || echo "unknown")
    check_pass "Redis" "responsive ($SIZE keys)"
  else
    check_warn "Redis" "not responding (may not be running)"
  fi
else
  check_skip "Redis" "redis-cli not available"
fi

# RabbitMQ
if curl -s -f http://localhost:15672/api/health/checks/virtual-hosts >/dev/null 2>&1; then
  check_pass "RabbitMQ" "running (http://localhost:15672)"
else
  check_warn "RabbitMQ" "not responding"
fi

# ========== SECURITY CHECKS ==========
print_section "7. SECURITY"

# Environment secrets
if [ -f ".env" ]; then
  check_pass "Environment file" ".env exists"
else
  check_warn "Environment file" ".env not found (needed for credentials)"
fi

# Git security
if [ -d ".git" ]; then
  check_pass "Git repository" "initialized"
  
  if grep -r "password\|token\|secret" .git/ >/dev/null 2>&1; then
    check_warn "Git security" "potential secrets in .git/ (verify)"
  else
    check_pass "Git security" "no obvious secrets exposed"
  fi
else
  check_warn "Git repository" "not initialized"
fi

# ========== AUDIT & LOGGING CHECKS ==========
print_section "8. AUDIT & LOGGING"

if [ -d "logs" ]; then
  AUDIT_COUNT=$(find logs -name "*.jsonl" 2>/dev/null | wc -l || true)
  if [ "$AUDIT_COUNT" -gt 0 ]; then
    check_pass "Audit logs" "$AUDIT_COUNT JSONL files"
  else
    check_warn "Audit logs" "directory exists but empty"
  fi
else
  check_warn "Audit logs" "logs directory not created yet"
fi

# ========== BUILD & DEPLOYMENT CHECKS ==========
print_section "9. BUILD & DEPLOYMENT"

# Docker images
if command -v docker >/dev/null 2>&1; then
  IMAGES=$(docker images --filter "reference=nexusshield*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
  if [ -n "$IMAGES" ]; then
    check_pass "Docker images" "$(echo "$IMAGES" | wc -l) local images built"
  else
    check_warn "Docker images" "no nexusshield images found (run: docker-compose build)"
  fi
fi

# Terraform (if applicable)
if [ -d "terraform" ]; then
  TF_COUNT=$(find terraform -name "*.tf" 2>/dev/null | wc -l || true)
  check_pass "Terraform" "$TF_COUNT configuration files"
else
  check_skip "Terraform" "infrastructure as code not found"
fi

# ========== INTEGRATION TESTS ==========
print_section "10. INTEGRATION TESTS"

if [ -d "backend/tests/integration" ]; then
  INT_TEST_COUNT=$(find backend/tests/integration -name "*.py" 2>/dev/null | wc -l || true)
  if [ "$INT_TEST_COUNT" -gt 0 ]; then
    check_pass "Backend integration tests" "$INT_TEST_COUNT test files"
  else
    check_warn "Backend integration tests" "directory empty"
  fi
else
  check_warn "Backend integration tests" "directory not found"
fi

if [ -d "frontend/cypress" ]; then
  E2E_COUNT=$(find frontend/cypress/e2e -name "*.cy.ts" 2>/dev/null | wc -l || true)
  if [ "$E2E_COUNT" -gt 0 ]; then
    check_pass "Frontend E2E tests" "$E2E_COUNT test specs"
  else
    check_warn "Frontend E2E tests" "no test files"
  fi
fi

# ========== SUMMARY ==========
print_section "SUMMARY"

{
  echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"phase\":\"6\",\"action\":\"health_check_complete\",\"passed\":$PASS_COUNT,\"failed\":$FAIL_COUNT,\"warnings\":$WARN_COUNT,\"skipped\":$SKIP_COUNT}"
} | tee -a "$AUDIT_LOG"

echo ""
echo "Results:"
echo -e "  ${GREEN}✓ Passed:  $PASS_COUNT${NC}"
echo -e "  ${RED}✗ Failed:  $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}⚠ Warnings: $WARN_COUNT${NC}"
echo -e "  ${YELLOW}⊘ Skipped: $SKIP_COUNT${NC}"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + SKIP_COUNT))
HEALTH_PERCENT=$(echo "scale=1; ($PASS_COUNT * 100) / $TOTAL" | bc 2>/dev/null || echo "0")
echo -e "Overall Health: ${GREEN}$HEALTH_PERCENT%${NC} ($PASS_COUNT/$TOTAL critical checks passed)"
echo ""
echo "Audit Log: $AUDIT_LOG"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✓ Phase 6 Systems Ready for Integration${NC}"
  exit 0
else
  echo -e "${RED}✗ Phase 6 has $FAIL_COUNT critical issues - review above${NC}"
  exit 1
fi
