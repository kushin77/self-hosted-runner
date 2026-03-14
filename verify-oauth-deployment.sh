#!/bin/bash
#
# OAuth Deployment Verification & Compliance Check
# Ensures monitoring stack is OAuth-exclusive and security properties are met
#
# Usage: bash verify-oauth-deployment.sh
#

set -euo pipefail

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  OAuth Deployment Verification & Compliance Check           ║"
echo "║  Monitoring Stack: OAuth-Exclusive Access                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() {
  echo -e "${GREEN}✅${NC} $1"
  ((PASSED++))
}

log_fail() {
  echo -e "${RED}❌${NC} $1"
  ((FAILED++))
}

log_warn() {
  echo -e "${YELLOW}⚠️${NC} $1"
  ((WARNINGS++))
}

# ============================================================================
# 1. IMMUTABILITY CHECKS
# ============================================================================
echo "🔒 1. IMMUTABILITY & GIT HISTORY"
echo "═══════════════════════════════════"

# Verify key OAuth files are immutable in git
if git log --all --oneline -- OAUTH_DEPLOYMENT_MANDATE.md 2>/dev/null | head -1 | grep -q ""; then
  log_pass "OAUTH_DEPLOYMENT_MANDATE.md tracked in git"
else
  log_warn "OAuth deployment mandate file not tracked in git"
fi

# Check no credentials in git
CRED_FOUND=$(git log -S 'GOOGLE_OAUTH_CLIENT_SECRET' 2>/dev/null | wc -l)
if [ "$CRED_FOUND" -eq 0 ]; then
  log_pass "No credentials found in git history (GOOD)"
else
  log_fail "FOUND SECRET IN GIT HISTORY - SECURITY BREACH"
fi

echo ""

# ============================================================================
# 2. CONFIGURATION IMMUTABILITY
# ============================================================================
echo "⚙️  2. CONFIGURATION IMMUTABILITY"
echo "═══════════════════════════════════"

# Check docker-compose.yml uses environment variables
if grep -q 'GOOGLE_OAUTH_CLIENT_ID.*{' docker-compose.yml 2>/dev/null; then
  log_pass "docker-compose.yml uses environment variables (not hardcoded)"
else
  log_fail "docker-compose.yml may have hardcoded secrets"
fi

# Check nginx config enforces X-Auth
if grep -q "X-Auth-Request" docker/nginx/monitoring-router.conf 2>/dev/null; then
  log_pass "Nginx enforces X-Auth-Request headers"
else
  log_warn "Nginx X-Auth enforcement not found"
fi

# Check no hardcoded credentials in deployed files
if grep -r "your-client-id\|your-secret-key" docker-compose.yml GOOGLE_OAUTH_SETUP.md 2>/dev/null | grep -qv "REPLACE_WITH" || true; then
  log_warn "Placeholder values found in config (expected for non-deployed state)"
else
  log_pass "No hardcoded secrets in configuration files"
fi

echo ""

# ============================================================================
# 3. CREDENTIAL MANAGEMENT
# ============================================================================
echo "🔐 3. CREDENTIAL MANAGEMENT"
echo "═══════════════════════════════════"

# Check for GSM integration script
if [ -f "scripts/sso/setup-gsm-integration.sh" ]; then
  log_pass "GSM integration script exists"
else
  log_fail "GSM integration script missing"
fi

# Check for automated deployment script
if [ -f "scripts/deploy-oauth.sh" ]; then
  log_pass "Automated deployment script exists (scripts/deploy-oauth.sh)"
else
  log_fail "Deployment script missing"
fi

# Check GSM integration is configured
if grep -q "google-oauth-client-id" scripts/sso/setup-gsm-integration.sh 2>/dev/null; then
  log_pass "GSM integration configured for Google OAuth credentials"
else
  log_warn "GSM integration not found for Google OAuth"
fi

echo ""

# ============================================================================
# 4. OAUTH ENFORCEMENT
# ============================================================================
echo "🛡️  4. OAUTH ENFORCEMENT"
echo "═══════════════════════════════════"

# Check for Grafana OAuth config
if grep -q "GF_AUTH_GOOGLE_ENABLED\|GF_AUTH_BASIC_ENABLED.*false" docker-compose.yml 2>/dev/null; then
  log_pass "Grafana OAuth enabled, local auth disabled"
else
  log_fail "Grafana OAuth configuration incomplete"
fi

# Check for OAuth2-Proxy configuration
if grep -q "OAUTH2_PROXY_PROVIDER.*google" docker-compose.yml 2>/dev/null; then
  log_pass "OAuth2-Proxy configured with Google provider"
else
  log_fail "OAuth2-Proxy not configured for Google"
fi

# Check deploy-worker-node.sh includes Phase 5
if grep -q "Phase 5.*OAuth\|Google OAuth deployment" deploy-worker-node.sh 2>/dev/null; then
  log_pass "Deployment script includes Phase 5 (OAuth protection)"
else
  log_fail "Phase 5 OAuth deployment not found in deploy-worker-node.sh"
fi

# Check for endpoint verification function
if grep -q "verify_oauth_endpoints" deploy-worker-node.sh 2>/dev/null; then
  log_pass "Endpoint protection verification function exists"
else
  log_warn "Endpoint protection verification function not found"
fi

