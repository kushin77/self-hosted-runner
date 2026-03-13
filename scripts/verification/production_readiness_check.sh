#!/usr/bin/env bash
set -euo pipefail

################################################################################
# PRODUCTION READINESS VERIFICATION SCRIPT
# Validates that the NexusShield deployment meets all FAANG requirements
# Usage: bash scripts/verification/production_readiness_check.sh [project_id]
################################################################################

PROJECT_ID="${1:-nexusshield-prod}"
ORGANIZATION_ID="266397081400"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}⚠ WARN${NC}: $1"; ((WARN++)); }

echo "================================================================================"
echo "PRODUCTION READINESS VERIFICATION"
echo "Project: $PROJECT_ID"
echo "Organization: $ORGANIZATION_ID"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================================"
echo

# ============================================================================
# SECURITY: Credentials Management
# ============================================================================
echo "=== SECURITY: Credentials Management ==="

# Check Secret Manager enabled
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q secretmanager.googleapis.com; then
  log_pass "Secret Manager API enabled"
else
  log_fail "Secret Manager API NOT enabled"
fi

# Check for hardcoded secrets in repo (pre-commit hook)
if [ -f .pre-commit-config.yaml ]; then
  if grep -q "detect-secrets\|truffleHog" .pre-commit-config.yaml 2>/dev/null; then
    log_pass "Pre-commit secret scanning enabled"
  else
    log_warn "Pre-commit secret scanning not found in .pre-commit-config.yaml"
  fi
else
  log_fail "Pre-commit config not found"
fi

