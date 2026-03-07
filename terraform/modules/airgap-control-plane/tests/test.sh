#!/usr/bin/env bash
# Test script for airgap-control-plane Terraform module
# Validates module syntax, runs Terraform plan/apply, and verifies resources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAMESPACE="airgap-test-$(date +%s)"
KUBECONFIG="${KUBECONFIG:-}"
CLEANUP_ON_EXIT="${CLEANUP_ON_EXIT:-true}"

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

# Cleanup function
cleanup() {
  if [ "$CLEANUP_ON_EXIT" = "true" ]; then
    log_info "Cleaning up test resources..."
    cd "$TEST_DIR"
    terraform destroy -auto-approve -var="test_namespace=$TEST_NAMESPACE" 2>/dev/null || true
    log_info "Cleanup complete"
  else
    log_warning "Skipping cleanup. Manual cleanup required:"
    log_warning "  kubectl delete namespace $TEST_NAMESPACE"
    log_warning "  cd $TEST_DIR && terraform destroy"
  fi
}

# Set trap for cleanup
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  local missing=0
  
  if ! command -v terraform &> /dev/null; then
    log_error "terraform not found in PATH"
    missing=$((missing + 1))
  fi
  
  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found in PATH"
    missing=$((missing + 1))
  fi
  
  if ! command -v helm &> /dev/null; then
    log_error "helm not found in PATH"
    missing=$((missing + 1))
  fi
  
  if [ -z "$KUBECONFIG" ] && ! kubectl config current-context &> /dev/null; then
    log_error "No Kubernetes context available. Set KUBECONFIG or configure kubeconfig"
    missing=$((missing + 1))
  fi
  
  if [ $missing -gt 0 ]; then
    log_error "$missing prerequisite(s) missing. Aborting."
    exit 1
  fi
  
  log_info "All prerequisites met"
}

# Test Terraform syntax
test_terraform_syntax() {
  log_info "Testing Terraform syntax..."
  
  cd "$MODULE_DIR"
  
  if terraform init -backend=false > /dev/null 2>&1; then
    log_info "Terraform module initialized"
  else
    log_error "Failed to initialize Terraform module"
    return 1
  fi
  
  if terraform validate > /dev/null 2>&1; then
    log_info "Terraform configuration is valid"
  else
    log_error "Terraform validation failed"
    terraform validate
    return 1
  fi
  
  return 0
}

# Test Terraform plan
test_terraform_plan() {
  log_info "Testing Terraform plan..."
  
  cd "$TEST_DIR"
  
  if terraform init > /dev/null 2>&1; then
    log_info "Test environment initialized"
  else
    log_error "Failed to initialize test environment"
    return 1
  fi
  
  if terraform plan -var="test_namespace=$TEST_NAMESPACE" -out=tfplan > /dev/null 2>&1; then
    log_info "Terraform plan successful"
  else
    log_error "Terraform plan failed"
    terraform plan -var="test_namespace=$TEST_NAMESPACE"
    return 1
  fi
  
  return 0
}

# Test Terraform apply (optional, requires Kubernetes cluster)
test_terraform_apply() {
  local apply_test="${1:-false}"
  
  if [ "$apply_test" != "true" ]; then
    log_info "Skipping Terraform apply test (set APPLY_TEST=true to enable)"
    return 0
  fi
  
  log_info "Applying Terraform configuration to cluster..."
  
  cd "$TEST_DIR"
  
  if terraform apply -auto-approve tfplan > /dev/null 2>&1; then
    log_info "Terraform apply successful"
  else
    log_error "Terraform apply failed"
    return 1
  fi
  
  # Wait for namespace to be created
  sleep 5
  
  # Verify namespace was created
  if kubectl get namespace "$TEST_NAMESPACE" > /dev/null 2>&1; then
    log_info "Namespace created successfully: $TEST_NAMESPACE"
  else
    log_error "Namespace was not created"
    return 1
  fi
  
  # Verify network policy was created
  if kubectl get networkpolicy -n "$TEST_NAMESPACE" airgap-control-plane-egress > /dev/null 2>&1; then
    log_info "Network policy created successfully"
  else
    log_error "Network policy was not created"
    return 1
  fi
  
  # Verify PVC was created
  if kubectl get pvc -n "$TEST_NAMESPACE" image-storage-pvc > /dev/null 2>&1; then
    log_info "Image storage PVC created successfully"
  else
    log_error "Image storage PVC was not created"
  fi
  
  return 0
}

# Test Helm values template
test_helm_values() {
  log_info "Testing Helm values template..."
  
  local tpl_file="$MODULE_DIR/helm-values.tpl"
  
  if [ ! -f "$tpl_file" ]; then
    log_error "Helm values template not found: $tpl_file"
    return 1
  fi
  
  # Simple check that template has required variables
  local required_vars=("image_loader_image" "collector_enabled" "registry_mirror_enabled")
  
  for var in "${required_vars[@]}"; do
    if grep -q "\${$var}" "$tpl_file"; then
      log_info "Template contains required variable: $var"
    else
      log_error "Template missing required variable: $var"
      return 1
    fi
  done
  
  return 0
}

# Main test execution
main() {
  log_info "Starting airgap-control-plane module tests"
  log_info "Test namespace: $TEST_NAMESPACE"
  log_info "Module directory: $MODULE_DIR"
  
  local test_failed=0
  
  check_prerequisites || exit 1
  
  test_terraform_syntax || test_failed=1
  test_helm_values || test_failed=1
  test_terraform_plan || test_failed=1
  
  # Run apply test only if explicitly requested
  local apply_test="${1:-false}"
  test_terraform_apply "$apply_test" || test_failed=1
  
  if [ $test_failed -eq 0 ]; then
    log_info "All tests passed successfully"
    return 0
  else
    log_error "Some tests failed"
    return 1
  fi
}

# Execute main function
main "$@"
