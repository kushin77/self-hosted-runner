#!/bin/bash
#
# deployment-readiness-validator.sh - Pre-deployment validation
# Purpose: Verify all systems ready for infrastructure deployment
# Properties: Immutable (Git) | Ephemeral (no state) | Idempotent (safe re-run)
#
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
check() { echo -e "${BLUE}→${NC} $*"; }

TOTAL_CHECKS=0
PASSED_CHECKS=0

check_cluster() {
  echo ""
  check "Checking staging cluster..."
  ((TOTAL_CHECKS++))
  
  if timeout 5 bash -c "echo >/dev/tcp/192.168.168.42/6443" 2>/dev/null; then
    info "Staging cluster online (192.168.168.42:6443)"
    ((PASSED_CHECKS++))
  else
    error "Staging cluster offline"
  fi
}

check_github_secrets() {
  echo ""
  check "Checking GitHub secrets..."
  
  for secret in AWS_OIDC_ROLE_ARN USE_OIDC GCP_WORKLOAD_IDENTITY_PROVIDER AWS_ROLE_TO_ASSUME AWS_REGION STAGING_KUBECONFIG; do
    ((TOTAL_CHECKS++))
    if gh secret list --repo kushin77/self-hosted-runner 2>/dev/null | grep -q "^$secret"; then
      info "Secret found: $secret"
      ((PASSED_CHECKS++))
    else
      warn "Secret missing: $secret"
    fi
  done
}

check_workflows() {
  echo ""
  check "Checking workflows..."
  
  for workflow in phase-p3-pre-apply-orchestrator phase-p4-terraform-apply-orchestrator phase-p5-post-deployment-validation ops-blocker-monitoring; do
    ((TOTAL_CHECKS++))
    if [ -f ".github/workflows/${workflow}.yml" ]; then
      info "Workflow exists: $workflow"
      ((PASSED_CHECKS++))
    else
      error "Workflow missing: $workflow"
    fi
  done
}

check_terraform() {
  echo ""
  check "Checking Terraform configuration..."
  ((TOTAL_CHECKS++))
  
  if [ -d "terraform" ] && [ -f "terraform/main.tf" ]; then
    info "Terraform configuration found"
    ((PASSED_CHECKS++))
  else
    error "Terraform configuration missing"
  fi
}

check_automation_scripts() {
  echo ""
  check "Checking automation scripts..."
  
  for script in hands-off-bootstrap ci-auto-recovery infrastructure-readiness ops-blocker-automation operator-provisioning-helper deployment-readiness-validator; do
    ((TOTAL_CHECKS++))
    if [ -f "scripts/automation/${script}.sh" ]; then
      info "Script exists: $script"
      ((PASSED_CHECKS++))
    else
      error "Script missing: $script"
    fi
  done
}

check_documentation() {
  echo ""
  check "Checking documentation..."
  
  for doc in OPERATOR_EXECUTION_SUMMARY OPS_TRIAGE_RESOLUTION_MAR8 FULL_AUTOMATION_DELIVERY_FINAL DEPLOYMENT_READY; do
    ((TOTAL_CHECKS++))
    if [ -f "${doc}.md" ]; then
      info "Document found: $doc"
      ((PASSED_CHECKS++))
    else
      error "Document missing: $doc"
    fi
  done
}

check_git_status() {
  echo ""
  check "Checking Git status..."
  ((TOTAL_CHECKS++))
  
  if git status --short | grep -q .; then
    warn "Uncommitted changes detected"
  else
    info "Git working directory clean"
    ((PASSED_CHECKS++))
  fi
}

# MAIN
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║    DEPLOYMENT READINESS VALIDATOR                  ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

check_cluster
check_github_secrets
check_workflows
check_terraform
check_automation_scripts
check_documentation
check_git_status

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║    VALIDATION SUMMARY                              ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

PERCENTAGE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
echo "Passed: $PASSED_CHECKS / $TOTAL_CHECKS ($PERCENTAGE%)"

if [ $PERCENTAGE -ge 90 ]; then
  echo -e "${GREEN}✅ DEPLOYMENT READY${NC}"
  exit 0
elif [ $PERCENTAGE -ge 70 ]; then
  echo -e "${YELLOW}⚠️ PARTIAL READINESS - Review warnings${NC}"
  exit 1
else
  echo -e "${RED}❌ NOT READY - Address errors${NC}"
  exit 2
fi