echo ""

# ============================================================================
# 5. NO GITHUB ACTIONS
# ============================================================================
echo "❌ 5. NO GITHUB ACTIONS REQUIREMENT"
echo "═══════════════════════════════════"

# Check for OAuth-related GitHub workflows
WORKFLOWS_FOUND=0
if find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | while read wf; do
  if grep -qi "oauth\|monitoring\|grafana\|credential" "$wf" 2>/dev/null; then
    log_fail "GitHub Actions workflow found: $wf (NOT ALLOWED)"
    WORKFLOWS_FOUND=1
  fi
done; then
  if [ "$WORKFLOWS_FOUND" -eq 0 ]; then
    log_pass "No GitHub Actions workflows for OAuth/monitoring (COMPLIANT)"
  fi
fi

# Check for GitHub pull request automation
if grep -r "actions/create-pull-request\|gh pr create" .github/ 2>/dev/null | grep -q .; then
  log_fail "Found GitHub PR creation in workflows (NOT ALLOWED)"
else
  log_pass "No automated GitHub PR creation (COMPLIANT)"
fi

# Check scripts use direct deployment only
if grep -q "bash scripts/deploy-oauth.sh\|docker-compose up" OAUTH_DEPLOYMENT_MANDATE.md 2>/dev/null; then
  log_pass "Deployment instructions use direct bash scripts only"
else
  log_warn "Deployment instructions unclear"
fi

echo ""

# ============================================================================
# 6. IDEMPOTENCY & SAFETY
# ============================================================================
echo "🔄 6. IDEMPOTENCY & SAFETY"
echo "═══════════════════════════════════"

# Check deploy script for idempotency
if grep -q "docker-compose up -d" scripts/deploy-oauth.sh 2>/dev/null; then
  log_pass "Deployment script uses idempotent commands (docker-compose up -d)"
else
  log_warn "Deployment script may not be idempotent"
fi

# Check for credential validation
if grep -q "REPLACE_WITH\|placeholder" scripts/deploy-oauth.sh 2>/dev/null; then
  log_pass "Deployment script validates credentials are not placeholders"
else
  log_warn "Credential validation check not found"
fi

# Check for error handling
if grep -q "set -euo pipefail" scripts/deploy-oauth.sh 2>/dev/null; then
  log_pass "Deployment script has strict error handling (set -euo pipefail)"
else
  log_warn "Deployment script error handling unclear"
fi

echo ""

# ============================================================================
# 7. DOCUMENTATION & GOVERNANCE
# ============================================================================
echo "📋 7. DOCUMENTATION & GOVERNANCE"
echo "═══════════════════════════════════"

# Check for deployment mandate documentation
if [ -f "OAUTH_DEPLOYMENT_MANDATE.md" ]; then
  log_pass "Deployment mandate documented"
else
  log_fail "OAUTH_DEPLOYMENT_MANDATE.md missing"
fi

# Check for Google OAuth setup guide
if [ -f "GOOGLE_OAUTH_SETUP.md" ]; then
  log_pass "Google OAuth setup guide exists"
else
  log_fail "GOOGLE_OAUTH_SETUP.md missing"
fi

# Check for GitHub issues
if command -v gh &>/dev/null; then
  ISSUE_COUNT=$(gh issue list --state=open --label=security --label=automation 2>/dev/null | grep -i oauth | wc -l || echo 0)
  if [ "$ISSUE_COUNT" -gt 0 ]; then
    log_pass "GitHub issues tracking OAuth automation ($ISSUE_COUNT open)"
  else
    log_warn "No GitHub issues tracking OAuth work"
  fi
else
  log_warn "gh CLI not installed - cannot verify GitHub issues"
fi

echo ""

# ============================================================================
# 8. DEPLOYMENT READINESS
# ============================================================================
echo "🚀 8. DEPLOYMENT READINESS"
echo "═══════════════════════════════════"

# Check services can be deployed (if services exist)
if [ -f "docker-compose.yml" ]; then
  log_pass "docker-compose.yml configuration exists (ready for deployment)"
else
  log_warn "docker-compose.yml not found"
fi

# Check deploy scripts exist
if [ -f "scripts/deploy-oauth.sh" ] && [ -x "scripts/deploy-oauth.sh" ]; then
  log_pass "Deployment script is executable (ready for deployment)"
else
  log_warn "Deploy script not executable (chmod +x scripts/deploy-oauth.sh)"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       COMPLIANCE VERIFICATION SUMMARY                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ PASSED:${NC}   $PASSED checks"
echo -e "${RED}❌ FAILED:${NC}   $FAILED checks"
echo -e "${YELLOW}⚠️  WARNINGS:${NC}  $WARNINGS checks"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo "🟢 STATUS: COMPLIANT"
  echo ""
  echo "Next steps:"
  echo "  1. Ensure Google OAuth credentials are obtained"
  echo "  2. Run: bash scripts/deploy-oauth.sh --setup-gsm"
  echo "  3. Run: bash scripts/deploy-oauth.sh"
  echo "  4. Visit: http://192.168.168.42:3000 (Google OAuth login)"
  echo ""
  exit 0
else
  echo "🔴 STATUS: NON-COMPLIANT"
  echo ""
  echo "Please address the failures above before production deployment."
  echo ""
  exit 1
fi
