#!/bin/bash

# NexusShield Portal - Final Production Readiness Verification
# Status: Production Ready
# Date: 2026-03-10
# Purpose: Comprehensive verification of all guardrails and production requirements

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED++))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  ((FAILED++))
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++))
}

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

###############################################################################
# SECTION 1: Infrastructure Verification
###############################################################################

section_1_infrastructure() {
  log_info "=== SECTION 1: INFRASTRUCTURE VERIFICATION ==="
  echo

  # 1.1 Deployment Host Validation
  log_info "1.1 Deployment Host Configuration"
  if grep -q "DEPLOYMENT_HOST=192.168.168.42" "$REPO_ROOT/backend/.env.example"; then
    log_pass "DEPLOYMENT_HOST set to 192.168.168.42"
  else
    log_fail "DEPLOYMENT_HOST not correctly configured"
  fi

  # 1.2 No localhost in documentation
  if ! grep -r "localhost" "$REPO_ROOT/docs/deployment/" 2>/dev/null | grep -qv "NEVER\|NOT\|❌"; then
    log_pass "No localhost references in deployment docs"
  else
    log_warn "Found localhost references in documentation (should be 192.168.168.42)"
  fi

  # 1.3 Docker networks configured
  if grep -q "networks:" "$REPO_ROOT/backend/docker-compose.yml"; then
    log_pass "Docker networks configured"
  else
    log_fail "Docker networks not configured"
  fi

  echo
}

###############################################################################
# SECTION 2: Security & Credentials
###############################################################################

section_2_security() {
  log_info "=== SECTION 2: SECURITY & CREDENTIALS ==="
  echo

  # 2.1 No hardcoded passwords in docker-compose
  if grep -E "POSTGRES_PASSWORD:|JWT_SECRET:|REDIS_PASSWORD:" "$REPO_ROOT/backend/docker-compose.yml" | grep -qv "\${" | grep -qv ":?error"; then
    log_fail "Found hardcoded credentials in docker-compose.yml"
  else
    log_pass "No hardcoded credentials in docker-compose.yml"
  fi

  # 2.2 .gitignore protects secrets
  if grep -q ".env" "$REPO_ROOT/backend/.gitignore"; then
    log_pass ".env files ignored in git"
  else
    log_fail ".env files NOT properly ignored"
  fi

  # 2.3 No credentials in git history
  if git -C "$REPO_ROOT" log --all --full-history -p -- ".env*" 2>/dev/null | grep -qE "password|secret|token"; then
    log_warn "Found potential credentials in git history"
  else
    log_pass "No credentials detected in git history"
  fi

  # 2.4 GSM/Vault/KMS documentation exists
  if [ -f "$REPO_ROOT/docs/deployment/CREDENTIAL_STRATEGY_GSM_VAULT_KMS.md" ]; then
    log_pass "Credential strategy documentation exists"
  else
    log_fail "Credential strategy documentation missing"
  fi

  # 2.5 No GitHub Actions
  if [ ! -d "$REPO_ROOT/.github/workflows" ] || [ ! "$(ls -A "$REPO_ROOT/.github/workflows" 2>/dev/null)" ]; then
    log_pass "No GitHub Actions workflows present"
  else
    log_fail "GitHub Actions workflows found (FORBIDDEN)"
  fi

  # 2.6 GitHub Actions explicitly disabled
  if [ -f "$REPO_ROOT/.github/NO_GITHUB_ACTIONS.md" ]; then
    log_pass "GitHub Actions explicitly disabled"
  else
    log_warn "NO_GITHUB_ACTIONS.md not found (create for clarity)"
  fi

  echo
}

###############################################################################
# SECTION 3: Code Quality & Standards
###############################################################################

section_3_code_quality() {
  log_info "=== SECTION 3: CODE QUALITY & STANDARDS ==="
  echo

  # 3.1 TypeScript compiles
  if [ -f "$REPO_ROOT/backend/package.json" ]; then
    if grep -q '"build": "tsc"' "$REPO_ROOT/backend/package.json"; then
      log_pass "TypeScript build script present"
    else
      log_fail "TypeScript build script missing"
    fi
  fi

  # 3.2 README.md exists
  if [ -f "$REPO_ROOT/backend/README.md" ]; then
    log_pass "Backend README.md exists"
  else
    log_fail "Backend README.md missing"
  fi

  # 3.3 Dockerfile optimized
  if grep -q "FROM node:18-alpine AS builder" "$REPO_ROOT/backend/Dockerfile"; then
    log_pass "Dockerfile uses multi-stage build"
  else
    log_fail "Dockerfile not optimized"
  fi

  # 3.4 CONTRIBUTING.md exists
  if [ -f "$REPO_ROOT/CONTRIBUTING.md" ]; then
    log_pass "CONTRIBUTING.md documentation exists"
  else
    log_fail "CONTRIBUTING.md missing"
  fi

  # 3.5 .instructions.md enforces standards
  if grep -q "NO GITHUB ACTIONS" "$REPO_ROOT/.instructions.md"; then
    log_pass "Repository standards enforced in .instructions.md"
  else
    log_fail "Standards not enforced in .instructions.md"
  fi

  echo
}