# Count secrets in GSM
SECRET_COUNT=$(gcloud secrets list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
if [ "$SECRET_COUNT" -gt 10 ]; then
  log_pass "Secret Manager populated ($SECRET_COUNT secrets)"
else
  log_warn "Secret Manager has only $SECRET_COUNT secrets (expected >10)"
fi

echo

# ============================================================================
# COMPLIANCE: Audit Logging
# ============================================================================
echo "=== COMPLIANCE: Audit Logging ==="

# Check Cloud Audit Logs configured
if gcloud logging sinks describe cloud-audit-logs --project="$PROJECT_ID" >/dev/null 2>&1; then
  log_pass "Cloud Audit Logs sink configured"
else
  log_warn "Cloud Audit Log sink not found (may use default)"
fi

# Check Cloud Logging API enabled
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q logging.googleapis.com; then
  log_pass "Cloud Logging API enabled"
else
  log_fail "Cloud Logging API NOT enabled"
fi

echo

# ============================================================================
# CI/CD: Cloud Build Pipeline
# ============================================================================
echo "=== CI/CD: Cloud Build Pipeline ==="

# Check Cloud Build API enabled
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q cloudbuild.googleapis.com; then
  log_pass "Cloud Build API enabled"
else
  log_fail "Cloud Build API NOT enabled"
fi

# Check Cloud Build triggers
TRIGGER_COUNT=$(gcloud builds triggers list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
if [ "$TRIGGER_COUNT" -gt 0 ]; then
  log_pass "Cloud Build triggers configured ($TRIGGER_COUNT)"
else
  log_fail "No Cloud Build triggers found"
fi

# Check for GitHub webhook (should NOT have GitHub Actions)
if [ -d .github/workflows ] && [ -n "$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true)" ]; then
  log_fail "GitHub Actions workflows still present in repo"
else
  log_pass "GitHub Actions workflows disabled/archived"
fi

echo

# ============================================================================
# AUTOMATION: Cloud Scheduler
# ============================================================================
echo "=== AUTOMATION: Cloud Scheduler ==="

# Check Cloud Scheduler API enabled
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q cloudscheduler.googleapis.com; then
  log_pass "Cloud Scheduler API enabled"
else
  log_fail "Cloud Scheduler API NOT enabled"
fi

# Check Cloud Scheduler jobs
SCHEDULER_JOBS=$(gcloud scheduler jobs list --location=us-central1 --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
if [ "$SCHEDULER_JOBS" -ge 5 ]; then
  log_pass "Cloud Scheduler jobs configured ($SCHEDULER_JOBS jobs)"
  gcloud scheduler jobs list --location=us-central1 --project="$PROJECT_ID" --format="value(name,schedule)" 2>/dev/null | while read -r name schedule; do
    echo "  - $name: $schedule"
  done
else
  log_fail "Expected >=5 Cloud Scheduler jobs, found $SCHEDULER_JOBS"
fi

echo

# ============================================================================
# INFRASTRUCTURE: Cloud Run Services
# ============================================================================
echo "=== INFRASTRUCTURE: Cloud Run Services ==="

# Check Cloud Run API enabled
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q run.googleapis.com; then
  log_pass "Cloud Run API enabled"
else
  log_fail "Cloud Run API NOT enabled"
fi

# Check Cloud Run services deployed
SERVICES=$(gcloud run services list --platform=managed --region=us-central1 --project="$PROJECT_ID" --format='value(service)' 2>/dev/null | wc -l)
if [ "$SERVICES" -gt 0 ]; then
  log_pass "Cloud Run services deployed ($SERVICES)"
else
  log_fail "No Cloud Run services found"
fi

echo

# ============================================================================
# ENCRYPTION: Cloud KMS
# ============================================================================
echo "=== ENCRYPTION: Cloud KMS ==="

# Check Cloud KMS API enabled
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q cloudkms.googleapis.com; then
  log_pass "Cloud KMS API enabled"
else
  log_fail "Cloud KMS API NOT enabled"
fi

# Check KMS keyrings configured
KEYRINGS=$(gcloud kms keyrings list --location=us --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
if [ "$KEYRINGS" -gt 0 ]; then
  log_pass "KMS keyrings configured ($KEYRINGS)"
else
  log_warn "No KMS keyrings found (may use Secrets Manager only)"
fi

echo

# ============================================================================
# SERVICE ACCOUNTS: IAM Bindings
# ============================================================================
echo "=== SERVICE ACCOUNTS: IAM Bindings ==="

# Check prod-deployer-sa has required roles
PROD_DEPLOYER_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:prod-deployer-sa" --format='value(bindings.role)' 2>/dev/null | wc -l)
if [ "$PROD_DEPLOYER_ROLES" -gt 0 ]; then
  log_pass "prod-deployer-sa IAM bindings configured ($PROD_DEPLOYER_ROLES roles)"
else
  log_fail "prod-deployer-sa has no IAM bindings"
fi

# Check Cloud Build SA can impersonate deployer
CB_SA=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
if gcloud iam service-accounts get-iam-policy "prod-deployer-sa-v3@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" 2>/dev/null | grep -q "roles/iam.serviceAccountTokenCreator\|${CB_SA}@cloudbuild.gserviceaccount.com"; then
  log_pass "Cloud Build SA can impersonate prod-deployer"
else
  log_warn "Cloud Build SA impersonation binding not verified"
fi

echo

# ============================================================================
# VULNERABILITY SCANNING
# ============================================================================
echo "=== VULNERABILITY SCANNING ==="

# Check for Trivy in Cloud Build pipeline
if [ -f cloudbuild-production.yaml ] && grep -q "trivy\|pip-audit\|npm audit" cloudbuild-production.yaml 2>/dev/null; then
  log_pass "Vulnerability scanning configured in Cloud Build"
else
  log_warn "Vulnerability scanning not found in Cloud Build pipeline"
fi

echo

# ============================================================================
# SBOM GENERATION
# ============================================================================
echo "=== SBOM GENERATION ==="

# Check for SBOM in Cloud Build
if [ -f cloudbuild-production.yaml ] && grep -q "syft\|sbom\|SPDX" cloudbuild-production.yaml 2>/dev/null; then
  log_pass "SBOM generation configured"
else
  log_warn "SBOM generation not found in Cloud Build"
fi

echo

# ============================================================================
# IMMUTABILITY & EPHEMERAL PROPERTIES
# ============================================================================
echo "=== IMMUTABILITY & EPHEMERAL PROPERTIES ==="

# Check Terraform infrastructure
if [ -f terraform/org_admin/main.tf ] && [ -f terraform/org_admin/terraform.tfvars ]; then
  log_pass "Infrastructure as Code (Terraform) configured"
else
  log_fail "Terraform infrastructure not found"
fi

# Check Cloud Run revisions are immutable (platform=managed uses revisions)
if gcloud services list --enabled --project="$PROJECT_ID" 2>/dev/null | grep -q run.googleapis.com; then
  log_pass "Cloud Run immutable revisions enabled (platform=managed)"
else
  log_fail "Cloud Run not configured properly"
fi

echo

# ============================================================================
# SUMMARY
# ============================================================================
echo "================================================================================"
echo "SUMMARY"
echo "================================================================================"
echo -e "Passed:    ${GREEN}$PASS${NC}"
echo -e "Failed:    ${RED}$FAIL${NC}"
echo -e "Warnings:  ${YELLOW}$WARN${NC}"
echo

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}✓ PRODUCTION READY${NC}"
  echo "All critical requirements verified. Safe to deploy."
  exit 0
else
  echo -e "${RED}✗ NOT PRODUCTION READY${NC}"
  echo "Please address the $FAIL failure(s) above before deploying to production."
  exit 1
fi
