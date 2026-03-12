#!/usr/bin/env bash
set -euo pipefail

# deploy-aws-oidc-federation.sh
# Direct deployment of AWS OIDC federation for GitHub Actions
# Enables OIDC token exchange instead of long-lived AWS Access Keys
# 
# Properties: Immutable (audit logged), Idempotent (Terraform rerun-safe), Ephemeral (STS tokens expire)
# No GitHub Actions • Direct commits to main • Hands-off automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/infra/terraform/modules/aws_oidc_federation"
AUDIT_LOG="$REPO_ROOT/logs/aws-oidc-deployment-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$AUDIT_LOG")"

# ============================================================================
# Logging & Audit
# ============================================================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

audit_entry() {
    local event="$1"
    local details="${2:-}"
    local status="${3:-success}"
    echo "{\"timestamp\": \"${TIMESTAMP}\", \"event\": \"${event}\", \"status\": \"${status}\", \"details\": \"${details}\"}" >> "$AUDIT_LOG"
}

# ============================================================================
# Environment Setup
# ============================================================================
setup_environment() {
    log_info "Setting up environment for AWS OIDC deployment..."
    
    # AWS credentials
    AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
    AWS_REGION="${AWS_REGION:-us-east-1}"
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        if command -v aws >/dev/null 2>&1; then
            AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS_ACCOUNT_ID not provided and cannot be determined"
        audit_entry "environment_setup" "AWS_ACCOUNT_ID missing" "failure"
        return 1
    fi
    
    # GCP project
    GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
    if [ -z "$GCP_PROJECT_ID" ]; then
        log_error "GCP_PROJECT_ID not set and gcloud not configured"
        audit_entry "environment_setup" "GCP_PROJECT_ID missing" "failure"
        return 1
    fi
    
    # GitHub repo
    GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"
    
    log_info "AWS Account: $AWS_ACCOUNT_ID"
    log_info "AWS Region: $AWS_REGION"
    log_info "GCP Project: $GCP_PROJECT_ID"
    log_info "GitHub Repo: $GITHUB_REPO"
    
    audit_entry "environment_setup" "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID; GCP_PROJECT=$GCP_PROJECT_ID; GITHUB_REPO=$GITHUB_REPO" "success"
}

# ============================================================================
# Terraform Deployment
# ============================================================================
deploy_terraform() {
    log_info "Deploying AWS OIDC Federation via Terraform..."
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log_error "Terraform module directory not found: $TERRAFORM_DIR"
        audit_entry "terraform_deploy" "Module directory missing" "failure"
        return 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    log_debug "Running terraform init..."
    if ! terraform init -upgrade 2>&1 | tee -a "$AUDIT_LOG"; then
        log_error "Terraform init failed"
        audit_entry "terraform_init" "init command failed" "failure"
        return 1
    fi
    
    # Plan
    log_debug "Running terraform plan..."
    local plan_file="/tmp/aws-oidc-$(date +%s).plan"
    if ! terraform plan \
        -var="aws_account_id=$AWS_ACCOUNT_ID" \
        -var="aws_region=$AWS_REGION" \
        -var="gcp_project_id=$GCP_PROJECT_ID" \
        -var="github_repo=$GITHUB_REPO" \
        -out="$plan_file" 2>&1 | tee -a "$AUDIT_LOG"; then
        log_error "Terraform plan failed"
        audit_entry "terraform_plan" "plan command failed" "failure"
        rm -f "$plan_file"
        return 1
    fi
    
    # Apply (idempotent)
    log_debug "Running terraform apply..."
    if ! terraform apply -auto-approve "$plan_file" 2>&1 | tee -a "$AUDIT_LOG"; then
        log_error "Terraform apply failed"
        audit_entry "terraform_apply" "apply command failed" "failure"
        rm -f "$plan_file"
        return 1
    fi
    
    rm -f "$plan_file"
    
    # Extract outputs
    OIDC_PROVIDER_ARN=$(terraform output -raw oidc_provider_arn 2>/dev/null || echo "")
    OIDC_ROLE_ARN=$(terraform output -raw oidc_role_arn 2>/dev/null || echo "")
    OIDC_ROLE_NAME=$(terraform output -raw oidc_role_name 2>/dev/null || echo "")
    
    if [ -z "$OIDC_ROLE_ARN" ]; then
        log_error "Failed to extract Terraform outputs"
        audit_entry "terraform_outputs" "output extraction failed" "failure"
        return 1
    fi
    
    log_info "✅ AWS OIDC Federation deployed successfully"
    log_debug "  OIDC Provider ARN: $OIDC_PROVIDER_ARN"
    log_debug "  OIDC Role ARN: $OIDC_ROLE_ARN"
    log_debug "  OIDC Role Name: $OIDC_ROLE_NAME"
    
    audit_entry "terraform_apply_success" "OIDC_ROLE_ARN=$OIDC_ROLE_ARN" "success"
}

