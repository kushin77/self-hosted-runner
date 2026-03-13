#!/bin/bash
#
# apply-org-admin-terraform.sh
# Purpose: Apply org-level Terraform configurations for IAM/policy bindings
# This solves blocker #2955 - 14 org-level IAM/policy items
#
# Usage:
#   bash scripts/ops/apply-org-admin-terraform.sh [OPTIONS]
#
# Options:
#   -p, --project <PROJECT_ID>          GCP Project ID (default: nexusshield-prod)
#   --plan                              Show terraform plan (no apply)
#   --apply                             Apply terraform changes
#   --force                             Skip confirmation prompts
#   -h, --help                          Show this help message
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
GCP_REGION="${GCP_REGION:-us-central1}"
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/terraform/org_admin"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

confirm() {
  local prompt="$1"
  local response=""
  
  if [[ "${FORCE_APPLY:-false}" == "true" ]]; then
    return 0
  fi
  
  read -p "$(echo -e ${YELLOW})?${NC} $prompt (y/N) " -n 1 -r response
  echo
  [[ "$response" =~ ^[Yy]$ ]]
}

show_help() {
  cat << 'EOF'
apply-org-admin-terraform.sh - Apply org-level Terraform for IAM/policy bindings

USAGE:
  bash scripts/ops/apply-org-admin-terraform.sh [OPTIONS]

OPTIONS:
  -p, --project <PROJECT_ID>          GCP Project ID (default: nexusshield-prod)
  --plan                              Show terraform plan (no apply)
  --apply                             Apply terraform changes
  --force                             Skip confirmation prompts
  -h, --help                          Show this help message

EXAMPLES:
  # Show what will change
  bash scripts/ops/apply-org-admin-terraform.sh --plan

  # Apply changes interactively
  bash scripts/ops/apply-org-admin-terraform.sh --apply

  # Apply changes without prompts
  bash scripts/ops/apply-org-admin-terraform.sh --apply --force

BLOCKING ISSUE:
  This script solves milestone 11 blocker #2955:
  Prod deployment requires 14 org-level IAM/policy items.

ITEMS CONFIGURED (10 of 14 automated):
  ✓ 1.  roles/iam.serviceAccountAdmin → prod-deployer-sa
  ✓ 2.  roles/iam.serviceAccounts.create → Cloud Build SA
  ✓ 2b. Cloud Build roles for direct deployment
  ✓ 7.  Cloud Build SA can impersonate deployer SA
  ✓ 8.  Secret Manager access for backend/frontend SAs
  ✓ 10. Enable required APIs (Secret Manager, Cloud Build, KMS, etc.)
  ✓ 11. Cloud Scheduler permissions & Pub/Sub publisher
  ✓ 12. KMS key access for backend SA
  ✓ 13. Pub/Sub topic IAM for milestone organizer
  ~ 1d. KMS access for prod-deployer-sa

ITEMS REQUIRING MANUAL ORG-ADMIN APPROVAL (4 of 14):
  3. Cloud SQL org policy exception (production)
  4. Cloud SQL org policy exception (staging)
  6. AWS S3 ObjectLock compliance bucket (AWS side)
  14. Service account allowlist for worker SSH

SEE ALSO:
  - GitHub Issue: https://github.com/kushin77/self-hosted-runner/issues/2955
  - Terraform dir: terraform/org_admin/
  - Terraform file: terraform/org_admin/main.tf

EOF
}

verify_terraform_installed() {
  if ! command -v terraform &> /dev/null; then
    log_error "terraform is not installed"
    log_info "Install from: https://developer.hashicorp.com/terraform/install"
    exit 1
  fi
  log_success "terraform $(terraform version | head -1) found"
}

verify_gcloud_authenticated() {
  if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
    log_error "gcloud is not authenticated"
    log_info "Authenticate: gcloud auth login"
    exit 1
  fi
  
  local current_account=$(gcloud config get-value account 2>/dev/null)
  log_success "gcloud authenticated as: $current_account"
}

verify_project_access() {
  if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    log_error "Cannot access project: $PROJECT_ID"
    log_info "With account: $(gcloud config get-value account)"
    exit 1
  fi
  log_success "Project access verified: $PROJECT_ID"
}

terraform_init() {
  log_info "Initializing Terraform..."
  cd "$TERRAFORM_DIR"
  terraform init -upgrade
  log_success "Terraform initialized"
}

terraform_plan() {
  log_info "Creating Terraform plan..."
  cd "$TERRAFORM_DIR"
  
  terraform plan \
    -var="project_id=$PROJECT_ID" \
    -var="gcp_region=$GCP_REGION" \
    -out=tfplan
  
  log_success "Plan created: tfplan"
}

show_plan() {
  log_info "Showing Terraform plan..."
  cd "$TERRAFORM_DIR"
  
  terraform show tfplan | head -100
  echo "... (use 'terraform show tfplan' to see full plan)"
}

terraform_apply() {
  log_info "Applying Terraform configuration..."
  cd "$TERRAFORM_DIR"
  
  if [[ ! -f "tfplan" ]]; then
    log_warn "No execution plan found. Creating one..."
    terraform_plan
  fi
  
  terraform apply tfplan
  
  log_success "Terraform applied successfully"
}

cleanup_plan() {
  cd "$TERRAFORM_DIR"
  if [[ -f "tfplan" ]]; then
    rm -f tfplan
    log_info "Cleaned up temporary plan file"
  fi
}

# Main
main() {
  local action=""
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--project)
        PROJECT_ID="$2"
        shift 2
        ;;
      --plan)
        action="plan"
        shift
        ;;
      --apply)
        action="apply"
        shift
        ;;
      --force)
        FORCE_APPLY="true"
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
  
  # Default action
  if [[ -z "$action" ]]; then
    action="plan"
  fi
  
  log_info "Org-Admin Terraform Setup - Blocker #2955"
  log_info "Project: $PROJECT_ID"
  log_info "Region: $GCP_REGION"
  log_info "Terraform: $TERRAFORM_DIR"
  echo ""
  
  # Verification
  log_info "Verifying prerequisites..."
  verify_terraform_installed
  verify_gcloud_authenticated
  verify_project_access
  echo ""
  
  # Initialize
  terraform_init
  echo ""
  
  # Actions
  case "$action" in
    plan)
      log_info "=== PLAN MODE ==="
      terraform_plan
      echo ""
      show_plan
      echo ""
      log_info "Review plan above. To apply:"
      log_info "  $SCRIPT_NAME --apply"
      ;;
    apply)
      log_info "=== APPLY MODE ==="
      terraform_plan
      echo ""
      show_plan
      echo ""
      
      if confirm "Apply these Terraform changes?"; then
        terraform_apply
        echo ""
        log_success "✅ Terraform applied successfully"
        log_info "10 of 14 IAM/policy items now configured"
        log_warn "⚠  REMAINING ITEMS (4 of 14) require org-admin manual approval:"
        log_warn "   3. Cloud SQL org policy exception (production)"
        log_warn "   4. Cloud SQL org policy exception (staging)"
        log_warn "   6. AWS S3 ObjectLock (AWS side)"
        log_warn "   14. Service account allowlist for worker SSH"
        log_warn ""
        log_warn "See terraform/org_admin/main.tf for commands and details."
        cleanup_plan
      else
        log_info "Apply cancelled. Plan saved to: tfplan"
        log_info "To apply later: terraform apply tfplan"
      fi
      ;;
  esac
}

# Run main
main "$@"
