#!/usr/bin/env bash
##############################################################################
# DRY-RUN: Complete Environment Teardown to Zero
# 
# This script performs a COMPLETE dry-run of environment destruction:
# - Terraform destroy plan (no apply)
# - Resource enumeration
# - Pre-backup artifacts
# - Verification checklist
#
# Status: SAFE - No actual resources destroyed in dry-run mode
# Author: Platform Team
# Date: 2026-03-05
##############################################################################

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
DRY_RUN_MODE="${DRY_RUN_MODE:-true}"
BACKUP_DIR="${BACKUP_DIR:-.}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

##############################################################################
# PRE-FLIGHT CHECKS
##############################################################################
preflight_checks() {
  log_info "Running pre-flight checks..."
  
  # Check 1: Credentials
  if [ -z "$PROJECT_ID" ]; then
    log_error "PROJECT_ID not set"
    exit 1
  fi
  
  # Check 2: Required tools
  for cmd in terraform gcloud docker kubectl redis-cli; do
    if ! command -v "$cmd" &> /dev/null; then
      log_warn "$cmd not found (some checks will be skipped)"
    fi
  done
  
  # Check 3: GCP credentials
  if ! gcloud auth list --filter=status=ACTIVE --format="value(account)" &>/dev/null; then
    log_error "GCP credentials not configured"
    exit 1
  fi
  
  # Check 4: Terraform state accessibility
  if [ ! -f "terraform/environments/$ENVIRONMENT/terraform.tfstate" ]; then
    log_warn "Terraform state not found for $ENVIRONMENT"
  fi
  
  log_success "Pre-flight checks passed"
}

##############################################################################
# PHASE 1: ENVIRONMENT STATE CAPTURE
##############################################################################
capture_environment_state() {
  log_info "Phase 1: Capturing environment state..."
  
  mkdir -p "$BACKUP_DIR/pre-nuke-backup-$(date +%s)"
  BACKUP_ID=$(date +%Y%m%d_%H%M%S)
  
  log_info "Backup ID: $BACKUP_ID"
  
  # Capture 1: GCP compute resources
  log_info "Enumerating GCP compute instances..."
  gcloud compute instances list \
    --project="$PROJECT_ID" \
    --format="table(name,zone,machineType.scope(scope_type:basename),status)" \
    --quiet > "$BACKUP_DIR/gcp-instances-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list instances"
  
  # Capture 2: GCP disks
  log_info "Enumerating GCP persistent disks..."
  gcloud compute disks list \
    --project="$PROJECT_ID" \
    --format="table(name,sizeGb,zone,type.scope(scope_type:basename),status)" \
    --quiet > "$BACKUP_DIR/gcp-disks-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list disks"
  
  # Capture 3: GCP networks
  log_info "Enumerating GCP networks..."
  gcloud compute networks list \
    --project="$PROJECT_ID" \
    --format="table(name,mode,IPv4Range)" \
    --quiet > "$BACKUP_DIR/gcp-networks-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list networks"
  
  # Capture 4: GCP firewall rules
  log_info "Enumerating GCP firewall rules..."
  gcloud compute firewall-rules list \
    --project="$PROJECT_ID" \
    --format="table(name,protocol,ALLOW,DENY,sourceRanges)" \
    --quiet > "$BACKUP_DIR/gcp-firewall-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list firewall rules"
  
  # Capture 5: GCP Redis instances
  log_info "Enumerating GCP Redis instances..."
  gcloud redis instances list \
    --region=us-central1 \
    --project="$PROJECT_ID" \
    --format="table(name,displayName,state,memorySizeGb)" \
    --quiet > "$BACKUP_DIR/gcp-redis-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list Redis instances"
  
  # Capture 6: AWS resources (if configured)
  if command -v aws &>/dev/null && [ -n "${AWS_REGION:-}" ]; then
    log_info "Enumerating AWS EC2 instances..."
    aws ec2 describe-instances \
      --region "${AWS_REGION:-us-east-1}" \
      --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
      --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,LaunchTime]' \
      --output table > "$BACKUP_DIR/aws-instances-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list AWS instances"
  fi
  
  # Capture 7: Systemd services
  log_info "Enumerating systemd services..."
  systemctl --user list-units --state=loaded --all \
    --no-pager --output=table | grep -E "provisioner|managed-auth|vault-shim|portal" \
    > "$BACKUP_DIR/systemd-services-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list systemd services"
  
  # Capture 8: Docker containers
  if command -v docker &>/dev/null; then
    log_info "Enumerating Docker containers..."
    docker ps -a --filter "label=app=self-hosted-runner" \
      --format="table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}" \
      > "$BACKUP_DIR/docker-containers-$BACKUP_ID.txt" 2>/dev/null || log_warn "Could not list Docker containers"
  fi
  
  # Capture 9: Terraform state
  log_info "Backing up Terraform state..."
  if [ -f "terraform/environments/$ENVIRONMENT/terraform.tfstate" ]; then
    cp "terraform/environments/$ENVIRONMENT/terraform.tfstate" \
      "$BACKUP_DIR/terraform-state-$BACKUP_ID.tfstate" 2>/dev/null || log_warn "Could not backup terraform state"
  fi
  
  log_success "Environment state captured to $BACKUP_DIR"
}