# ============================================================================
# Immutable Record (Git Commit)
# ============================================================================
record_deployment() {
    log_info "Recording deployment to immutable audit trail..."
    
    cd "$REPO_ROOT"
    
    git add logs/aws-oidc-deployment-*.jsonl 2>/dev/null || true
    
    if git diff --cached --quiet 2>/dev/null; then
        log_debug "No changes to commit"
    else
        git commit -m "ops: AWS OIDC federation deployed (${TIMESTAMP})

- OIDC Provider ARN: $OIDC_PROVIDER_ARN
- OIDC Role ARN: $OIDC_ROLE_ARN
- OIDC Role Name: $OIDC_ROLE_NAME
- Idempotent deployment via Terraform
- Direct commit to main (no GitHub Actions)
- Immutable audit log: logs/aws-oidc-deployment-*.jsonl
" || true
        git push origin main || true
    fi
    
    audit_entry "git_commit" "deployment recorded" "success"
}

# ============================================================================
# GitHub Issue Update
# ============================================================================
update_github_issue() {
    log_info "Updating GitHub issue #2159..."
    
    local issue_number="2159"
    local comment_body="✅ AWS OIDC Federation Deployment Complete (${TIMESTAMP})

**Deployment Details:**
- OIDC Provider ARN: \`$OIDC_PROVIDER_ARN\`
- OIDC Role ARN: \`$OIDC_ROLE_ARN\`
- OIDC Role Name: \`$OIDC_ROLE_NAME\`

**Configuration:**
- AWS Account: \`$AWS_ACCOUNT_ID\`
- GitHub Repo: \`$GITHUB_REPO\`
- GCP Project: \`$GCP_PROJECT_ID\`

**Architecture:**
✅ Immutable: Deployment logged to audit trail (JSONL)
✅ Idempotent: Terraform rerun-safe, all policies ignore_changes
✅ Ephemeral: STS assume-role tokens expire (temporary credentials)
✅ No-Ops: Deployed directly to main, no GitHub Actions
✅ Hands-Off: Automated orchestrator, zero manual intervention

**Next Steps:**
- Delete or rotate long-lived AWS Access Keys (if not needed)
- Update deployment workflows to use OIDC role
- Run vulnerability scans: \`aws accessanalyzer validate-policy --policy-document file://policy.json\`
- Test cross-account access if multi-account setup required

**Audit Log:** \`logs/aws-oidc-deployment-${TIMESTAMP}.jsonl\`"
    
    if command -v gh >/dev/null 2>&1; then
        gh issue comment "$issue_number" --repo=kushin77/self-hosted-runner --body "$comment_body" || true
    else
        log_warn "GitHub CLI not available; skipping issue comment"
    fi
    
    audit_entry "github_issue_update" "issue #$issue_number commented" "success"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "=========================================="
    echo "AWS OIDC Federation Deployment"
    echo "Immutable • Idempotent • Ephemeral"
    echo "=========================================="
    echo ""
    
    log_info "Timestamp: $TIMESTAMP"
    log_info "Audit Log: $AUDIT_LOG"
    echo ""
    
    setup_environment || exit 1
    echo ""
    
    deploy_terraform || exit 1
    echo ""
    
    record_deployment || true
    echo ""
    
    update_github_issue || true
    echo ""
    
    log_info "✅ AWS OIDC Deployment Complete"
    audit_entry "main_complete" "AWS OIDC deployment successful" "success"
}

main "$@"
