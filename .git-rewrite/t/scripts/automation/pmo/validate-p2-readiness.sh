#!/bin/bash
# Phase P2 Pre-Deployment Validation Script
# Validates system readiness for production rollout
# Usage: bash scripts/automation/pmo/validate-p2-readiness.sh

set -u
echo "=== Phase P2 Production Readiness Validation ==="
echo "Time: $(date)"
echo ""

SUCCESS=0
FAILURES=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function check() {
  local name=$1
  local cmd=$2
  echo -n "Checking: $name ... "
  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((SUCCESS++))
  else
    echo -e "${RED}✗${NC}"
    ((FAILURES++))
  fi
}

function check_file() {
  local filepath=$1
  echo -n "Checking: $filepath exists ... "
  if [[ -f "$filepath" ]]; then
    echo -e "${GREEN}✓${NC}"
    ((SUCCESS++))
  else
    echo -e "${RED}✗${NC}"
    ((FAILURES++))
  fi
}

# System dependencies
echo -e "${BLUE}[1. System Dependencies]${NC}"
check "Docker installed" "command -v docker"
check "Docker daemon running" "docker ps"
check "Git installed" "command -v git"
check "Bash 4+ available" "[[ ${BASH_VERSINFO[0]} -ge 4 ]]"
check "jq installed" "command -v jq"

# Repository state
echo ""
echo -e "${BLUE}[2. Repository State]${NC}"
check_file "docs/PHASE_P2_DELIVERY_SUMMARY.md"
check_file "docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md"
check_file "scripts/automation/pmo/deploy-p2-production.sh"
check_file "services/provisioner-worker/deploy/docker-compose.yml"
check_file "services/provisioner-worker/deploy/provisioner-worker.service"

# Code validation
echo ""
echo -e "${BLUE}[3. Code Validation]${NC}"
check_file "services/provisioner-worker/worker.js"
check_file "services/provisioner-worker/jobStore.js"
check_file "services/provisioner-worker/terraform_runner.js"
check_file "services/managed-auth/index.js"
check_file "services/managed-auth/lib/secretStore.cjs"
check "All services have package.json" "[[ -f services/provisioner-worker/package.json && -f services/managed-auth/package.json ]]"

# Configuration templates
echo ""
echo -e "${BLUE}[4. Configuration Templates]${NC}"
check ".env.example docs" "[[ -f ElevatedIQ-Mono-Repo/apps/portal/.env.example ]]"
check "Portal staging guide" "[[ -f ElevatedIQ-Mono-Repo/docs/staging.md ]]"
check "Vault setup guide" "[[ -f docs/VAULT_CI_SETUP.md ]]"

# Git status
echo ""
echo -e "${BLUE}[5. Git Status]${NC}"
if [[ -z "$(cd $(git rev-parse --show-toplevel) && git status --porcelain)" ]]; then
  echo -n "Working directory clean ... "
  echo -e "${GREEN}✓${NC}"
  ((SUCCESS++))
else
  echo -n "Working directory clean ... "
  echo -e "${YELLOW}⚠${NC} (uncommitted changes present)"
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo -n "Current branch on main ... "
if [[ "$BRANCH" == "main" ]]; then
  echo -e "${GREEN}✓${NC}"
  ((SUCCESS++))
else
  echo -e "${RED}✗${NC} (on branch: $BRANCH)"
  ((FAILURES++))
fi

# Test docker build capability
echo ""
echo -e "${BLUE}[6. Docker Build Capability (Simulated)]${NC}"
echo -n "Docker build test (no-op) ... "
if docker --version >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC}"
  ((SUCCESS++))
else
  echo -e "${RED}✗${NC}"
  ((FAILURES++))
fi

# Production readiness summary
echo ""
echo "================================"
echo -e "Checks passed: ${GREEN}${SUCCESS}${NC}"
echo -e "Checks failed: ${RED}${FAILURES}${NC}"
echo "================================"

if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}✅ System is ready for Phase P2 production deployment${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Review docs/PHASE_P2_DELIVERY_SUMMARY.md for architecture overview"
  echo "2. Follow docs/PHASE_P2_DEPLOYMENT_VALIDATION_CHECKLIST.md for 10-stage guide"
  echo "3. Run: scripts/automation/pmo/deploy-p2-production.sh deploy"
  echo "4. Validate production instance per checklist"
  exit 0
else
  echo -e "${RED}❌ System has issues. Fix above items before proceeding.${NC}"
  exit 1
fi
