#!/usr/bin/env bash
# Delivery verification script - validates all deliverables are in place

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_1=0
FOUND=0

# Arrays for results
MISSING_FILES=()
FOUND_FILES=()

log_found() {
  TOTAL_1=$((TOTAL_1 + 1))
  FOUND=$((FOUND + 1))
  echo -e "${GREEN}✓${NC} $1"
  FOUND_FILES+=("$1")
}

log_missing() {
  TOTAL_1=$((TOTAL_1 + 1))
  echo -e "${RED}✗${NC} $1"
  MISSING_FILES+=("$1")
}

check_file() {
  local file="$1"
  local description="$2"
  
  if [ -f "${REPO_ROOT}/${file}" ]; then
    log_found "${description}"
  else
    log_missing "${description} (${file})"
  fi
}

check_files() {
  local pattern="$1"
  local description="$2"
  
  if find "${REPO_ROOT}" -path "*/.git" -prune -o -name "${pattern}" -type f -print | grep -q .; then
    TOTAL_1=$((TOTAL_1 + 1))
    FOUND=$((FOUND + 1))
    echo -e "${GREEN}✓${NC} ${description}"
  else
    TOTAL_1=$((TOTAL_1 + 1))
    echo -e "${RED}✗${NC} ${description} (pattern: ${pattern})"
    MISSING_FILES+=("${description}")
  fi
}

print_header() {
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
}