##############################################################################
# PHASE 2: TERRAFORM DESTROY PLAN (DRY-RUN)
##############################################################################
terraform_destroy_dryrun() {
  log_info "Phase 2: Terraform destroy plan (dry-run)..."
  
  if [ ! -d "terraform/environments/$ENVIRONMENT" ]; then
    log_error "Terraform directory not found: terraform/environments/$ENVIRONMENT"
    return 1
  fi
  
  cd "terraform/environments/$ENVIRONMENT"
  
  # Initialize terraform
  log_info "Initializing Terraform..."
  terraform init -upgrade > /tmp/tf-init.log 2>&1 || log_warn "Terraform init failed"
  
  # Create destroy plan
  log_info "Creating destroy plan..."
  terraform plan \
    -destroy \
    -var-file=prod.tfvars \
    -out="$BACKUP_DIR/destroy-$BACKUP_ID.tfplan" \
    > "$BACKUP_DIR/destroy-plan-$BACKUP_ID.txt" 2>&1 || log_warn "Terraform plan failed"
  
  # Count resources
  DESTROY_COUNT=$(grep -c "will be destroyed" "$BACKUP_DIR/destroy-plan-$BACKUP_ID.txt" || echo "0")
  
  log_info "Resources to be destroyed: $DESTROY_COUNT"
  
  # Show resource breakdown
  log_info "Resource destruction breakdown:"
  grep "will be destroyed" "$BACKUP_DIR/destroy-plan-$BACKUP_ID.txt" | \
    sed 's/will be destroyed//' | sort | uniq -c || true
  
  cd - > /dev/null
  
  log_success "Terraform destroy plan complete (saved to $BACKUP_DIR/destroy-$BACKUP_ID.tfplan)"
}

