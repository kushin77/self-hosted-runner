#!/bin/bash
# Terraform Pre-Apply Checks
# Purpose: Validate environment, credentials, and state before terraform apply
# Usage: ./terraform-preapply-checks.sh [--strict]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TERRAFORM_DIR="${TERRAFORM_DIR:-.}/terraform"
PLAN_FILE="${PLAN_FILE:-${TERRAFORM_DIR}/tfplan}"
STRICT_MODE="${1:-false}"
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; ((CHECKS_PASSED++)); }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; ((CHECKS_WARNED++)); }
log_error() { echo -e "${RED}[✗]${NC} $1"; ((CHECKS_FAILED++)); }

check_terraform_installed() {
  log_info "Checking for terraform installation..."
  if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || terraform version | head -1)
    log_success "Terraform installed: $TF_VERSION"
  else
    log_error "Terraform not found in PATH"
    return 1
  fi
}

check_aws_credentials() {
  log_info "Checking AWS credentials..."
  
  # Check environment variables
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    log_success "AWS credentials configured (environment variables)"
    return 0
  fi
  
  # Check AWS CLI configured
  if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    USER=$(aws sts get-caller-identity --query Arn --output text)
    log_success "AWS credentials valid (Account: $ACCOUNT, User: $USER)"
    return 0
  fi
  
  log_warning "No AWS credentials detected (some resources may require them)"
  return 1
}

check_gcp_credentials() {
  log_info "Checking GCP credentials..."
  
  # Check GOOGLE_APPLICATION_CREDENTIALS
  if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    log_success "GCP credentials file found"
    return 0
  fi
  
  # Check gcloud authentication
  if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    PROJECT=$(gcloud config get-value project 2>/dev/null || echo "unknown")
    log_success "gcloud authenticated (Project: $PROJECT)"
    return 0
  fi
  
  log_warning "GCP credentials not found; GCP resources may fail"
  return 1
}

check_terraform_initialized() {
  log_info "Checking terraform initialization..."
  
  if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
    log_error "Terraform not initialized (run 'terraform init')"
    return 1
  fi
  
  log_success "Terraform workspace initialized"
  return 0
}

check_terraform_state() {
  log_info "Checking terraform state..."
  
  if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    log_warning "No local terraform.tfstate found (may use remote backend)"
  else
    STATE_AGE_DAYS=$(($(date +%s) - $(stat -c%Y "$TERRAFORM_DIR/terraform.tfstate" 2>/dev/null || echo 0)) / 86400))
    if [ $STATE_AGE_DAYS -gt 7 ]; then
      log_warning "State file is $STATE_AGE_DAYS days old"
    else
      log_success "State file is current ($STATE_AGE_DAYS days old)"
    fi
  fi
  
  return 0
}

check_plan_file() {
  log_info "Checking for terraform plan file..."
  
  if [ -f "$PLAN_FILE" ]; then
    PLAN_STAT=$(stat -c%s "$PLAN_FILE" 2>/dev/null || stat -f%z "$PLAN_FILE")
    log_success "Plan file found (size: $PLAN_STAT bytes)"
    
    # Try to extract resource count
    if command -v terraform &> /dev/null; then
      RESOURCE_COUNT=$(terraform show -json "$PLAN_FILE" 2>/dev/null | jq '.resource_changes | length' || echo "unknown")
      log_info "  Resources in plan: $RESOURCE_COUNT"
    fi
    return 0
  fi
  
  log_warning "No plan file found at $PLAN_FILE (run 'terraform plan')"
  return 1
}

check_terraform_fmt() {
  log_info "Checking terraform formatting..."
  
  cd "$TERRAFORM_DIR"
  if terraform fmt -check -recursive . >/dev/null 2>&1; then
    log_success "Terraform code is properly formatted"
  else
    log_warning "terraform fmt would make changes (run 'terraform fmt -recursive .')"
  fi
  cd - > /dev/null
  
  return 0
}

check_terraform_validate() {
  log_info "Validating terraform configuration..."
  
  cd "$TERRAFORM_DIR"
  if terraform validate >/dev/null 2>&1; then
    log_success "Terraform configuration is valid"
  else
    log_error "Terraform validation failed"
    terraform validate
    cd - > /dev/null
    return 1
  fi
  cd - > /dev/null
  
  return 0
}

