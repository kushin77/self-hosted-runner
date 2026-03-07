#!/usr/bin/env bash
#
# Automated ElastiCache Redis Provisioning Helper
# Prepares and executes `terraform apply` for ElastiCache with safety checks
#
# Usage: ./provision-elasticache-redis.sh [--dry-run] [--auto-approve]

set -euo pipefail

DRY_RUN=${1:-}
AUTO_APPROVE=${2:-}
TERRAFORM_DIR="terraform"
TFVARS_FILE="${TERRAFORM_DIR}/terraform.tfvars"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v terraform >/dev/null 2>&1; then
  log_error "terraform not found in PATH"
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  log_warn "AWS CLI not found; assuming IAM credentials are available via environment"
fi

if ! command -v jq >/dev/null 2>&1; then
  log_warn "jq not found; some validation will be skipped"
fi

log_success "Prerequisites met"

# Check if terraform.tfvars exists
if [ ! -f "$TFVARS_FILE" ]; then
  log_error "terraform.tfvars not found at $TFVARS_FILE"
  log_info "Please copy from terraform.tfvars.elasticache and populate required values:"
  log_info "  cp terraform/terraform.tfvars.elasticache terraform/terraform.tfvars"
  log_info "  # Edit terraform.tfvars with your VPC/subnet IDs"
  exit 1
fi

log_success "terraform.tfvars found"

# Validate terraform.tfvars
log_info "Validating terraform.tfvars..."

# Check for empty required variables
VPC_ID=$(grep -E '^\s*vpc_id\s*=' "$TFVARS_FILE" | grep -oE '"[^"]*"' | tr -d '"' | head -1)
SUBNET_IDS=$(grep -E '^\s*subnet_ids\s*=' "$TFVARS_FILE" -A5 | grep -E '^\s*#' | wc -l)

if [ -z "$VPC_ID" ]; then
  log_error "vpc_id is empty or not set"
  log_info "Edit $TFVARS_FILE and set vpc_id to your VPC ID"
  exit 1
fi

log_success "vpc_id is set: $VPC_ID"

# Validate AWS credentials
log_info "Validating AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  log_error "Invalid AWS credentials or not authenticated"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_success "AWS account authenticated: $ACCOUNT_ID"

# Change to terraform directory
cd "$TERRAFORM_DIR" || {
  log_error "Cannot change to $TERRAFORM_DIR directory"
  exit 1
}

# Initialize Terraform
log_info "Initializing Terraform..."
if ! terraform init; then
  log_error "terraform init failed"
  exit 1
fi

log_success "Terraform initialized"

# Validate Terraform configuration
log_info "Validating Terraform configuration..."
if ! terraform validate; then
  log_error "terraform validate failed"
  exit 1
fi

log_success "Terraform configuration valid"

# Plan Terraform
log_info "Planning Terraform application..."
PLAN_FILE="tfplan-elasticache-$(date +%s).out"

if ! terraform plan -var-file=../terraform.tfvars.elasticache -out="$PLAN_FILE"; then
  log_error "terraform plan failed"
  exit 1
fi

log_success "Terraform plan created: $PLAN_FILE"

# Show plan
log_info "Terraform Plan Summary:"
log_info "════════════════════════════════════════════════"
terraform show "$PLAN_FILE" | head -50

# Dry-run mode
if [ "$DRY_RUN" = "--dry-run" ]; then
  log_info "DRY-RUN MODE: Plan complete. Review above and run without --dry-run to apply."
  log_info "terraform apply $PLAN_FILE"
  exit 0
fi

# Prompt for approval if not auto-approved
if [ "$AUTO_APPROVE" != "--auto-approve" ]; then
  log_warn "About to apply Terraform changes. This will:"
  log_warn "  - Create VPC security group"
  log_warn "  - Create KMS encryption key"
  log_warn "  - Create ElastiCache replication group"
  log_warn "  - Provision $num_cache_nodes Redis nodes"
  read -p "Do you understand and approve? (yes/no): " approval
  
  if [ "$approval" != "yes" ]; then
    log_warn "Aborted by user"
    rm -f "$PLAN_FILE"
    exit 0
  fi
fi

# Apply Terraform
log_info "Applying Terraform plan..."
if ! terraform apply "$PLAN_FILE"; then
  log_error "terraform apply failed"
  exit 1
fi

log_success "Terraform apply completed"

# Extract outputs
log_info "Extracting outputs..."
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint 2>/dev/null || echo "unknown")
REDIS_PORT=$(terraform output -raw redis_port 2>/dev/null || echo "6379")
REDIS_URL=$(terraform output -raw redis_url 2>/dev/null || echo "")
REDIS_AUTH=$(terraform output -raw redis_auth_token 2>/dev/null || echo "")

log_success "ElastiCache provisioning complete!"

cat << SUMMARY
════════════════════════════════════════════════════════════════════
🎉 ElastiCache Redis Production Deployment Complete
════════════════════════════════════════════════════════════════════

ENDPOINT:  $REDIS_ENDPOINT
PORT:      $REDIS_PORT
URL:       $REDIS_URL
AUTH TOKEN: [redacted - see below]

⚠️  IMPORTANT: Save the AUTH Token to GitHub Secrets:

1. Copy the AUTH token:
   terraform output -raw redis_auth_token

2. In GitHub repo → Settings → Secrets and Variables → Actions:
   Name:  PROVISIONER_REDIS_AUTH_TOKEN
   Value: [paste token from step 1]

3. Also add the Redis URL:
   Name:  PROVISIONER_REDIS_URL
   Value: redis://<endpoint>:6379

4. Test connection from provisioner-worker:
   redis-cli -h $REDIS_ENDPOINT -a <AUTH_TOKEN> ping

5. Verify cluster health:
   redis-cli -h $REDIS_ENDPOINT -a <AUTH_TOKEN> cluster info

════════════════════════════════════════════════════════════════════
NEXT STEPS:
1. Add credentials to GitHub Secrets (steps 2-3 above)
2. Update Issue #172 with deployment summary
3. Close Issue #172 once validated
4. Proceed with provisioner-worker deployment (Issue #147)
════════════════════════════════════════════════════════════════════
SUMMARY

# Save outputs to file for CI/CD pipelines
cat > elasticache-outputs.json << JSON
{
  "endpoint": "$REDIS_ENDPOINT",
  "port": $REDIS_PORT,
  "url": "$REDIS_URL",
  "auth_token": "$REDIS_AUTH",
  "cluster_name": "provisioner-redis-prod",
  "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

log_success "Outputs saved to elasticache-outputs.json"
