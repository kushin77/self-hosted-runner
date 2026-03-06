#!/usr/bin/env bash
set -euo pipefail

# Master deployment orchestration script for hands-off GitLab Runner migration
# Purpose: Coordinate fully automated, immutable, sovereign, ephemeral runner deployment
# Usage: ./scripts/ci/hands_off_orchestrate.sh [phase]
# Phases: check | deploy | validate | migrate | cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
PHASE="${1:-check}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NAMESPACE="gitlab-runner"
HELM_RELEASE="gitlab-runner"

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_ok() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*"
}

# Phase 1: Check prerequisites
phase_check() {
  log_info "Checking deployment prerequisites..."

  # Check kubectl
  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not installed"
    exit 1
  fi
  log_ok "kubectl installed: $(kubectl version --client --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+')"

  # Check helm
  if ! command -v helm &> /dev/null; then
    log_error "helm not installed"
    exit 1
  fi
  log_ok "helm installed: $(helm version --short 2>/dev/null || echo 'unknown')"

  # Check kubeconfig
  if [ ! -f "$KUBECONFIG" ]; then
    log_error "KUBECONFIG not found at $KUBECONFIG"
    exit 1
  fi
  log_ok "kubeconfig found at $KUBECONFIG"

  # Check cluster connectivity
  if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
  fi
  log_ok "Kubernetes cluster reachable"

  # Check if namespace exists
  if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_ok "Namespace '$NAMESPACE' exists"
  else
    log_warn "Namespace '$NAMESPACE' does not exist (will be created during deploy)"
  fi

  # Check for Helm chart
  if [ ! -f "$REPO_ROOT/infra/gitlab-runner/values.yaml.template" ]; then
    log_error "Helm values template not found at $REPO_ROOT/infra/gitlab-runner/values.yaml.template"
    exit 1
  fi
  log_ok "Helm values template found"

  log_ok "All prerequisites satisfied"
}

# Phase 2: Deploy runner (assumes secrets are in place)
phase_deploy() {
  log_info "Deploying GitLab Runner via Helm..."

  if [ -z "${REG_TOKEN:-}" ]; then
    log_error "REG_TOKEN environment variable not set"
    log_info "Please provide REG_TOKEN and re-run:"
    log_info "  REG_TOKEN=<token> KUBECONFIG=~/.kube/config $0 deploy"
    exit 1
  fi

  log_info "Creating namespace if needed..."
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  log_info "Generating/applying secrets..."
  chmod +x "$REPO_ROOT/scripts/ci/create_sealedsecret_from_token.sh"
  "$REPO_ROOT/scripts/ci/create_sealedsecret_from_token.sh" "$REG_TOKEN" "$NAMESPACE"

  # Apply secret (either SealedSecret or plain Secret)
  if [ -f "$REPO_ROOT/infra/gitlab-runner/sealedsecret.generated.yaml" ]; then
    log_info "Applying SealedSecret..."
    kubectl apply -f "$REPO_ROOT/infra/gitlab-runner/sealedsecret.generated.yaml"
  elif [ -f "$REPO_ROOT/infra/gitlab-runner/secret.generated.yaml" ]; then
    log_warn "Applying plain Secret (insecure for production)..."
    kubectl apply -f "$REPO_ROOT/infra/gitlab-runner/secret.generated.yaml"
  else
    log_error "No secret manifest found"
    exit 1
  fi

  log_info "Running hands-off Helm deploy..."
  chmod +x "$REPO_ROOT/scripts/ci/hands_off_runner_deploy.sh"
  "$REPO_ROOT/scripts/ci/hands_off_runner_deploy.sh"

  log_ok "Deployment completed"
}

# Phase 3: Validate runner
phase_validate() {
  log_info "Validating runner deployment..."

  # Check pod readiness
  log_info "Waiting for runner pods to be ready..."
  if kubectl wait --for=condition=ready pod -l app=gitlab-runner -n "$NAMESPACE" --timeout=300s 2>/dev/null; then
    log_ok "Runner pods are ready"
  else
    log_warn "Pods did not reach Ready state within timeout"
  fi

  # Show pod status
  log_info "Pod status:"
  kubectl get pods -n "$NAMESPACE" -l app=gitlab-runner -o wide

  # Show logs
  log_info "Latest logs:"
  kubectl logs -n "$NAMESPACE" -l app=gitlab-runner --tail=50 --timestamps=true

  # Check if runner is registered
  log_info "Checking runner registration in GitLab..."
  if [ -n "${GITLAB_URL:-}" ] && [ -n "${GITLAB_API_TOKEN:-}" ]; then
    # Attempt to check via API
    runner_count=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
      "$GITLAB_URL/api/v4/admin/runners?tag_list=k8s-runner" | jq 'length' 2>/dev/null || echo "0")
    if [ "$runner_count" -gt 0 ]; then
      log_ok "Found $runner_count runner(s) with 'k8s-runner' tag"
    else
      log_warn "Could not verify runner registration via API"
    fi
  else
    log_info "Skipping runner API check (GITLAB_URL and GITLAB_API_TOKEN not set)"
  fi

  log_ok "Validation completed"
}

