#!/usr/bin/env bash
set -euo pipefail

# Pre-deployment health check for GitLab Runner hands-off migration
# Verifies repository structure, CI config, scripts, and documentation
# Usage: ./scripts/ci/pre_deploy_health_check.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ERRORS=0
WARNINGS=0

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
  ((WARNINGS++))
}

log_error() {
  echo -e "${RED}✗${NC} $*"
  ((ERRORS++))
}

log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

section() {
  echo ""
  echo -e "${BLUE}=== $* ===${NC}"
}

# Verify repository structure
section "Repository Structure"

check_file() {
  local file=$1
  local description=$2
  if [ -f "$REPO_ROOT/$file" ]; then
    log_ok "$description: $file"
  else
    log_error "$description not found: $file"
  fi
}

check_dir() {
  local dir=$1
  local description=$2
  if [ -d "$REPO_ROOT/$dir" ]; then
    log_ok "$description: $dir"
  else
    log_error "$description not found: $dir"
  fi
}

# Core files
check_file ".gitlab-ci.yml" "Main CI config"
check_file ".gitlab/ci-includes/runner-deploy.gitlab-ci.yml" "Runner deploy CI include"
check_dir "scripts/ci" "Scripts directory"
check_dir "infra/gitlab-runner" "Helm infra directory"
check_dir "issues" "Issues directory"

# Deployment guides
check_file "HANDS_OFF_DEPLOYMENT_GUIDE.md" "Deployment guide"
check_file "DEPLOYMENT_FINAL_STATUS.md" "Final status document"
check_file "infra/gitlab-runner/README.md" "Helm README"

section "Required Scripts"

check_script() {
  local script=$1
  local description=$2
  if [ -f "$REPO_ROOT/$script" ] && [ -x "$REPO_ROOT/$script" ]; then
    log_ok "$description: $script"
  elif [ -f "$REPO_ROOT/$script" ]; then
    log_warn "$description exists but not executable: $script"
  else
    log_error "$description not found: $script"
  fi
}

check_script "scripts/ci/hands_off_orchestrate.sh" "Master orchestration script"
check_script "scripts/ci/gcp_fetch_secrets.sh" "GCP Secret Manager helper"
check_script "scripts/ci/create_sealedsecret_from_token.sh" "SealedSecret generator"
check_script "scripts/ci/hands_off_runner_deploy.sh" "Helm deploy script"
check_script "scripts/ci/validate_runner_readiness.sh" "Readiness validator"
check_script "scripts/ci/trigger_yamltest_pipeline.sh" "Pipeline trigger script"

section "Deployment Issues & Checklists"

check_file "issues/100-runner-migration-plan.md" "Issue #100: Migration plan"
check_file "issues/101-deploy-via-ci.md" "Issue #101: CI deploy"
check_file "issues/102-gsm-secrets-setup.md" "Issue #102: GSM setup"
check_file "issues/103-trigger-ci-deploy.md" "Issue #103: Trigger deploy"
check_file "issues/104-post-deploy-validation.md" "Issue #104: Validation"
check_file "issues/105-runner-migration-decommission.md" "Issue #105: Migration"

section "Helm Configuration"

check_file "infra/gitlab-runner/values.yaml.template" "Helm values template"
check_file "infra/gitlab-runner/sealedsecret.example.yaml" "SealedSecret example"
if [ -f "$REPO_ROOT/infra/gitlab-runner/deploy_runbook.md" ]; then
  log_ok "Helm runbook: infra/gitlab-runner/deploy_runbook.md"
else
  log_warn "Helm runbook not found (optional): infra/gitlab-runner/deploy_runbook.md"
fi

section "CI Validation"

log_info "Checking .gitlab-ci.yml syntax..."
if head -1 "$REPO_ROOT/.gitlab-ci.yml" | grep -q "^#" || grep -q "^stages:" "$REPO_ROOT/.gitlab-ci.yml"; then
  log_ok ".gitlab-ci.yml exists and has expected format"
else
  log_warn ".gitlab-ci.yml might have syntax issues"
fi

log_info "Checking for runner-deploy include..."
if grep -q "runner-deploy.gitlab-ci.yml" "$REPO_ROOT/.gitlab-ci.yml"; then
  log_ok "Runner deploy include referenced in main CI config"
else
  log_error "Runner deploy include NOT referenced in .gitlab-ci.yml"
fi

log_info "Checking for YAMLtest-sovereign-runner job..."
if grep -q "YAMLtest-sovereign-runner" "$REPO_ROOT/.gitlab-ci.yml"; then
  log_ok "Pre-flight validation job (YAMLtest-sovereign-runner) present"
else
  log_error "Pre-flight validation job NOT found"
fi

log_info "Checking runner deploy include..."
if grep -q "deploy:sovereign-runner" "$REPO_ROOT/.gitlab/ci-includes/runner-deploy.gitlab-ci.yml"; then
  log_ok "deploy:sovereign-runner job configured"
else
  log_error "deploy:sovereign-runner job NOT found"