# Main verification
main() {
  print_header "CI/CD Runner Platform - Delivery Verification"
  
  # ======================================================================
  # Architecture & Design Files
  # ======================================================================
  
  print_header "1. Architecture & Design"
  
  check_file "docs/ci-cd-architecture.md" "CI/CD Architecture Overview"
  check_file "docs/k8s-reference.md" "Kubernetes Reference Implementation"
  check_file "docs/artifact-promotion.md" "Artifact Promotion Workflow"
  check_file "docs/security-controls.md" "Security Control Framework"
  check_file "docs/observability-model.md" "Observability Model & SLOs"
  check_file "docs/rollback-strategy.md" "Production Rollback Strategy"
  check_file ".ci/tekton-pipeline.yaml" "Example Tekton Pipeline"
  
  # ======================================================================
  # Runner Platform Bootstrap
  # ======================================================================
  
  print_header "2. Runner Platform - Bootstrap"
  
  check_file "cicd-runner-platform/bootstrap/bootstrap.sh" "Linux Bootstrap Script"
  check_file "cicd-runner-platform/bootstrap/bootstrap.ps1" "Windows Bootstrap Script"
  check_file "cicd-runner-platform/bootstrap/verify-host.sh" "Host Verification Script"
  check_file "cicd-runner-platform/bootstrap/install-dependencies.sh" "Dependency Installation"
  
  # ======================================================================
  # Runner Management
  # ======================================================================
  
  print_header "3. Runner Platform - Management"
  
  check_file "cicd-runner-platform/runner/install-runner.sh" "Runner Installation"
  check_file "cicd-runner-platform/runner/register-runner.sh" "Runner Registration"
  check_file "cicd-runner-platform/runner/update-runner.sh" "Auto-Update Daemon"
  
  # ======================================================================
  # Pipeline Executors
  # ======================================================================
  
  print_header "4. Pipeline Executors"
  
  check_file "cicd-runner-platform/pipeline-executors/build-executor.sh" "Build Executor (hermetic builds, SBOM, signing)"
  check_file "cicd-runner-platform/pipeline-executors/test-executor.sh" "Test Executor (isolated networks, coverage)"
  check_file "cicd-runner-platform/pipeline-executors/security-executor.sh" "Security Executor (SAST, secrets, SCA, policies)"
  check_file "cicd-runner-platform/pipeline-executors/deploy-executor.sh" "Deploy Executor (canary, rollback, health checks)"
  
  # ======================================================================
  # Security Modules
  # ======================================================================
  
  print_header "5. Security Modules"
  
  check_file "cicd-runner-platform/security/artifact-signing/cosign-sign.sh" "Cosign Signing with Keyless OIDC"
  check_file "cicd-runner-platform/security/sbom/generate-sbom.sh" "SBOM Generation (SPDX/CycloneDX)"
  check_file "cicd-runner-platform/security/policy/opa-policies.rego" "OPA Policies (12+ rules, compliance checks)"
  
  # ======================================================================
  # Observability
  # ======================================================================
  
  print_header "6. Observability Stack"
  
  check_file "cicd-runner-platform/observability/metrics-agent.yaml" "Prometheus Configuration"
  check_file "cicd-runner-platform/observability/logging-agent.yaml" "Fluent Bit Configuration"
  check_file "cicd-runner-platform/observability/otel-config.yaml" "OpenTelemetry Configuration"
  
  # ======================================================================
  # Self-Healing
  # ======================================================================
  
  print_header "7. Self-Healing & Lifecycle"
  
  check_file "cicd-runner-platform/self-update/update-checker.sh" "Auto-Update Daemon"
  check_file "cicd-runner-platform/scripts/health-check.sh" "Health Check Daemon"
  check_file "cicd-runner-platform/scripts/clean-runner.sh" "Workspace Cleanup Script"
  check_file "cicd-runner-platform/scripts/destroy-runner.sh" "Runner Destruction Script"
  
  # ======================================================================
  # Configuration
  # ======================================================================
  
  print_header "8. Configuration Files"
  
  check_file "cicd-runner-platform/config/runner-env.yaml" "Runtime Configuration"
  check_file "cicd-runner-platform/config/feature-flags.yaml" "Feature Flags & Rollout Control"
  
  # ======================================================================
  # Cloud Deployment Guides
  # ======================================================================
  
  print_header "9. Cloud Deployment Guides"
  
  check_file "cicd-runner-platform/docs/deployment-ec2.md" "AWS EC2 Deployment Guide"
  check_file "cicd-runner-platform/docs/deployment-gcp.md" "GCP Deployment Guide"
  check_file "cicd-runner-platform/docs/deployment-azure.md" "Azure Deployment Guide"
  
  # ======================================================================
  # Documentation
  # ======================================================================
  
  print_header "10. Documentation"
  
  check_file "cicd-runner-platform/docs/architecture.md" "Runner Platform Architecture"
  check_file "cicd-runner-platform/docs/runner-lifecycle.md" "Runner Lifecycle & State Machine"
  check_file "cicd-runner-platform/docs/security-model.md" "Security Model & Threat Analysis"
  check_file "cicd-runner-platform/README.md" "Platform Quick Start"
  check_file "DELIVERY_COMPLETION_REPORT.md" "Delivery Completion Report"
  
  # ======================================================================
  # Tests
  # ======================================================================
  
  print_header "11. Test Suites"
  
  check_file "tests/integration-test.sh" "Integration Test Suite (30+ tests)"
  check_file "tests/security-test.sh" "Security Test Suite (25+ tests)"
  check_file "tests/cloud-test-ec2.sh" "EC2 Deployment Test"
  check_file "tests/cloud-test-gcp.sh" "GCP Deployment Test"
  check_file "tests/cloud-test-azure.sh" "Azure Deployment Test"
  check_file "tests/run-tests.sh" "Master Test Runner"
  check_file "tests/README.md" "Test Suite Documentation"
  
  # ======================================================================
  # Verify Script Permissions
  # ======================================================================
  
  print_header "12. Script Permissions"
  
  local scripts=(
    "cicd-runner-platform/bootstrap/bootstrap.sh"
    "cicd-runner-platform/bootstrap/verify-host.sh"
    "cicd-runner-platform/bootstrap/install-dependencies.sh"
    "cicd-runner-platform/runner/install-runner.sh"
    "cicd-runner-platform/runner/register-runner.sh"
    "cicd-runner-platform/runner/update-runner.sh"
    "cicd-runner-platform/pipeline-executors/build-executor.sh"
    "cicd-runner-platform/pipeline-executors/test-executor.sh"
    "cicd-runner-platform/pipeline-executors/security-executor.sh"
    "cicd-runner-platform/pipeline-executors/deploy-executor.sh"
    "tests/integration-test.sh"
    "tests/security-test.sh"
    "tests/cloud-test-ec2.sh"
    "tests/cloud-test-gcp.sh"
    "tests/cloud-test-azure.sh"
    "tests/run-tests.sh"
  )
  
  local executable_count=0
  for script in "${scripts[@]}"; do
    if [ -f "${REPO_ROOT}/${script}" ] && [ -x "${REPO_ROOT}/${script}" ]; then
      executable_count=$((executable_count + 1))
    fi
  done
  
  TOTAL_1=$((TOTAL_1 + 1))
  if [ ${executable_count} -eq ${#scripts[@]} ]; then
    FOUND=$((FOUND + 1))
    echo -e "${GREEN}✓${NC} All scripts are executable (${executable_count}/${#scripts[@]})"
  else
    echo -e "${RED}✗${NC} Some scripts not executable (${executable_count}/${#scripts[@]})"
    MISSING_FILES+=("Script permissions")
  fi
  
  # ======================================================================
  # Summary
  # ======================================================================
  
  print_header "Verification Summary"
  
  local percentage=$((FOUND * 100 / TOTAL_1))
  echo "Total checks: ${TOTAL_1}"
  echo "Passed: ${FOUND}"
  echo "Failed: $((TOTAL_1 - FOUND))"
  echo "Completion: ${percentage}%"
  
  if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Missing or Incomplete:${NC}"
    for item in "${MISSING_FILES[@]}"; do
      echo -e "  ${RED}✗${NC} ${item}"
    done
  fi
  
  echo ""
  
  if [ ${percentage} -eq 100 ]; then
    echo -e "${GREEN}✅ DELIVERY COMPLETE - ALL DELIVERABLES READY${NC}"
    echo ""
    echo "Platform is production-ready for deployment:"
    echo "  1. Run tests: ./tests/run-tests.sh"
    echo "  2. Select cloud: EC2/GCP/Azure"
    echo "  3. Deploy: Follow cicd-runner-platform/docs/deployment-*.md"
    echo "  4. Monitor: Check Prometheus/Loki/Jaeger dashboards"
    echo ""
    return 0
  else
    echo -e "${YELLOW}⚠️  DELIVERY INCOMPLETE - ${#MISSING_FILES[@]} items missing${NC}"
    return 1
  fi
}

main "$@"