check_required_variables() {
  log_info "Checking required variables..."
  
  cd "$TERRAFORM_DIR"
  
  # Get list of required variables
  REQUIRED_VARS=$(terraform metadata -json 2>/dev/null | jq -r '.variables[] | select(.required == true) | .name' || true)
  
  if [ -z "$REQUIRED_VARS" ]; then
    log_success "All required variables are satisfied or none defined"
  else
    log_warning "Required variables: $REQUIRED_VARS"
    # Note: This is informational; variables might come from .tfvars or environment
  fi
  
  cd - > /dev/null
  return 0
}

check_git_status() {
  log_info "Checking git repository status..."
  
  if ! command -v git &> /dev/null; then
    log_warning "Git not found; skipping git checks"
    return 0
  fi
  
  cd "$(dirname $TERRAFORM_DIR)"
  
  if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    COMMIT=$(git rev-parse --short HEAD)
    
    if [ -z "$(git status --porcelain)" ]; then
      log_success "Git working directory is clean (Branch: $BRANCH, Commit: $COMMIT)"
    else
      log_warning "Git has uncommitted changes (Branch: $BRANCH, Commit: $COMMIT)"
    fi
  else
    log_warning "Not a git repository"
  fi
  
  cd - > /dev/null
  return 0
}

check_network_connectivity() {
  log_info "Checking network connectivity..."
  
  # Check if we can reach core providers
  local targets=(
    "https://registry.terraform.io"
    "https://api.github.com"
  )
  
  # Add conditional checks based on configured providers
  if grep -q "hashicorp/aws" "$TERRAFORM_DIR"/*.tf 2>/dev/null; then
    targets+=("https://api.aws.amazon.com")
  fi
  
  if grep -q "hashicorp/google" "$TERRAFORM_DIR"/*.tf 2>/dev/null; then
    targets+=("https://www.googleapis.com")
  fi
  
  local connected=true
  for target in "${targets[@]}"; do
    if timeout 5 curl -s -I "$target" > /dev/null 2>&1; then
      log_success "Reachable: $target"
    else
      log_warning "Cannot reach: $target (timeout or unreachable)"
      connected=false
    fi
  done
  
  return 0
}

check_provider_versions() {
  log_info "Checking provider versions..."
  
  cd "$TERRAFORM_DIR"
  
  PROVIDERS=$(terraform providers 2>/dev/null | grep -E "^│|^└" | grep provider || true)
  
  if [ -n "$PROVIDERS" ]; then
    echo "$PROVIDERS" | while read -r line; do
      if echo "$line" | grep -q "registry.terraform.io"; then
        log_info "  $line"
      fi
    done
    log_success "Providers are configured"
  else
    log_warning "No providers found"
  fi
  
  cd - > /dev/null
  return 0
}

# Main execution
main() {
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Terraform Pre-Apply Checks${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  
  # Required checks
  check_terraform_installed || true
  check_terraform_initialized || true
  check_terraform_validate || true
  
  # Credential checks
  check_aws_credentials || true
  check_gcp_credentials || true
  
  # State and plan checks
  check_terraform_state || true
  check_plan_file || true
  
  # Configuration checks
  check_terraform_fmt || true
  check_required_variables || true
  check_provider_versions || true
  
  # Environment checks
  check_git_status || true
  check_network_connectivity || true
  
  # Summary
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Pre-Apply Checks Summary${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}Passed:${NC}  $CHECKS_PASSED"
  if [ $CHECKS_WARNED -gt 0 ]; then
    echo -e "  ${YELLOW}Warned:${NC}  $CHECKS_WARNED"
  fi
  if [ $CHECKS_FAILED -gt 0 ]; then
    echo -e "  ${RED}Failed:${NC}  $CHECKS_FAILED"
  fi
  echo ""
  
  # Exit based on results
  if [ $CHECKS_FAILED -gt 0 ]; then
    if [ "$STRICT_MODE" = "--strict" ]; then
      log_error "Critical checks failed (strict mode enabled)"
      exit 1
    else
      log_warning "Some checks failed but proceeding (non-strict mode)"
      exit 0
    fi
  else
    log_success "All critical pre-apply checks passed"
    exit 0
  fi
}

main "$@"
