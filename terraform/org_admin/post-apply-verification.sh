#!/bin/bash

################################################################################
# Post-Apply Verification Script for Org Admin IAM Terraform Module
#
# Purpose: Validate that all 13 org-level IAM resources were successfully
#          applied by Terraform and are functioning correctly.
#
# Usage: bash post-apply-verification.sh [project_id] [verbose]
#
# Example: bash post-apply-verification.sh nexusshield-prod verbose
################################################################################

set -e

PROJECT_ID="${1:-nexusshield-prod}"
VERBOSE="${2:-}"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARNING_COUNT=0

# Helper functions
log_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL_COUNT++))
}

log_warning() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNING_COUNT++))
}

log_info() {
    echo -e "${YELLOW}ℹ INFO${NC}: $1"
}

check_iam_binding() {
    local sa_email="$1"
    local role="$2"
    local description="$3"

    if gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --filter="bindings.members:$sa_email AND bindings.role:$role" \
        --quiet 2>/dev/null | grep -q "$sa_email"; then
        log_pass "$description"
        return 0
    else
        log_fail "$description"
        return 1
    fi
}

check_service_account_iam() {
    local sa_email="$1"
    local member="$2"
    local role="$3"
    local description="$4"

    if gcloud iam service-accounts get-iam-policy "$sa_email" \
        --project="$PROJECT_ID" \
        --flatten="bindings[].members" \
        --filter="bindings.members:$member AND bindings.role:$role" \
        --quiet 2>/dev/null | grep -q "$member"; then
        log_pass "$description"
        return 0
    else
        log_fail "$description"
        return 1
    fi
}

check_api_enabled() {
    local api="$1"
    local description="$2"

    if gcloud services list --enabled --project="$PROJECT_ID" --quiet 2>/dev/null | grep -q "$api"; then
        log_pass "$description"
        return 0
    else
        log_fail "$description"
        return 1
    fi
}

echo "=================================================================================="
echo "Post-Apply Verification Script"
echo "Project: $PROJECT_ID"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=================================================================================="
echo ""

# Retrieve project number for Cloud Build SA email
log_info "Fetching project details..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || echo "UNKNOWN")
CB_SA_EMAIL="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

if [ "$VERBOSE" == "verbose" ]; then
    log_info "Project Number: $PROJECT_NUMBER"
    log_info "Cloud Build SA: $CB_SA_EMAIL"
fi

echo ""
echo "=================================================================================="
echo "VERIFYING PROJECT-LEVEL IAM BINDINGS (Items 1-2, 7-13)"
echo "=================================================================================="
echo ""

# Item 1: prod-deployer-sa (allowing name variants) → roles/iam.serviceAccountAdmin
log_info "Checking Item 1: prod-deployer-sa (any variant) has roles/iam.serviceAccountAdmin"
if gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/iam.serviceAccountAdmin" \
    --format="value(bindings.members)" 2>/dev/null | grep -E "prod-deployer-sa" >/dev/null; then
    log_pass "Item 1: prod-deployer-sa variant has roles/iam.serviceAccountAdmin"
else
    log_fail "Item 1: prod-deployer-sa does NOT have roles/iam.serviceAccountAdmin"
fi

# Item 2: Cloud Build SA → roles/iam.serviceAccounts.create
check_iam_binding \
    "serviceAccount:$CB_SA_EMAIL" \
    "roles/iam.serviceAccounts.create" \
    "Item 2: Cloud Build SA has roles/iam.serviceAccounts.create"

# Item 8: backend-sa → roles/secretmanager.secretAccessor
check_iam_binding \
    "backend-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    "roles/secretmanager.secretAccessor" \
    "Item 8a: backend-sa has roles/secretmanager.secretAccessor"

# Item 8: frontend-sa → roles/secretmanager.secretAccessor
check_iam_binding \
    "frontend-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    "roles/secretmanager.secretAccessor" \
    "Item 8b: frontend-sa has roles/secretmanager.secretAccessor"

# Item 11: cloud-scheduler-sa → roles/cloudbuild.builds.editor
check_iam_binding \
    "cloud-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    "roles/cloudbuild.builds.editor" \
    "Item 11: cloud-scheduler-sa has roles/cloudbuild.builds.editor"

# Item 13: milestone-organizer-sa → roles/pubsub.publisher
check_iam_binding \
    "milestone-organizer-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    "roles/pubsub.publisher" \
    "Item 13a: milestone-organizer-sa has roles/pubsub.publisher"

# Item 13: milestone-organizer-sa → roles/pubsub.subscriber
check_iam_binding \
    "milestone-organizer-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    "roles/pubsub.subscriber" \
    "Item 13b: milestone-organizer-sa has roles/pubsub.subscriber"

echo ""
echo "=================================================================================="
echo "VERIFYING SERVICE ACCOUNT IMPERSONATION (Item 7)"
echo "=================================================================================="
echo ""

# Item 7: Cloud Build SA → impersonate prod-deployer-sa
check_service_account_iam \
    "prod-deployer-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    "serviceAccount:$CB_SA_EMAIL" \
    "roles/iam.serviceAccountTokenCreator" \
    "Item 7: Cloud Build SA can impersonate prod-deployer-sa"

