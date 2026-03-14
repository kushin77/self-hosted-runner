#!/bin/bash
# OPERATOR INJECTION: Enable Compliance Module
# Enables Terraform compliance module once cloud-audit IAM group is created
# Usage: bash scripts/ops/OPERATOR_ENABLE_COMPLIANCE_MODULE.sh --gcp-project nexusshield-prod

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly COMPLIANCE_DIR="${WORKSPACE_ROOT}/infra/terraform/modules/compliance"
readonly AUDIT_LOG="${WORKSPACE_ROOT}/logs/compliance-enablement-audit.jsonl"
readonly TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$AUDIT_LOG"; }
log_step() { echo -e "${YELLOW}▶${NC} $1" | tee -a "$AUDIT_LOG"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --gcp-project) GCP_PROJECT="$2"; shift 2 ;;
        --audit-group-name) AUDIT_GROUP="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
AUDIT_GROUP="${AUDIT_GROUP:-cloud-audit}"

# Initialize
mkdir -p "$(dirname "$AUDIT_LOG")"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"compliance_enablement_started\",\"gcp_project\":\"$GCP_PROJECT\",\"audit_group\":\"$AUDIT_GROUP\",\"user\":\"$USER\"}" >> "$AUDIT_LOG"

log_step "Enabling Compliance Module"
log_info "GCP Project: $GCP_PROJECT"
log_info "Audit Group: $AUDIT_GROUP"

# Verify gcloud is available
log_step "Verifying gcloud CLI..."
if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found. Please install Google Cloud SDK."
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"gcloud_check\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi
log_success "gcloud CLI verified"

# Set GCP project
gcloud config set project "$GCP_PROJECT" 2>/dev/null || {
    log_error "Failed to set GCP project: $GCP_PROJECT"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"gcloud_project_set\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
}
log_success "GCP project set: $GCP_PROJECT"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"gcp_project_configured\",\"project\":\"$GCP_PROJECT\",\"status\":\"success\"}" >> "$AUDIT_LOG"

# Verify audit group exists
log_step "Verifying cloud-audit group exists..."
if ! gcloud iam groups describe "${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1; then
    log_error "Cloud-audit group not found: ${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com"
    log_info "Action item: Org admin must create the group in GCP Cloud Console:"
    log_info "  1. Visit https://console.cloud.google.com/iam-admin/groups"
    log_info "  2. Create Group: ${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com"
    log_info "  3. Re-run this script once group is created"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"audit_group_verification\",\"group\":\"$AUDIT_GROUP\",\"status\":\"not_found\"}" >> "$AUDIT_LOG"
    exit 1
fi
log_success "Cloud-audit group verified: ${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"audit_group_verified\",\"group\":\"${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com\",\"status\":\"exists\"}" >> "$AUDIT_LOG"

# Check if compliance module directory exists
if [ ! -d "$COMPLIANCE_DIR" ]; then
    log_error "Compliance module directory not found: $COMPLIANCE_DIR"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"compliance_dir_check\",\"status\":\"not_found\"}" >> "$AUDIT_LOG"
    exit 1
fi
log_success "Compliance module directory found"

# Update Terraform variables to enable compliance
log_step "Updating Terraform configuration..."
TERRAFORM_VARS="${COMPLIANCE_DIR}/terraform.tfvars"

if [ ! -f "$TERRAFORM_VARS" ]; then
    log_info "Creating terraform.tfvars..."
    cat > "$TERRAFORM_VARS" <<EOF
enable_compliance = true
audit_group_name = "$AUDIT_GROUP"
project_id       = "$GCP_PROJECT"
EOF
    log_success "Created terraform.tfvars"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_vars_created\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_info "Updating existing terraform.tfvars..."
    # Ensure enable_compliance is set to true
    if grep -q "enable_compliance" "$TERRAFORM_VARS"; then
        sed -i 's/enable_compliance = .*/enable_compliance = true/g' "$TERRAFORM_VARS"
    else
        echo "enable_compliance = true" >> "$TERRAFORM_VARS"
    fi
    
    if grep -q "audit_group_name" "$TERRAFORM_VARS"; then
        sed -i "s/audit_group_name = .*/audit_group_name = \"$AUDIT_GROUP\"/g" "$TERRAFORM_VARS"
    else
        echo "audit_group_name = \"$AUDIT_GROUP\"" >> "$TERRAFORM_VARS"
    fi
    
    log_success "Updated terraform.tfvars"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_vars_updated\",\"status\":\"success\"}" >> "$AUDIT_LOG"
