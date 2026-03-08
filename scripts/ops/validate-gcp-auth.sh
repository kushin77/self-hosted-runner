#!/bin/bash
# Script to validate GCP Workload Identity Provider and service account configuration
# Usage: ./validate-gcp-auth.sh [--fix]
# Set: GCP_PROJECT_ID, GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT_EMAIL

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Color-coded output functions
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo "ℹ $1"; }

# Check required environment variables
if [ -z "${GCP_PROJECT_ID:-}" ]; then
  log_fail "GCP_PROJECT_ID not set"
  exit 1
fi

if [ -z "${GCP_SERVICE_ACCOUNT_EMAIL:-}" ]; then
  log_fail "GCP_SERVICE_ACCOUNT_EMAIL not set"
  exit 1
fi

if [ -z "${GCP_WORKLOAD_IDENTITY_PROVIDER:-}" ]; then
  log_fail "GCP_WORKLOAD_IDENTITY_PROVIDER not set"
  exit 1
fi

FIX_MODE="${1:-}"
SUCCESS_COUNT=0
FAIL_COUNT=0

echo "=== GCP Authentication Validation ==="
echo "Project: $GCP_PROJECT_ID"
echo "Service Account: $GCP_SERVICE_ACCOUNT_EMAIL"
echo "WIP: $GCP_WORKLOAD_IDENTITY_PROVIDER"
echo ""

# Test 1: Service account exists
echo "Test 1: Verify service account exists..."
if gcloud iam service-accounts describe "$GCP_SERVICE_ACCOUNT_EMAIL" \
  --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  log_pass "Service account exists"
  ((SUCCESS_COUNT++))
else
  log_fail "Service account not found in project"
  ((FAIL_COUNT++))
fi

# Test 2: iamcredentials API enabled
echo ""
echo "Test 2: Verify iamcredentials.googleapis.com API is enabled..."
if gcloud services list --project="$GCP_PROJECT_ID" --enabled --filter="name:iamcredentials" --format="value(name)" | grep -q iamcredentials.googleapis.com; then
  log_pass "iamcredentials.googleapis.com API is enabled"
  ((SUCCESS_COUNT++))
else
  log_fail "iamcredentials.googleapis.com API is not enabled"
  ((FAIL_COUNT++))
  if [ "$FIX_MODE" = "--fix" ]; then
    log_info "Enabling iamcredentials.googleapis.com..."
    gcloud services enable iamcredentials.googleapis.com --project="$GCP_PROJECT_ID"
    log_pass "iamcredentials.googleapis.com enabled"
  fi
fi

# Test 3: Workload Identity Pool exists
echo ""
echo "Test 3: Verify Workload Identity Pool exists..."
# Extract pool name from provider string
POOL_NAME=$(echo "$GCP_WORKLOAD_IDENTITY_PROVIDER" | grep -oP '(?<=workloadIdentityPools/)[^/]+' || echo "")
PROVIDER_NAME=$(echo "$GCP_WORKLOAD_IDENTITY_PROVIDER" | grep -oP '(?<=providers/)[^/]+$' || echo "")

if [ -n "$POOL_NAME" ] && [ -n "$PROVIDER_NAME" ]; then
  if gcloud iam workload-identity-pools providers list \
    --workload-identity-pool="$POOL_NAME" \
    --location="global" \
    --project="$GCP_PROJECT_ID" \
    --filter="name:$PROVIDER_NAME" \
    --format="value(name)" 2>/dev/null | grep -q "$PROVIDER_NAME"; then
    log_pass "Workload Identity Provider exists"
    ((SUCCESS_COUNT++))
  else
    log_fail "Workload Identity Provider not found"
    ((FAIL_COUNT++))
  fi
else
  log_fail "Invalid provider string format (could not extract pool/provider names)"
  ((FAIL_COUNT++))
fi

# Test 4: Workload Identity Pool attributes (OIDC configuration)
echo ""
echo "Test 4: Verify Workload Identity Pool attributes..."
if gcloud iam workload-identity-pools describe "$POOL_NAME" \
  --location="global" \
  --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  log_pass "Workload Identity Pool accessible"
  ((SUCCESS_COUNT++))
else
  log_fail "Workload Identity Pool not accessible"
  ((FAIL_COUNT++))
fi

# Test 5: Service Account permissions (IAM binding)
echo ""
echo "Test 5: Verify service account token creator role..."
BINDING=$(gcloud iam service-accounts get-iam-policy "$GCP_SERVICE_ACCOUNT_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/iam.serviceAccountTokenCreator" 2>/dev/null || echo "")

if [ -n "$BINDING" ]; then
  log_pass "Service account has tokenCreator role"
  ((SUCCESS_COUNT++))
else
  log_warn "Service account does not have tokenCreator role binding detected"
  if [ "$FIX_MODE" = "--fix" ]; then
    log_info "Adding serviceAccountTokenCreator role to service account..."
    # This is a simplified approach; in production, specify the exact principal
    log_info "Note: Please manually add the GitHub OIDC principal with:"
    echo "gcloud iam service-accounts add-iam-policy-binding $GCP_SERVICE_ACCOUNT_EMAIL \"
    echo "  --role=roles/iam.serviceAccountTokenCreator \"
    echo "  --member='principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/$POOL_NAME/attribute.repository/<ORG>/<REPO>' \"
    echo "  --project=$GCP_PROJECT_ID"
  fi
fi

# Summary
echo ""
echo "=== Validation Summary ==="
echo "Passed: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -eq 0 ]; then
  log_pass "All checks passed! GCP auth should work."
  exit 0
else
  log_fail "Some checks failed. Please review logs above."
  exit 1
fi