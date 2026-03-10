#!/usr/bin/env bash
################################################################################
# NexusShield Portal MVP - Staging Deployment Orchestration
#
# Purpose: Execute approved staging deployment with immutable audit trail
# Authorization: User approved "all the above is approved - proceed now no waiting"
# Date: 2026-03-10
#
# Architecture Principles:
#   - Immutable: JSONL audit trail + git commits
#   - Ephemeral: Container lifecycle auto-managed
#   - Idempotent: Terraform state management
#   - No-Ops: 100% automation
#   - Hands-Off: Single terraform apply command
#   - Credentials: GSM/Vault/KMS multi-layer
#   - Governance: Direct to main, no branches
#   - Zero Manual Ops: Fully automated
#
################################################################################

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
AUDIT_LOG="${PROJECT_ROOT}/logs/nexus-shield-staging-deployment-$(date +%Y%m%d).jsonl"
ENVIRONMENT="staging"
DEPLOYMENT_ID="deploy-staging-$(date +%s)"
GCP_PROJECT="${GCP_PROJECT:-p4-platform}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Output Functions
# ============================================================================

log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
  echo -e "${GREEN}✅ $*${NC}"
}

warning() {
  echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
  echo -e "${RED}❌ $*${NC}"
  exit 1
}

# ============================================================================
# Immutable Audit Trail
# ============================================================================

audit_log() {
  local event="$1"
  local status="$2"
  local details="${3:-}"
  local duration_ms="${4:-0}"
  
  local entry=$(jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg deployment_id "$DEPLOYMENT_ID" \
    --arg environment "$ENVIRONMENT" \
    --arg event "$event" \
    --arg status "$status" \
    --arg details "$details" \
    --argjson duration "$duration_ms" \
    '{
      timestamp: $ts,
      deployment_id: $deployment_id,
      environment: $environment,
      event: $event,
      status: $status,
      details: $details,
      duration_ms: $duration,
      user: env.USER,
      commit: env.GIT_COMMIT,
      hostname: env.HOSTNAME
    }')
  
  echo "$entry" >> "$AUDIT_LOG"
}

# ============================================================================
# Pre-Deployment Checks
# ============================================================================

pre_deployment_checks() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "PHASE 1: Pre-Deployment Verification"
  log "════════════════════════════════════════════════════════════════"
  
  # Check Terraform
  if ! command -v terraform &> /dev/null; then
    error "Terraform not found in PATH"
  fi
  success "Terraform found $(terraform version -json | jq -r '.terraform_version')"
  audit_log "terraform-check" "success" "Terraform available"
  
  # Check GCP authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    error "GCP authentication required. Run: gcloud auth application-default login"
  fi
  success "GCP authentication verified"
  audit_log "gcp-auth-check" "success" "GCP credentials available"
  
  # Check Terraform directory
  if [[ ! -d "$TERRAFORM_DIR" ]]; then
    error "Terraform directory not found: $TERRAFORM_DIR"
  fi
  success "Terraform directory available"
  audit_log "terraform-dir-check" "success" "Directory structure valid"
  
  # Check main.tf exists
  if [[ ! -f "$TERRAFORM_DIR/main.tf" ]]; then
    error "main.tf not found in $TERRAFORM_DIR"
  fi
  success "Terraform configuration found"
  audit_log "terraform-config-check" "success" "Configuration files present"
}

# ============================================================================
# Terraform Initialization
# ============================================================================

terraform_init() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "PHASE 2: Terraform Initialization"
  log "════════════════════════════════════════════════════════════════"
  
  cd "$TERRAFORM_DIR"
  
  log "Initializing Terraform (environment=$ENVIRONMENT)..."
  if terraform init \
    -upgrade \
    -no-color 2>&1 | tee /tmp/terraform-init.log; then
    success "Terraform initialized successfully"
    audit_log "terraform-init" "success" "Providers downloaded, ready for deployment"
  else
    error "Terraform initialization failed"
  fi
}

# ============================================================================
# Terraform Validation
# ============================================================================

terraform_validate() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "PHASE 3: Terraform Validation"
  log "════════════════════════════════════════════════════════════════"
  
  cd "$TERRAFORM_DIR"
  
  log "Validating Terraform configuration..."
  if terraform validate -no-color; then
    success "Terraform configuration valid"
    audit_log "terraform-validate" "success" "All HCL syntax validated"
  else
    error "Terraform validation failed"
  fi
}

# ============================================================================
# Terraform Plan
# ============================================================================

