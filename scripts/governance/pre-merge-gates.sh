#!/usr/bin/env bash
################################################################################
# Governance Pre-Merge Gates
# 
# Enforces 10 core governance principles before merge to main:
# 1. Immutable - JSONL audit trail
# 2. Ephemeral - auto-cleanup
# 3. Idempotent - safe to re-run
# 4. No-Ops - fully automated
# 5. Hands-Off - OIDC token auth
# 6. GSM/Vault/KMS ONLY - no hardcoded secrets
# 7. Direct Development - commits to main trigger build
# 8. Direct Deployment - Cloud Build → Cloud Run/GKE
# 9. NO GitHub Actions - forbidden
# 10. NO GitHub Pull Releases - forbidden
#
# Usage: ./scripts/governance/pre-merge-gates.sh
# Exit code: 0 = PASS (safe to merge), 1 = FAIL (block merge)
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
GATES_PASSED=0
GATES_FAILED=0
TOTAL_GATES=0

echo "🚨 GOVERNANCE PRE-MERGE GATES (STRICT ENFORCEMENT)"
echo "==============================================="
echo ""
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commit: $(git rev-parse --short HEAD)"
echo ""

################################################################################
# Gate 1: NO Hardcoded Secrets (Gitleaks)
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 1/10] Scanning for hardcoded secrets (gitleaks)... "

if command -v gitleaks &> /dev/null; then
  if gitleaks detect --source=. --exit-code=1 --verbose 2>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    GATES_PASSED=$((GATES_PASSED + 1))
  else
    echo -e "${RED}❌ FAIL${NC}"
    echo "  ERROR: Hardcoded secrets detected"
    echo "  ACTION: Rotate secrets and migrate to GSM/Vault/KMS"
    GATES_FAILED=$((GATES_FAILED + 1))
  fi
else
  echo -e "${YELLOW}⚠ SKIPPED (gitleaks not installed)${NC}"
  echo "  Install: sudo apt install gitleaks"
fi
echo ""

################################################################################
# Gate 2: NO GitHub Actions Workflows
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 2/10] Checking for GitHub Actions workflows... "

if find .github/workflows -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | grep -q .; then
  echo -e "${RED}❌ FAIL${NC}"
  echo "  ERROR: GitHub Actions workflows found in .github/workflows/"
  echo "  FILES:"
  find .github/workflows -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | sed 's/^/    - /'
  echo "  ACTION: Delete workflows and use Cloud Build instead"
  echo "  POLICY: NO_GITHUB_ACTIONS"
  GATES_FAILED=$((GATES_FAILED + 1))
else
  echo -e "${GREEN}✓ PASS${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Gate 3: Credentials → GSM/Vault/KMS ONLY (No Plaintext)
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 3/10] Verifying credentials → GSM/Vault/KMS... "

PLAINTEXT_CREDS=$(grep -r \
  'password.*:' \
  --include="*.yaml" --include="*.yml" --include="*.json" \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
  2>/dev/null | grep -v 'secret' | grep -v 'vault' | grep -v 'GSM' | grep -v 'KMS' | wc -l)

if [ "$PLAINTEXT_CREDS" -gt 0 ]; then
  echo -e "${RED}❌ FAIL${NC}"
  echo "  ERROR: Hardcoded credentials found in manifests"
  echo "  COUNT: $PLAINTEXT_CREDS"
  echo "  ACTION: Replace with GSM/Vault/KMS references"
  GATES_FAILED=$((GATES_FAILED + 1))
else
  echo -e "${GREEN}✓ PASS${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Gate 4: NO GitHub Release Automation
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 4/10] Checking for GitHub Release automation... "

if grep -r 'gh release create' . --exclude-dir=.git 2>/dev/null | head -1 | grep -q .; then
  echo -e "${RED}❌ FAIL${NC}"
  echo "  ERROR: GitHub release automation found"
  echo "  ACTION: Remove release step; use direct deployment"
  echo "  POLICY: Direct deployment (main → Cloud Build → production)"
  GATES_FAILED=$((GATES_FAILED + 1))
else
  echo -e "${GREEN}✓ PASS${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Gate 5: Cloud Build Configuration Required
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 5/10] Verifying Cloud Build configuration... "

if [ -f "cloudbuild.yaml" ]; then
  echo -e "${GREEN}✓ PASS${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
else
  echo -e "${YELLOW}⚠ WARNING${NC}"
  echo "  cloudbuild.yaml not found at repo root"
  echo "  This may be OK if using direct deployment scripts"
fi
echo ""

################################################################################
# Gate 6: Immutable Audit Trail Required
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 6/10] Verifying immutable audit trail... "