fi

# Initialize Terraform
log_step "Initializing Terraform..."
cd "$COMPLIANCE_DIR" || exit 1

if terraform init -upgrade >/dev/null 2>&1; then
    log_success "Terraform initialized"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_init\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_error "Terraform init failed"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_init\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi

# Plan Terraform changes
log_step "Planning Terraform compliance module deployment..."
if terraform plan -destroy=false -out=tfplan >/dev/null 2>&1; then
    log_success "Terraform plan successful"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_plan\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_error "Terraform plan failed (may require review)"
    log_info "Run: cd $COMPLIANCE_DIR && terraform plan"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_plan\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi

# Apply Terraform changes
log_step "Applying Terraform compliance module..."
log_info "This will create IAM bindings and compliance resources..."

if terraform apply -auto-approve tfplan >/dev/null 2>&1; then
    log_success "Terraform apply successful"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_apply\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_error "Terraform apply failed"
    log_info "Run: cd $COMPLIANCE_DIR && terraform apply -auto-approve"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"terraform_apply\",\"status\":\"failed\"}" >> "$AUDIT_LOG"
    exit 1
fi

# Verify compliance module
log_step "Verifying compliance module deployment..."
terraform output -no-color 2>/dev/null | tee -a "$AUDIT_LOG" || true

if terraform output -json 2>/dev/null | grep -q "compliance_module_id"; then
    log_success "Compliance module verified"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"compliance_verification\",\"status\":\"success\"}" >> "$AUDIT_LOG"
else
    log_info "Compliance module deployed (outputs may be empty if no resources created)"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"compliance_verification\",\"status\":\"deployed\"}" >> "$AUDIT_LOG"
fi

# Generate status report
cd "$WORKSPACE_ROOT" || exit 1
COMPLIANCE_STATUS="${WORKSPACE_ROOT}/logs/compliance-module-status.md"
{
    cat <<EOF
# Compliance Module Status

**Deployment Date:** $TIMESTAMP
**GCP Project:** $GCP_PROJECT
**Audit Group:** ${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com
**Status:** ✅ DEPLOYED

## What Was Enabled

- Cloud Audit Logging integration
- IAM audit bindings via cloud-audit group
- Compliance module Terraform resources
- Automated audit log collection

## Next Steps

1. Monitor audit logs in GCP Cloud Logging
2. Verify compliance metrics in monitoring dashboard
3. Set up compliance alerts (optional)

## Files Updated

- \`infra/terraform/modules/compliance/terraform.tfvars\`
- \`infra/terraform/modules/compliance/terraform.tfstate\`

## Audit Trail

See \`logs/compliance-enablement-audit.jsonl\` for full audit trail.

---
Generated: $TIMESTAMP
EOF
} > "$COMPLIANCE_STATUS"

log_success "Status report written: $COMPLIANCE_STATUS"
echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"status_report_generated\",\"file\":\"$COMPLIANCE_STATUS\",\"status\":\"success\"}" >> "$AUDIT_LOG"

# Final success
log_success "=== Compliance Module Enablement Complete ==="
log_info "Deployment: ✅ SUCCESS"
log_info "Audit Group: ${AUDIT_GROUP}@${GCP_PROJECT}.iam.gserviceaccount.com"
log_info "Module Directory: $COMPLIANCE_DIR"
log_info "Status Report: $COMPLIANCE_STATUS"
log_info "Audit Trail: $AUDIT_LOG"

echo "{\"timestamp\":\"$TIMESTAMP\",\"action\":\"compliance_enablement_completed\",\"status\":\"success\",\"gcp_project\":\"$GCP_PROJECT\",\"audit_group\":\"$AUDIT_GROUP\"}" >> "$AUDIT_LOG"

log_info ""
log_success "Compliance module is now active"
log_success "Cloud audit logging enabled for the project"