fi

if grep -q "deploy:sovereign-runner-gsm" "$REPO_ROOT/.gitlab/ci-includes/runner-deploy.gitlab-ci.yml"; then
  log_ok "deploy:sovereign-runner-gsm job (GCP path) configured"
else
  log_error "deploy:sovereign-runner-gsm job NOT found"
fi

section "Git Status"

cd "$REPO_ROOT"

if git rev-parse --git-dir > /dev/null 2>&1; then
  log_ok "Repository is a Git repository"
  
  # Check for uncommitted changes
  if [ -z "$(git status --short)" ]; then
    log_ok "No uncommitted changes (working directory clean)"
  else
    log_warn "Uncommitted changes exist (not critical, but review before deploying)"
    git status --short | head -5
  fi
  
  # Check branch
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  LATEST_COMMIT=$(git rev-parse --short HEAD)
  log_ok "Current branch: $CURRENT_BRANCH (commit: $LATEST_COMMIT)"
  
  # Check if origin is set
  if git remote get-url origin > /dev/null 2>&1; then
    log_ok "Remote 'origin' is configured: $(git remote get-url origin)"
  else
    log_warn "Remote 'origin' is not configured"
  fi
else
  log_error "Not a Git repository"
fi

section "Local Environment"

# Check required commands
check_command() {
  local cmd=$1
  local description=$2
  if command -v "$cmd" &> /dev/null; then
    log_ok "$description installed: $(command -v "$cmd")"
  else
    log_warn "$description NOT installed (may be needed for local testing)"
  fi
}

check_command "kubectl" "kubectl"
check_command "helm" "helm"
check_command "git" "git"
check_command "jq" "jq"
check_command "base64" "base64"
check_command "gcloud" "gcloud"
check_command "docker" "docker"
check_command "kind" "kind"

section "Deployment Readiness Checklist"

echo ""
echo "Before deploying, ensure you have completed:"
echo ""
echo "  [ ] Created GCP secrets (see: issues/102-gsm-secrets-setup.md)"
echo "      - kubeconfig-secret"
echo "      - gitlab-runner-regtoken"
echo "      - gcp-sa-key"
echo ""
echo "  [ ] Set GitLab CI protected variables (see: issues/101-deploy-via-ci.md)"
echo "      - GCP_PROJECT"
echo "      - GCP_SA_KEY"
echo "      - KUBECONFIG_SECRET_NAME"
echo "      - REGTOKEN_SECRET_NAME"
echo ""
echo "  [ ] Verified kubeconfig is current and points to reachable cluster"
echo ""
echo "  [ ] Generated GitLab Runner registration token (admin panel)"
echo ""
echo "  [ ] Reviewed deployment guide: HANDS_OFF_DEPLOYMENT_GUIDE.md"
echo ""

section "Deployment Options"

echo ""
echo "Option A: Deploy via GCP Secret Manager (Recommended)"
echo "  $ gitlab pipelines run main"
echo "  $ Click play button on 'deploy:sovereign-runner-gsm'"
echo "  Estimated time: 2-5 minutes (fully automated)"
echo ""
echo "Option B: Deploy via GitLab Protected Variables"
echo "  $ Set KUBECONFIG_BASE64 + REG_TOKEN in GitLab CI variables"
echo "  $ gitlab pipelines run main"
echo "  $ Click play button on 'deploy:sovereign-runner'"
echo "  Estimated time: 2-5 minutes (fully automated)"
echo ""
echo "Option C: Local Testing (Optional)"
echo "  $ REG_TOKEN=glrt-... ./scripts/ci/hands_off_orchestrate.sh deploy"
echo "  $ ./scripts/ci/hands_off_orchestrate.sh validate"
echo "  Estimated time: 5-10 minutes"
echo ""

section "Summary"

TOTAL_ISSUES=$ERRORS
TOTAL_WARNINGS=$WARNINGS

echo ""
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✓ Health check PASSED${NC}"
  echo ""
  echo "Repository is ready for hands-off deployment."
  echo ""
  echo "Next steps:"
  echo "  1. Review: HANDS_OFF_DEPLOYMENT_GUIDE.md"
  echo "  2. Setup: Create GCP secrets (issues/102-gsm-secrets-setup.md)"
  echo "  3. Configure: Set GitLab CI variables (issues/101-deploy-via-ci.md)"
  echo "  4. Deploy: Trigger CI job (issues/103-trigger-ci-deploy.md)"
  echo "  5. Validate: Check pod readiness (issues/104-post-deploy-validation.md)"
  echo ""
else
  echo -e "${RED}✗ Health check FAILED${NC}"
  echo ""
  echo "Issues found: $ERRORS"
  echo "Warnings: $TOTAL_WARNINGS"
  echo ""
  echo "Please resolve the above errors before deploying."
  exit 1
fi

[ $TOTAL_WARNINGS -gt 0 ] && echo "Warnings: $TOTAL_WARNINGS (non-critical)"

exit 0
