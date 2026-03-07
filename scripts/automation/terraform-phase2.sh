#!/usr/bin/env bash
# Terraform Phase 2 Automation Helper
# Provides hands-off CLI interface for Phase 2 operations
# Usage: terraform-phase2.sh <command> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GH_CLI="${GH_CLI:-gh}"
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform}"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
  echo -e "${BLUE}ℹ ${NC}$*"
}

log_success() {
  echo -e "${GREEN}✓ ${NC}$*"
}

log_warning() {
  echo -e "${YELLOW}⚠ ${NC}$*"
}

log_error() {
  echo -e "${RED}✗ ${NC}$*" >&2
}

check_prerequisites() {
  log_info "Checking prerequisites..."
  
  # Check gh CLI
  if ! command -v "$GH_CLI" &> /dev/null; then
    log_error "GitHub CLI not found. Install from: https://cli.github.com"
    exit 1
  fi
  
  # Check git
  if ! command -v git &> /dev/null; then
    log_error "Git not found"
    exit 1
  fi
  
  # Check we're in repo
  if [ ! -d "$REPO_ROOT/.git" ]; then
    log_error "Not in a Git repository"
    exit 1
  fi
  
  log_success "Prerequisites met"
}

get_repo_info() {
  OWNER=$($GH_CLI repo view --json owner -q | jq -r '.owner.login')
  REPO=$($GH_CLI repo view --json name -q | jq -r '.name')
  log_info "Repository: $OWNER/$REPO"
}

# ============================================================================
# Commands
# ============================================================================

cmd_plan() {
  local auto_apply="${1:-false}"
  local varfile_source="${2:-github-secrets}"
  
  log_info "Triggering Terraform Phase 2 Plan..."
  log_info "  Auto-apply: $auto_apply"
  log_info "  Variable source: $varfile_source"
  
  get_repo_info
  
  $GH_CLI workflow run terraform-phase2-final-plan-apply.yml \
    -f auto_apply="$auto_apply" \
    -f varfile_source="$varfile_source" \
    -R "$OWNER/$REPO"
  
  log_success "Workflow triggered"
  log_info "Monitor progress: $GH_CLI run list --workflow=terraform-phase2-final-plan-apply.yml"
}

cmd_apply() {
  log_info "Triggering Terraform Phase 2 Plan+Apply..."
  cmd_plan "true" "${1:-github-secrets}"
}

cmd_drift_check() {
  log_info "Running drift detection..."
  
  get_repo_info
  
  local check_type="${1:-full}"
  
  $GH_CLI workflow run terraform-phase2-drift-detection.yml \
    -f check_type="$check_type" \
    -R "$OWNER/$REPO"
  
  log_success "Drift detection triggered"
}

cmd_validate() {
  log_info "Running post-deployment validation..."
  
  get_repo_info
  
  $GH_CLI workflow run terraform-phase2-post-deploy-validation.yml \
    -R "$OWNER/$REPO"
  
  log_success "Validation workflow triggered"
}

cmd_status() {
  log_info "Checking workflow status..."
  
  get_repo_info
  
  echo ""
  echo "Recent Terraform Phase 2 Plan/Apply runs:"
  $GH_CLI run list --workflow=terraform-phase2-final-plan-apply.yml -L 10 \
    -R "$OWNER/$REPO"
  
  echo ""
  echo "Recent Drift Detection runs:"
  $GH_CLI run list --workflow=terraform-phase2-drift-detection.yml -L 5 \
    -R "$OWNER/$REPO"
}

cmd_artifacts() {
  local workflow="${1:-terraform-phase2-final-plan-apply}"
  local run_id="${2:-latest}"
  
  get_repo_info
  
  log_info "Fetching artifacts from $workflow workflow..."
  
  if [ "$run_id" == "latest" ]; then
    run_id=$($GH_CLI run list --workflow="$workflow.yml" -L 1 -q ".id" -R "$OWNER/$REPO" | head -1)
  fi
  
  log_info "Run ID: $run_id"
  
  mkdir -p artifacts/$workflow-$run_id
  cd artifacts/$workflow-$run_id
  
  $GH_CLI run download $run_id -R "$OWNER/$REPO"
  
  log_success "Artifacts downloaded to: $PWD"
}

cmd_logs() {
  local workflow="${1:-terraform-phase2-final-plan-apply}"
  local job="${2:-}"
  
  get_repo_info
  
  log_info "Fetching logs from $workflow workflow (latest run)..."
  
  local run_id=$($GH_CLI run list --workflow="$workflow.yml" -L 1 -q ".id" -R "$OWNER/$REPO" | head -1)
  
  if [ -z "$job" ]; then
    $GH_CLI run view $run_id --log -R "$OWNER/$REPO" | less
  else
    $GH_CLI run view $run_id --log -R "$OWNER/$REPO" | grep -A 100 "$job" || log_warning "Job not found: $job"
  fi
}