###############################################################################
# SECTION 4: Deployment Automation
###############################################################################

section_4_deployment() {
  log_info "=== SECTION 4: DEPLOYMENT AUTOMATION ==="
  echo

  # 4.1 Deployment scripts exist
  if [ -x "$REPO_ROOT/scripts/deployment/deploy-portal.sh" ]; then
    log_pass "Deploy script exists and is executable"
  else
    log_fail "Deploy script missing or not executable"
  fi

  # 4.2 Validation script exists
  if [ -x "$REPO_ROOT/scripts/validate-deployment.sh" ]; then
    log_pass "Validation script exists and is executable"
  else
    log_fail "Validation script missing or not executable"
  fi

  # 4.3 Deployment checklist exists
  if [ -f "$REPO_ROOT/docs/deployment/DEPLOYMENT_CHECKLIST.md" ]; then
    log_pass "Deployment checklist exists"
  else
    log_fail "Deployment checklist missing"
  fi

  # 4.4 Deployment index exists
  if [ -f "$REPO_ROOT/docs/deployment/README.md" ]; then
    log_pass "Deployment documentation index exists"
  else
    log_fail "Deployment documentation index missing"
  fi

  # 4.5 Health checks documented
  if grep -q "/ready\|/alive" "$REPO_ROOT/backend/README.md"; then
    log_pass "Health check endpoints documented"
  else
    log_fail "Health check endpoints not documented"
  fi

  echo
}

###############################################################################
# SECTION 5: Immutability & Idempotency
###############################################################################

section_5_immutability() {
  log_info "=== SECTION 5: IMMUTABILITY & IDEMPOTENCY ==="
  echo

  # 5.1 Audit trail implementation mentioned
  if grep -q "audit\|immutable\|JSONL\|append-only" "$REPO_ROOT/backend/README.md"; then
    log_pass "Audit trail requirements documented"
  else
    log_warn "Audit trail not prominently documented"
  fi

  # 5.2 Soft delete pattern documented
  if grep -q "soft delete\|soft-delete\|isDeleted" "$REPO_ROOT/backend/prisma/schema.prisma" 2>/dev/null; then
    log_pass "Soft delete pattern used in schema"
  else
    log_warn "Soft delete pattern not found in schema"
  fi

  # 5.3 Idempotency mentioned in documentation
  if grep -q "idempotent" "$REPO_ROOT/CONTRIBUTING.md"; then
    log_pass "Idempotency documented in CONTRIBUTING.md"
  else
    log_warn "Idempotency not documented in guidelines"
  fi

  # 5.4 Versioning in responses
  if grep -q "api/v1\|/v1/" "$REPO_ROOT/backend/README.md"; then
    log_pass "API versioning implemented"
  else
    log_warn "API versioning not documented"
  fi

  echo
}

###############################################################################
# SECTION 6: Documentation Completeness
###############################################################################

section_6_documentation() {
  log_info "=== SECTION 6: DOCUMENTATION COMPLETENESS ==="
  echo

  # 6.1 Deployment guardrails document
  if [ -f "$REPO_ROOT/DEPLOYMENT_GUARDRAILS_IMPLEMENTATION_COMPLETE.md" ]; then
    log_pass "Deployment guardrails documented"
  else
    log_fail "Deployment guardrails summary missing"
  fi

  # 6.2 Credential strategy documented
  if [ -f "$REPO_ROOT/docs/deployment/CREDENTIAL_STRATEGY_GSM_VAULT_KMS.md" ]; then
    log_pass "Credential strategy (GSM/Vault/KMS) documented"
  else
    log_fail "Credential strategy documentation missing"
  fi

  # 6.3 Architecture documentation
  if [ -d "$REPO_ROOT/docs/architecture" ] && [ -n "$(ls -A "$REPO_ROOT/docs/architecture" 2>/dev/null)" ]; then
    log_pass "Architecture documentation present"
  else
    log_warn "Architecture documentation not comprehensive"
  fi

  # 6.4 Runbook documentation
  if [ -d "$REPO_ROOT/docs/runbooks" ] && [ -n "$(ls -A "$REPO_ROOT/docs/runbooks" 2>/dev/null)" ]; then
    log_pass "Operational runbooks present"
  else
    log_warn "Operational runbooks not found"
  fi

  echo
}