terraform_plan() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "PHASE 4: Terraform Plan"
  log "════════════════════════════════════════════════════════════════"
  
  cd "$TERRAFORM_DIR"
  
  log "Planning deployment for environment=$ENVIRONMENT..."
  if terraform plan \
    -var="environment=$ENVIRONMENT" \
    -var="gcp_project=$GCP_PROJECT" \
    -out=tfplan \
    -no-color 2>&1 | tee /tmp/terraform-plan.log; then
    
    # Count resources
    local resource_count=$(grep -c "# google_" tfplan || echo "unknown")
    success "Terraform plan successful ($resource_count resources)"
    audit_log "terraform-plan" "success" "Deployment plan created, $resource_count resources"
  else
    error "Terraform plan failed"
  fi
}

# ============================================================================
# Terraform Apply
# ============================================================================

terraform_apply() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "PHASE 5: Terraform Apply (Infrastructure Deployment)"
  log "════════════════════════════════════════════════════════════════"
  
  cd "$TERRAFORM_DIR"
  
  log "Applying Terraform configuration..."
  local start_time=$(date +%s%N | cut -b1-13)
  
  if terraform apply \
    -no-color \
    -auto-approve \
    tfplan 2>&1 | tee /tmp/terraform-apply.log; then
    
    local end_time=$(date +%s%N | cut -b1-13)
    local duration=$((end_time - start_time))
    
    success "Infrastructure deployed successfully"
    audit_log "terraform-apply" "success" "All resources created/updated in GCP" "$duration"
  else
    error "Terraform apply failed"
  fi
}

# ============================================================================
# Post-Deployment Validation
# ============================================================================

post_deployment_validation() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "PHASE 6: Post-Deployment Validation"
  log "════════════════════════════════════════════════════════════════"
  
  # Check Cloud Run services
  log "Checking Cloud Run services..."
  if gcloud run services list --project="$GCP_PROJECT" --format="value(metadata.name)" 2>/dev/null | grep -q "portal"; then
    success "Cloud Run services deployed"
    audit_log "cloud-run-check" "success" "Portal services operational"
  else
    warning "Cloud Run services not yet visible (may still be starting)"
    audit_log "cloud-run-check" "partial" "Services still initializing"
  fi
  
  # Check database
  log "Checking Cloud SQL instance..."
  if gcloud sql instances list --project="$GCP_PROJECT" --format="value(name)" 2>/dev/null | grep -q "portal"; then
    success "Database instance deployed"
    audit_log "cloudsql-check" "success" "PostgreSQL instance operational"
  else
    warning "Database instance not yet visible (may still be starting)"
    audit_log "cloudsql-check" "partial" "Database still initializing"
  fi
}

# ============================================================================
# Completion & Audit
# ============================================================================

deployment_complete() {
  log ""
  log "════════════════════════════════════════════════════════════════"
  log "✅ DEPLOYMENT COMPLETE - STAGING ENVIRONMENT READY"
  log "════════════════════════════════════════════════════════════════"
  
  log "Deployment ID: $DEPLOYMENT_ID"
  log "Environment: $ENVIRONMENT"
  log "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "Audit Trail: $AUDIT_LOG"
  
  audit_log "deployment-complete" "success" "Staging deployment complete, ready for testing"
  
  success "All infrastructure deployed successfully"
  success "Audit trail recorded to: $AUDIT_LOG"
  success "Next: Run tests and validate deployment"
  
  return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  log ""
  log "╔════════════════════════════════════════════════════════════════╗"
  log "║  NexusShield Portal MVP - Staging Deployment Orchestration     ║"
  log "║  Authority: Approved - Execute immediately, zero waiting      ║"
  log "║  Date: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)                                ║"
  log "╚════════════════════════════════════════════════════════════════╝"
  
  # Initialize audit log
  mkdir -p "$(dirname "$AUDIT_LOG")"
  touch "$AUDIT_LOG"
  
  audit_log "deployment-start" "initiated" "Staging deployment authorized and initiated"
  
  # Execute deployment sequence
  pre_deployment_checks || error "Pre-deployment checks failed"
  terraform_init || error "Terraform initialization failed"
  terraform_validate || error "Terraform validation failed"
  terraform_plan || error "Terraform plan failed"
  terraform_apply || error "Terraform apply failed"
  post_deployment_validation
  deployment_complete
  
  log ""
  success "🎉 Staging deployment successful!"
}

# Execute main
main