# Phase 4: Run test pipeline
phase_test() {
  log_info "Triggering YAMLtest-sovereign-runner pipeline..."

  if [ -z "${GITLAB_API_TOKEN:-}" ] || [ -z "${PROJECT_ID:-}" ]; then
    log_error "GITLAB_API_TOKEN and PROJECT_ID must be set"
    log_info "Usage: GITLAB_API_TOKEN=<token> PROJECT_ID=<id> $0 test"
    exit 1
  fi

  chmod +x "$REPO_ROOT/scripts/ci/trigger_yamltest_pipeline.sh"
  "$REPO_ROOT/scripts/ci/trigger_yamltest_pipeline.sh" "main"

  log_ok "Pipeline triggered"
  log_info "Monitor progress in GitLab UI: $GITLAB_URL/project/$PROJECT_ID/pipelines"
}

# Phase 5: Migration and legacy runner decommission
phase_migrate() {
  log_info "Ready for runner migration..."
  log_info ""
  log_info "Checklist before proceeding:"
  log_info "  [ ] New runner is Online in GitLab admin"
  log_info "  [ ] YAMLtest-sovereign-runner passed"
  log_info "  [ ] Multiple test pipelines ran successfully"
  log_info "  [ ] No regressions observed in logs"
  log_info ""
  log_info "Next steps (manual in GitLab UI):"
  log_info "  1. Disable legacy runner(s)"
  log_info "  2. Monitor for 24 hours"
  log_info "  3. If stable: delete legacy runner"
  log_info ""
  log_info "See issues/105-runner-migration-decommission.md for detailed steps"
}

# Phase 6: Cleanup
phase_cleanup() {
  log_warn "Cleanup phase (optional, destructive)"
  read -p "This will DELETE the gitlab-runner release. Continue? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    log_info "Cleanup cancelled"
    return
  fi

  log_info "Removing Helm release..."
  helm uninstall "$HELM_RELEASE" -n "$NAMESPACE" || true

  log_info "Removing namespace..."
  kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

  log_ok "Cleanup completed"
}

# Show help
show_help() {
  cat << EOF
Usage: $(basename "$0") [PHASE]

Phases:
  check       - Verify prerequisites (kubectl, helm, cluster, kubeconfig)
  deploy      - Deploy runner via Helm (requires REG_TOKEN env var)
  validate    - Verify pod readiness and registration
  test        - Trigger YAMLtest-sovereign-runner pipeline
  migrate     - Show migration checklist and next steps
  cleanup     - DESTRUCTIVE: remove runner deployment (requires confirmation)

Environment Variables:
  KUBECONFIG              - Path to kubeconfig (default: ~/.kube/config)
  REG_TOKEN               - GitLab Runner registration token (for deploy phase)
  GITLAB_API_TOKEN        - GitLab API token (for test phase)
  GITLAB_URL              - GitLab instance URL (default: https://gitlab.com)
  PROJECT_ID              - GitLab project ID (for test phase)

Examples:
  # Just check dependencies
  $(basename "$0") check

  # Deploy with token from environment
  REG_TOKEN="glrt-..." $(basename "$0") deploy

  # Full flow: check, deploy, validate
  REG_TOKEN="glrt-..." $(basename "$0") check && REG_TOKEN="glrt-..." $(basename "$0") deploy && $(basename "$0") validate

  # Trigger test pipeline
  GITLAB_API_TOKEN="glpat-..." PROJECT_ID=12345 $(basename "$0") test
EOF
}

# Main
case "${PHASE}" in
  check)
    phase_check
    ;;
  deploy)
    phase_check
    phase_deploy
    ;;
  validate)
    phase_validate
    ;;
  test)
    phase_test
    ;;
  migrate)
    phase_migrate
    ;;
  cleanup)
    phase_cleanup
    ;;
  help|-h|--help)
    show_help
    exit 0
    ;;
  *)
    log_error "Unknown phase: $PHASE"
    show_help
    exit 1
    ;;
esac

log_ok "Phase '$PHASE' completed successfully"