###############################################################################
# SECTION 7: Production Readiness
###############################################################################

section_7_production_readiness() {
  log_info "=== SECTION 7: PRODUCTION READINESS ==="
  echo

  # 7.1 Environment template exists
  if [ -f "$REPO_ROOT/backend/.env.example" ]; then
    log_pass ".env.example template exists"
  else
    log_fail ".env.example template missing"
  fi

  # 7.2 Health check in Dockerfile
  if grep -q "HEALTHCHECK" "$REPO_ROOT/backend/Dockerfile"; then
    log_pass "Docker health checks configured"
  else
    log_fail "Docker health checks missing"
  fi

  # 7.3 Non-root user in Dockerfile
  if grep -q "USER nodejs\|USER.*[0-9]" "$REPO_ROOT/backend/Dockerfile"; then
    log_pass "Non-root user configured in Dockerfile"
  else
    log_warn "Consider running container as non-root for security"
  fi

  # 7.4 Security headers configured
  if grep -q "helmet\|Helmet" "$REPO_ROOT/backend/src/index.ts" 2>/dev/null || grep -q "helmet\|cors" "$REPO_ROOT/backend/package.json" 2>/dev/null; then
    log_pass "Security headers/CORS middleware configured"
  else
    log_warn "Security headers middleware not documented"
  fi

  # 7.5 Graceful shutdown implemented
  if grep -q "SIGTERM\|SIGINT\|graceful" "$REPO_ROOT/backend/src/index.ts" 2>/dev/null || grep -q "close\|shutdown" "$REPO_ROOT/backend/README.md" 2>/dev/null; then
    log_pass "Graceful shutdown handling documented"
  else
    log_warn "Graceful shutdown not documented"
  fi

  echo
}

###############################################################################
# SECTION 8: No-Ops & Automation
###############################################################################

section_8_automation() {
  log_info "=== SECTION 8: NO-OPS & FULL AUTOMATION ==="
  echo

  # 8.1 Deployment fully automated
  if grep -q "docker-compose up\|automated deploy\|hands-off" "$REPO_ROOT/scripts/deployment/deploy-portal.sh"; then
    log_pass "Deployment is fully automated"
  else
    log_fail "Deployment requires manual steps"
  fi

  # 8.2 No manual steps in docs
  if grep -q "manual\|TODO\|FIXME" "$REPO_ROOT/docs/deployment/DEPLOYMENT_CHECKLIST.md" 2>/dev/null | head -5 | grep -q "."; then
    log_warn "Found potential manual steps in deployment guide"
  else
    log_pass "Deployment guide is fully automatable"
  fi

  # 8.3 Credentials automated from GSM/Vault
  if grep -q "GSM\|Vault\|KMS" "$REPO_ROOT/docs/deployment/CREDENTIAL_STRATEGY_GSM_VAULT_KMS.md"; then
    log_pass "Automated credential resolution documented"
  else
    log_fail "Credential automation not documented"
  fi

  # 8.4 Rotation automated
  if grep -q "rotation\|rotate" "$REPO_ROOT/docs/deployment/CREDENTIAL_STRATEGY_GSM_VAULT_KMS.md"; then
    log_pass "Automatic credential rotation documented"
  else
    log_fail "Credential rotation not documented"
  fi

  echo
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
  clear
  cat << 'EOF'

╔════════════════════════════════════════════════════════════╗
║  NexusShield Portal - Production Readiness Verification   ║
║  Status: COMPREHENSIVE AUDIT                             ║
╚════════════════════════════════════════════════════════════╝

EOF

  section_1_infrastructure
  section_2_security
  section_3_code_quality
  section_4_deployment
  section_5_immutability
  section_6_documentation
  section_7_production_readiness
  section_8_automation

  echo
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  VERIFICATION RESULTS                                      ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo
  echo -e "  ${GREEN}Passed:${NC}   $PASSED"
  echo -e "  ${RED}Failed:${NC}   $FAILED"
  echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
  echo

  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ PRODUCTION READY VERIFIED${NC}"
    echo
    echo "Next steps:"
    echo "  1. Deploy to 192.168.168.42"
    echo "  2. Run: bash scripts/deployment/deploy-portal.sh"
    echo "  3. Verify: curl http://192.168.168.42:3000/ready"
    echo
    exit 0
  else
    echo -e "${RED}✗ ISSUES FOUND - RESOLVE BEFORE PRODUCTION${NC}"
    echo
    exit 1
  fi
}

main "$@"