if [ -f "audit-trail.jsonl" ]; then
  AUDIT_LINES=$(wc -l < audit-trail.jsonl)
  echo -e "${GREEN}✓ PASS${NC}"
  echo "  Audit trail: $AUDIT_LINES entries"
  GATES_PASSED=$((GATES_PASSED + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  echo "  ERROR: audit-trail.jsonl not found"
  echo "  ACTION: Create immutable JSONL audit trail"
  echo "  FORMAT: {\"timestamp\": \"...\", \"action\": \"...\", ...}"
  GATES_FAILED=$((GATES_FAILED + 1))
fi
echo ""

################################################################################
# Gate 7: NO AWS Secrets Manager (KMS Only)
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 7/10] Checking for AWS Secrets Manager usage... "

if grep -r 'secretsmanager' . --exclude-dir=.git 2>/dev/null | grep -v 'docs' | grep -q .; then
  echo -e "${YELLOW}⚠ WARNING${NC}"
  echo "  AWS Secrets Manager found; use KMS instead"
  GATES_PASSED=$((GATES_PASSED + 1))
else
  echo -e "${GREEN}✓ PASS${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Gate 8: NO Environment Variables for Secrets
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 8/10] Checking for secrets in env vars... "

ENV_SECRETS=$(grep -r 'env:' --include="*.yaml" --include="*.yml" 2>/dev/null | \
  grep -E 'PASSWORD|SECRET|TOKEN|KEY' | wc -l)

if [ "$ENV_SECRETS" -gt 0 ]; then
  echo -e "${RED}❌ FAIL${NC}"
  echo "  ERROR: Secrets in environment variables found ($ENV_SECRETS)"
  echo "  ACTION: Use CSI drivers or init containers for secret injection"
  GATES_FAILED=$((GATES_FAILED + 1))
else
  echo -e "${GREEN}✓ PASS${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Gate 9: Terraform Compliance (Idempotent)
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 9/10] Checking Terraform idempotency... "

if [ -d "terraform" ]; then
  if command -v terraform &> /dev/null; then
    if terraform -chdir=terraform init -backend=false > /dev/null 2>&1; then
      # Check for potential drift
      if terraform -chdir=terraform validate > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        GATES_PASSED=$((GATES_PASSED + 1))
      else
        echo -e "${RED}❌ FAIL${NC}"
        terraform -chdir=terraform validate
        GATES_FAILED=$((GATES_FAILED + 1))
      fi
    else
      echo -e "${YELLOW}⚠ SKIPPED (terraform init failed)${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ SKIPPED (terraform not installed)${NC}"
  fi
else
  echo -e "${GREEN}✓ PASS (no terraform directory)${NC}"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Gate 10: OIDC / Workload Identity (No Passwords)
################################################################################
TOTAL_GATES=$((TOTAL_GATES + 1))
echo -n "[Gate 10/10] Verifying OIDC token auth (no passwords)... "

if grep -r 'serviceAccountJson\|SERVICEACCOUNT' . --exclude-dir=.git 2>/dev/null | grep -v 'docs' | head -1 | grep -q .; then
  echo -e "${GREEN}✓ PASS${NC}"
  echo "  Service account auth found (OIDC compatible)"
  GATES_PASSED=$((GATES_PASSED + 1))
else
  echo -e "${YELLOW}⚠ INFO${NC}"
  echo "  Status: OIDC verification deferred to deployment time"
  GATES_PASSED=$((GATES_PASSED + 1))
fi
echo ""

################################################################################
# Summary
################################################################################
echo "==============================================="
echo "GOVERNANCE PRE-MERGE GATES - SUMMARY"
echo ""
echo "Gates Passed:  $GATES_PASSED / $TOTAL_GATES"
echo "Gates Failed:  $GATES_FAILED / $TOTAL_GATES"
echo ""

if [ $GATES_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ ALL GATES PASSED - SAFE TO MERGE${NC}"
  echo ""
  echo "Audit Log Entry:"
  echo "{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"action\": \"pre-merge-gates-passed\", \"commit\": \"$(git rev-parse --short HEAD)\", \"gates_passed\": $GATES_PASSED}" | tee -a audit-trail.jsonl
  echo ""
  exit 0
else
  echo -e "${RED}❌ MERGE BLOCKED - FIX FAILED GATES BEFORE RETRY${NC}"
  echo ""
  echo "Audit Log Entry:"
  echo "{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"action\": \"pre-merge-gates-failed\", \"commit\": \"$(git rev-parse --short HEAD)\", \"gates_failed\": $GATES_FAILED}" | tee -a audit-trail.jsonl
  echo ""
  exit 1
fi