##############################################################################
# PHASE 3: RESOURCE ENUMERATION & SUMMARY
##############################################################################
resource_enumeration() {
  log_info "Phase 3: Resource enumeration summary..."
  
  echo ""
  echo "┌─────────────────────────────────────────┐"
  echo "│  ENVIRONMENT STATE PRIOR TO DESTRUCTION  │"
  echo "└─────────────────────────────────────────┘"
  
  if [ -f "$BACKUP_DIR/gcp-instances-$BACKUP_ID.txt" ]; then
    INSTANCE_COUNT=$(tail -n +2 "$BACKUP_DIR/gcp-instances-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    log_info "GCP Compute Instances: $INSTANCE_COUNT"
  fi
  
  if [ -f "$BACKUP_DIR/gcp-disks-$BACKUP_ID.txt" ]; then
    DISK_COUNT=$(tail -n +2 "$BACKUP_DIR/gcp-disks-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    DISK_SIZE=$(tail -n +2 "$BACKUP_DIR/gcp-disks-$BACKUP_ID.txt" 2>/dev/null | awk '{print $2}' | paste -sd+ | bc || echo "0")
    log_info "GCP Persistent Disks: $DISK_COUNT (Total: ${DISK_SIZE}GB)"
  fi
  
  if [ -f "$BACKUP_DIR/gcp-networks-$BACKUP_ID.txt" ]; then
    NETWORK_COUNT=$(tail -n +2 "$BACKUP_DIR/gcp-networks-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    log_info "GCP Networks: $NETWORK_COUNT"
  fi
  
  if [ -f "$BACKUP_DIR/gcp-firewall-$BACKUP_ID.txt" ]; then
    FIREWALL_COUNT=$(tail -n +2 "$BACKUP_DIR/gcp-firewall-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    log_info "GCP Firewall Rules: $FIREWALL_COUNT"
  fi
  
  if [ -f "$BACKUP_DIR/gcp-redis-$BACKUP_ID.txt" ]; then
    REDIS_COUNT=$(tail -n +2 "$BACKUP_DIR/gcp-redis-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    log_info "GCP Redis Instances: $REDIS_COUNT"
  fi
  
  if [ -f "$BACKUP_DIR/docker-containers-$BACKUP_ID.txt" ]; then
    CONTAINER_COUNT=$(tail -n +2 "$BACKUP_DIR/docker-containers-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    log_info "Docker Containers: $CONTAINER_COUNT"
  fi
  
  if [ -f "$BACKUP_DIR/systemd-services-$BACKUP_ID.txt" ]; then
    SERVICE_COUNT=$(tail -n +2 "$BACKUP_DIR/systemd-services-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    log_info "Systemd Services: $SERVICE_COUNT"
  fi
}

##############################################################################
# PHASE 4: VAULT CLEANUP PREVIEW
##############################################################################
vault_cleanup_preview() {
  log_info "Phase 4: Vault cleanup preview..."
  
  if ! command -v vault &>/dev/null; then
    log_warn "Vault CLI not found, skipping vault preview"
    return 0
  fi
  
  # Check vault connectivity
  if vault status &>/dev/null; then
    log_info "Vault status: ACCESSIBLE"
    
    # List AppRole auth method
    log_info "AppRole roles (to be disabled):"
    vault list auth/approle/role/ 2>/dev/null | head -5 || log_warn "Could not list AppRole roles"
    
    # List secrets
    log_info "Secrets (to be archived):"
    vault list secret/data/runners 2>/dev/null | head -5 || log_warn "Could not list secrets"
  else
    log_warn "Vault not accessible"
  fi
}

##############################################################################
# PHASE 5: COST IMPACT ESTIMATE
##############################################################################
cost_impact_estimate() {
  log_info "Phase 5: Cost impact estimate..."
  
  # Rough estimation based on resource counts
  COMPUTE_COST_MONTHLY=0
  STORAGE_COST_MONTHLY=0
  NETWORK_COST_MONTHLY=0
  
  if [ -f "$BACKUP_DIR/gcp-instances-$BACKUP_ID.txt" ]; then
    INSTANCE_COUNT=$(tail -n +2 "$BACKUP_DIR/gcp-instances-$BACKUP_ID.txt" 2>/dev/null | wc -l || echo "0")
    COMPUTE_COST_MONTHLY=$((INSTANCE_COUNT * 25))  # Rough estimate: $25/instance/month
  fi
  
  if [ -f "$BACKUP_DIR/gcp-disks-$BACKUP_ID.txt" ]; then
    DISK_SIZE=$(tail -n +2 "$BACKUP_DIR/gcp-disks-$BACKUP_ID.txt" 2>/dev/null | awk '{print $2}' | paste -sd+ | bc || echo "0")
    STORAGE_COST_MONTHLY=$((DISK_SIZE * 1 / 100))  # Rough estimate: $0.01/GB/month
  fi
  
  TOTAL=$(( COMPUTE_COST_MONTHLY + STORAGE_COST_MONTHLY + NETWORK_COST_MONTHLY ))
  
  log_warn "Estimated monthly cost savings if nuked: \$$TOTAL"
  log_info "  - Compute: \$$COMPUTE_COST_MONTHLY"
  log_info "  - Storage: \$$STORAGE_COST_MONTHLY"
  log_info "  - Network: \$$NETWORK_COST_MONTHLY"
}

##############################################################################
# PHASE 6: VERIFICATION CHECKLIST
##############################################################################
print_verification_checklist() {
  log_info "Phase 6: Verification checklist..."
  
  echo ""
  echo "┌──────────────────────────────────────────────────────┐"
  echo "│  POST-DESTRUCTION VERIFICATION CHECKLIST             │"
  echo "│  (To be performed after actual nuke)                 │"
  echo "└──────────────────────────────────────────────────────┘"
  
  echo "☐ GCP: All compute instances terminated"
  echo "☐ GCP: All persistent disks deleted"
  echo "☐ GCP: Redis cluster destroyed"
  echo "☐ GCP: VPCs and subnets removed"
  echo "☐ GCP: Firewall rules cleaned"
  echo "☐ AWS: All EC2 spot instances terminated"
  echo "☐ AWS: EBS volumes deleted"
  echo "☐ Vault: AppRole disconnected"
  echo "☐ Local: All systemd services stopped and disabled"
  echo "☐ Local: Docker containers stopped"
  echo "☐ Local: Docker images removed"
  echo "☐ DNS: Records updated (if using custom DNS)"
  echo "☐ GitHub: No runners connected to repo"
  echo "☐ Monitoring: Alerts disabled or routed elsewhere"
  echo "☐ Logs: Archived to cold storage"
  echo "☐ Backups: Encrypted backups stored securely"
  echo ""
}

##############################################################################
# PHASE 7: NEXT STEPS
##############################################################################
print_next_steps() {
  log_info "Dry-run complete. Next steps:"
  
  echo ""
  echo "┌──────────────────────────────────────────────────────┐"
  echo "│  NEXT STEPS FOR ACTUAL DESTRUCTION                   │"
  echo "└──────────────────────────────────────────────────────┘"
  
  echo ""
  echo "1. Review all artifacts in: $BACKUP_DIR"
  echo ""
  echo "2. If satisfied, run ACTUAL destruction:"
  echo "   cd terraform/environments/$ENVIRONMENT"
  echo "   terraform apply $BACKUP_DIR/destroy-$BACKUP_ID.tfplan"
  echo ""
  echo "3. Stop local services:"
  echo "   systemctl --user stop provisioner-worker"
  echo "   systemctl --user stop managed-auth"
  echo "   systemctl --user stop vault-shim"
  echo ""
  echo "4. Clean Docker:"
  echo "   docker system prune -a --volumes"
  echo ""
  echo "5. Revoke Vault credentials:"
  echo "   vault auth disable approle"
  echo ""
  echo "6. Archive backups to cold storage:"
  echo "   gsutil -m cp -r $BACKUP_DIR/terraform-state-*.tfstate \\\"
  echo "     gs://archive-vault/pre-nuke-$(date +%Y%m%d)/"
  echo ""
  echo "7. Verify destruction using checklist above"
  echo ""
}

##############################################################################
# MAIN EXECUTION
##############################################################################
main() {
  log_info "════════════════════════════════════════════════════"
  log_info "DRY-RUN: Complete Environment Teardown"
  log_info "Environment: $ENVIRONMENT"
  log_info "Project: $PROJECT_ID"
  log_info "Backup Dir: $BACKUP_DIR"
  log_info "════════════════════════════════════════════════════"
  echo ""
  
  preflight_checks
  echo ""
  
  capture_environment_state
  echo ""
  
  terraform_destroy_dryrun
  echo ""
  
  resource_enumeration
  echo ""
  
  vault_cleanup_preview
  echo ""
  
  cost_impact_estimate
  echo ""
  
  print_verification_checklist
  
  print_next_steps
  
  log_success "Dry-run complete. No resources were destroyed."
}

main "$@"