cmd_secrets_status() {
  log_info "Checking required GitHub Secrets..."
  
  get_repo_info
  
  local required_secrets=(
    "TERRAFORM_VPC_ID"
    "TERRAFORM_SUBNET_IDS"
    "TERRAFORM_RUNNER_TOKEN"
    "AWS_REGION"
    "GCP_PROJECT_ID"
    "GCP_SA_KEY"
  )
  
  local missing=()
  
  for secret in "${required_secrets[@]}"; do
    if $GH_CLI secret list -R "$OWNER/$REPO" | grep -q "^$secret"; then
      log_success "$secret"
    else
      log_warning "$secret (not found)"
      missing+=("$secret")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    log_warning "Missing secrets: ${missing[*]}"
    log_info "Configure them at: https://github.com/$OWNER/$REPO/settings/secrets/actions"
    return 1
  else
    log_success "All required secrets configured"
  fi
}

cmd_validate_workflow() {
  log_info "Validating workflow YAML syntax..."
  
  if command -v yamllint &> /dev/null; then
    yamllint "$WORKFLOWS_DIR"/terraform-phase2-*.yml
    log_success "Workflow YAML valid"
  else
    log_warning "yamllint not installed - skipping syntax check"
  fi
}

cmd_local_plan() {
  log_info "Running local Terraform plan (requires credentials and variables)"
  
  if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    log_error "terraform/terraform.tfvars not found"
    log_info "Create it from the template: TERRAFORM_PHASE2_PLAN_APPLY_GUIDE.md"
    exit 1
  fi
  
  cd "$TERRAFORM_DIR"
  
  log_info "Running: terraform init -input=false"
  terraform init -input=false
  
  log_info "Running: terraform validate"
  terraform validate
  
  log_info "Running: terraform plan (dry-run)"
  terraform plan -var-file=terraform.tfvars -out=/tmp/phase2-local.tfplan
  
  log_success "Local plan complete: /tmp/phase2-local.tfplan"
  log_info "Review with: terraform show /tmp/phase2-local.tfplan"
}

cmd_help() {
  cat <<'EOF'
Terraform Phase 2 Automation Helper

USAGE:
  terraform-phase2.sh <command> [options]

COMMANDS:
  plan [false|true] [github-secrets|minio]
      Trigger Terraform plan (default: no auto-apply, github-secrets vars)
      Example: terraform-phase2.sh plan
      Example: terraform-phase2.sh plan false minio

  apply [github-secrets|minio]
      Trigger plan + apply automatically
      Example: terraform-phase2.sh apply

  drift-check [full|plan-only|health-only]
      Run drift detection workflow
      Example: terraform-phase2.sh drift-check full

  validate
      Run post-deployment validation and smoke tests

  status
      Check status of recent runs

  artifacts [workflow] [run-id]
      Download artifacts from workflow run
      Example: terraform-phase2.sh artifacts terraform-phase2-final-plan-apply latest

  logs [workflow] [job]
      View logs from latest workflow run
      Example: terraform-phase2.sh logs terraform-phase2-final-plan-apply terraform-plan

  secrets-status
      Verify all required GitHub Secrets are configured

  validate-workflow
      Validate workflow YAML syntax

  local-plan
      Run terraform plan locally (requires terraform.tfvars)

  help
      Show this help message

EXAMPLES:
  # Dry-run: plan only
  terraform-phase2.sh plan

  # Full deployment: plan + apply
  terraform-phase2.sh apply

  # Check for drift daily
  terraform-phase2.sh drift-check full

  # Verify post-deploy health
  terraform-phase2.sh validate

  # Monitor latest workflow
  terraform-phase2.sh status

  # Download and inspect plan
  terraform-phase2.sh artifacts terraform-phase2-final-plan-apply latest
  terraform show artifacts/terraform-phase2-final-plan-apply-*/terraform-phase2-*.tfplan

PREREQUISITES:
  - GitHub CLI (gh) installed and authenticated
  - Git repository cloned
  - GitHub Secrets configured

For complete documentation, see:
  TERRAFORM_PHASE2_PLAN_APPLY_GUIDE.md

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
  local cmd="${1:-help}"
  shift || true
  
  check_prerequisites
  
  case "$cmd" in
    plan)       cmd_plan "$@" ;;
    apply)      cmd_apply "$@" ;;
    drift-check) cmd_drift_check "$@" ;;
    validate)   cmd_validate "$@" ;;
    status)     cmd_status ;;
    artifacts)  cmd_artifacts "$@" ;;
    logs)       cmd_logs "$@" ;;
    secrets-status) cmd_secrets_status ;;
    validate-workflow) cmd_validate_workflow ;;
    local-plan) cmd_local_plan ;;
    help|-h|--help) cmd_help ;;
    *)
      log_error "Unknown command: $cmd"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