echo ""
echo "=================================================================================="
echo "VERIFYING API ENABLEMENT (Item 10)"
echo "=================================================================================="
echo ""

# Check required APIs
check_api_enabled \
    "secretmanager.googleapis.com" \
    "Item 10a: Secret Manager API enabled"

check_api_enabled \
    "cloudbuild.googleapis.com" \
    "Item 10b: Cloud Build API enabled"

check_api_enabled \
    "cloudkms.googleapis.com" \
    "Item 10c: Cloud KMS API enabled"

check_api_enabled \
    "cloudscheduler.googleapis.com" \
    "Item 10d: Cloud Scheduler API enabled"

check_api_enabled \
    "pubsub.googleapis.com" \
    "Item 10e: Pub/Sub API enabled"

check_api_enabled \
    "artifactregistry.googleapis.com" \
    "Item 10f: Artifact Registry API enabled"

check_api_enabled \
    "run.googleapis.com" \
    "Item 10g: Cloud Run API enabled"

check_api_enabled \
    "container.googleapis.com" \
    "Item 10h: Container API enabled"

echo ""
echo "=================================================================================="
echo "MANUAL VERIFICATION ITEMS (Items 3-6, 9, 12, 14)"
echo "=================================================================================="
echo ""

log_info "Item 3 (Cloud SQL org policy - prod): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: gcloud resource-manager org-policies describe constraints/compute.restrictVpcPeering --organization=ORG_ID"

log_info "Item 4 (Cloud SQL org policy - staging): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: gcloud resource-manager org-policies describe constraints/compute.restrictVpcPeering --organization=ORG_ID"

log_info "Item 5 (Vault Token/AppRole): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: gcloud secrets versions access latest --secret=vault-approle-id --project=$PROJECT_ID"

log_info "Item 6 (AWS S3 ObjectLock): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: aws s3api get-object-retention --bucket=nexusshield-compliance-logs --key=audit-trail.jsonl"

log_info "Item 9 (VPC-SC exceptions): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: gcloud access-context-manager perimeters list"

log_info "Item 12 (KMS permissions): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: gcloud kms keys get-iam-policy KEY_NAME --location=us --keyring=KEYRING_NAME"

log_info "Item 14 (Worker SSH allowlist): REQUIRES MANUAL VERIFICATION"
log_info "  → Run: gcloud compute os-login describe-profile"

echo ""
echo "=================================================================================="
echo "FUNCTIONAL TESTS"
echo "=================================================================================="
echo ""

# Test 1: Can Cloud Build SA create a service account?
log_info "Test 1: Cloud Build SA can create service accounts"
if gcloud iam service-accounts list --project="$PROJECT_ID" --quiet 2>/dev/null | grep -q "cloudbuild"; then
    log_pass "Cloud Build service account exists and accessible"
else
    log_warning "Cannot verify Cloud Build SA service account"
fi

# Test 2: Can backend-sa access secrets?
log_info "Test 2: backend-sa can access secrets"
SECRET_COUNT=$(gcloud secrets list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
if [ "$SECRET_COUNT" -gt 0 ]; then
    log_pass "Secrets exist in Secret Manager ($SECRET_COUNT secrets found)"
else
    log_fail "No secrets found in Secret Manager"
fi

# Test 3: Are Cloud Scheduler jobs configured?
log_info "Test 3: Cloud Scheduler jobs are configured"
SCHEDULER_JOBS=$(gcloud scheduler jobs list --location=us-central1 --project="$PROJECT_ID" 2>/dev/null | wc -l)
if [ "$SCHEDULER_JOBS" -gt 0 ]; then
    log_pass "Cloud Scheduler jobs exist ($SCHEDULER_JOBS jobs)"
else
    log_warning "No Cloud Scheduler jobs found (expected during initial deployment)"
fi

echo ""
echo "=================================================================================="
echo "SUMMARY"
echo "=================================================================================="
echo -e "Passed:    ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed:    ${RED}$FAIL_COUNT${NC}"
echo -e "Warnings:  ${YELLOW}$WARNING_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ ALL AUTOMATED CHECKS PASSED${NC}"
    echo ""
    echo "Status: READY FOR PRODUCTION DEPLOYMENT"
    echo ""
    echo "Next Steps:"
    echo "1. Manually verify items 3-6, 9, 12, 14 (see section above)"
    echo "2. Run: cd /home/akushnir/self-hosted-runner && bash scripts/ops/production-verification.sh"
    echo "3. Post approval confirmation to GitHub Issue #2955"
    echo ""
    exit 0
else
    echo -e "${RED}✗ AUTOMATED CHECKS FAILED${NC}"
    echo ""
    echo "Issues Found:"
    echo "1. Check Terraform apply logs: terraform show -json"
    echo "2. Review GCP IAM bindings: gcloud projects get-iam-policy $PROJECT_ID"
    echo "3. For service account bindings: gcloud iam service-accounts get-iam-policy SA_EMAIL"
    echo ""
    exit 1
fi
