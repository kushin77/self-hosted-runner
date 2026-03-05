#!/bin/bash
# Phase P4 AWS Spot Runner - Ops Setup & Plan Script
# This script prepares the environment and runs terraform plan for AWS spot runner deployment
# Pre-requisites: AWS credentials (via env vars or IAM role), terraform installed

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform/examples/aws-spot"

# Color output helper
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  command -v terraform >/dev/null 2>&1 || {
    log_error "terraform is not installed"
    exit 1
  }
  
  if [[ -z "${AWS_REGION:-}" ]]; then
    log_warn "AWS_REGION not set; defaulting to us-east-1"
    export AWS_REGION="us-east-1"
  fi
  
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured or invalid"
    exit 1
  fi
  
  log_info "AWS credentials OK (caller: $(aws sts get-caller-identity --query Arn --output text))"
  log_info "Prerequisites OK"
}

# Prepare terraform inputs
prepare_inputs() {
  log_info "Preparing terraform inputs..."
  
  cd "${TERRAFORM_DIR}"
  
  # Check if terraform.tfvars exists
  if [[ -f "terraform.tfvars" ]]; then
    log_info "Using existing terraform.tfvars"
  else
    log_warn "terraform.tfvars not found; creating from terraform.tfvars.example"
    cp terraform.tfvars.example terraform.tfvars
    log_warn "Please edit terraform.tfvars with your VPC and subnet details"
    log_warn "At minimum, set:"
    log_warn "  - vpc_id"
    log_warn "  - subnet_ids"
    log_warn "  - key_name (for SSH access)"
    read -p "Press enter once terraform.tfvars is configured..."
  fi
  
  # Validate tfvars contains required variables
  if ! grep -q "vpc_id" terraform.tfvars; then
    log_error "terraform.tfvars missing vpc_id"
    exit 1
  fi
  if ! grep -q "subnet_ids" terraform.tfvars; then
    log_error "terraform.tfvars missing subnet_ids"
    exit 1
  fi
  
  log_info "Terraform inputs OK"
}

# Initialize and validate
init_and_validate() {
  log_info "Initializing terraform..."
  
  cd "${TERRAFORM_DIR}"
  
  # Clean prior state to avoid version conflicts
  rm -rf .terraform .terraform.lock.hcl
  
  terraform init
  
  log_info "Validating terraform configuration..."
  terraform validate
  
  log_info "Formatting check..."
  terraform fmt -check . || {
    log_warn "Terraform files not properly formatted; applying fmt..."
    terraform fmt .
  }
  
  log_info "Init and validation OK"
}

# Run terraform plan
run_plan() {
  log_info "Running terraform plan..."
  
  cd "${TERRAFORM_DIR}"
  
  terraform plan -out=aws-spot.plan
  
  log_info "Plan completed; artifacts available:"
  log_info "  - Binary plan: aws-spot.plan"
  ls -lh aws-spot.plan
  
  log_info "Generating human-readable plan summary..."
  terraform show -no-color aws-spot.plan > aws-spot.plan.txt
  
  log_info "Plan summary saved to aws-spot.plan.txt"
  head -50 aws-spot.plan.txt
  
  log_info "Plan OK"
}

# Generate approval summary
approval_summary() {
  log_info "=== PLAN APPROVAL SUMMARY ==="
  log_info "Review the plan artifacts and approve the changes:"
  log_info ""
  log_info "Plan artifacts in: ${TERRAFORM_DIR}/"
  log_info "  - aws-spot.plan (binary)"
  log_info "  - aws-spot.plan.txt (human-readable)"
  log_info ""
  log_info "To apply the plan:"
  log_info "  1. Review aws-spot.plan.txt"
  log_info "  2. Ensure prod-terraform-apply environment is protected in GitHub"
  log_info "  3. Run: cd ${TERRAFORM_DIR} && terraform apply aws-spot.plan"
  log_info "  4. Or use GitHub Actions: p4-aws-spot-apply.yml workflow"
  log_info ""
  log_info "To verify after apply:"
  log_info "  - ASG should be created in VPC"
  log_info "  - Lambda function should be deployed (if enable_lifecycle_handler=true)"
  log_info "  - SNS/SQS lifecycle notification plumbing should be wired"
  log_info "=== END SUMMARY ==="
}

# Main execution
main() {
  log_info "Phase P4 AWS Spot Runner - Ops Setup & Plan"
  log_info "Repository: ${REPO_ROOT}"
  log_info "Terraform directory: ${TERRAFORM_DIR}"
  log_info ""
  
  check_prerequisites
  prepare_inputs
  init_and_validate
  run_plan
  approval_summary
  
  log_info "Setup and plan completed successfully"
  exit 0
}

main "$@"
