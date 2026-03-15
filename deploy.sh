#!/bin/bash
#
# Direct Deployment Trigger - Hands-Off Automation Entry Point
#
# Purpose: Trigger direct deployment without GitHub Actions or pull requests
#         - Fully automated: No manual intervention required
#         - Cloud Build integration: Direct execution
#         - Immutable: Only version-controlled code deployed
#         - Idempotent: Safe re-execution
#
# Usage:
#   ./deploy.sh --environment prod --components all
#   ./deploy.sh --environment staging --components k8s-health-checks
#   ./deploy.sh --environment prod --components multi-region-failover --skip-verification
#
# Features:
#   - Direct Cloud Build integration (no GitHub Actions)
#   - GSM/Vault/KMS credential management
#   - Automatic health verification
#   - Immutable deployment artifacts
#   - Full audit trail
#

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
readonly DEPLOYMENT_LOG="${REPO_ROOT}/.deployment-log"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Defaults
ENVIRONMENT="prod"
COMPONENTS="all"
SKIP_VERIFICATION=false
DRY_RUN=false
WATCH_BUILD=true

# Logging function
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; return 1; }

# Parse arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --environment)
        ENVIRONMENT="$2"
        shift 2
        ;;
      --components)
        COMPONENTS="$2"
        shift 2
        ;;
      --skip-verification)
        SKIP_VERIFICATION=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-watch)
        WATCH_BUILD=false
        shift
        ;;
      *)
        error "Unknown argument: $1"
        ;;
    esac
  done
}

# Verify deployment prerequisites
verify_prerequisites() {
  log "Verifying deployment prerequisites..."
  
  # Check required commands
  local REQUIRED_COMMANDS=(
    "git"
    "gcloud"
    "kubectl"
    "jq"
  )
  
  for CMD in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "${CMD}" &>/dev/null; then
      error "Required command not found: ${CMD}"
    fi
  done
  
  # Verify git status
  if [[ -n $(git status --porcelain) ]]; then
    error "Working directory has uncommitted changes. Commit first."
  fi
  
  # Verify we're on a valid branch
  local CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  log "Current branch: ${CURRENT_BRANCH}"
  
  # Get current commit
  local CURRENT_COMMIT=$(git rev-parse HEAD)
  log "Current commit: ${CURRENT_COMMIT:0:10}"
  
  # Verify Cloud Build project is configured
  local PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [[ -z "${PROJECT_ID}" ]]; then
    error "GCP project not configured. Run: gcloud config set project PROJECT_ID"
  fi
  
  log "✓ All prerequisites verified"
}

# Verify deployment is safe
verify_deployment_safety() {
  log "Verifying deployment safety..."
  
  # Check git remote
  if ! git remote -v | grep -q "origin"; then
    error "Git origin not configured"
  fi
  
  # Verify SSH access to git
  if ! git ls-remote origin &>/dev/null; then
    error "Cannot access git repository. Check SSH keys."
  fi
  
  # Verify GCP access.
  # Prefer ADC for workload-safe automation, but allow fallback to active user auth
  # on developer hosts where ADC is not configured.
  if ! gcloud auth application-default print-access-token &>/dev/null; then
    log "ADC not configured; falling back to active gcloud account credentials"
    if ! gcloud auth print-access-token &>/dev/null; then
      error "Cannot access GCP via ADC or active gcloud account. Check authentication."
    fi
  fi
  
  # Verify Cloud Build API enabled
  if ! gcloud services list --enabled 2>/dev/null | grep -q "cloudbuild"; then
    error "Cloud Build API not enabled. Enable it first."
  fi
  
  log "✓ Deployment safety verified"
}

# Submit Cloud Build job
submit_build() {
  local ENVIRONMENT="$1"
  
  log "Submitting Cloud Build job..."
  log "  Environment: ${ENVIRONMENT}"
  log "  Components: ${COMPONENTS}"
  
  local BUILD_ARGS=(
    "--config=cloudbuild-direct-deployment.yaml"
    "--substitutions=_ENVIRONMENT=${ENVIRONMENT},_COMPONENTS=${COMPONENTS}"
    "--async"
    "--timeout=3600s"
  )
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN MODE - Would execute:"
    log "  gcloud builds submit ${BUILD_ARGS[@]}"
    return 0
  fi
  
  # Submit build
  local BUILD_OUTPUT
  BUILD_OUTPUT=$(gcloud builds submit "${BUILD_ARGS[@]}" 2>&1)
  
  # Extract build ID
  local BUILD_ID=$(echo "${BUILD_OUTPUT}" | grep -oP 'Starting Cloud Build job' | head -1)
  BUILD_ID=$(gcloud builds list --limit=1 --format='value(id)' 2>/dev/null | head -1)
  
  if [[ -z "${BUILD_ID}" ]]; then
    error "Failed to get build ID"
  fi
  
  log "✓ Build submitted successfully"
  log "  Build ID: ${BUILD_ID}"
  echo "${BUILD_ID}"
}

# Watch build progress
watch_build() {
  local BUILD_ID="$1"
  
  if [[ "${WATCH_BUILD}" != "true" ]]; then
    log "Skipping build watch (use 'gcloud builds log ${BUILD_ID} --stream' to monitor)"
    return 0
  fi
  
  log "Watching build progress (CTRL+C to exit)..."
  log "Build ID: ${BUILD_ID}"
  log "View logs: gcloud builds log ${BUILD_ID} --stream"
  
  # Stream logs
  gcloud builds log "${BUILD_ID}" --stream 2>/dev/null || {
    # If streaming not available, poll status
    while true; do
      local STATUS=$(gcloud builds describe "${BUILD_ID}" --format='value(status)' 2>/dev/null)
      case "${STATUS}" in
        SUCCESS)
          log "✓ Build completed successfully"
          return 0
          ;;
        FAILURE)
          error "Build failed"
          ;;
        TIMEOUT)
          error "Build timed out"
          ;;
        QUEUED|WORKING)
          log "Build status: ${STATUS}"
          sleep 10
          ;;
        *)
          log "Build status: ${STATUS}"
          sleep 5
          ;;
      esac
    done
  }
}

# Verify deployment results
verify_deployment_results() {
  local ENVIRONMENT="$1"
  
  if [[ "${SKIP_VERIFICATION}" == "true" ]]; then
    log "Skipping deployment verification"
    return 0
  fi
  
  log "Verifying deployment results..."
  
  # Check deployment status in target environment
  if ! kubectl get deployment -n "${ENVIRONMENT}" &>/dev/null; then
    error "Failed to verify deployments in ${ENVIRONMENT}"
  fi
  
  # Wait for deployments to be ready
  local MAX_WAIT=300  # 5 minutes
  local ELAPSED=0
  
  while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    local READY=$(kubectl get deployment -n "${ENVIRONMENT}" \
      --format='count(status.conditions[?(@.type=="Available")].status=="True")' 2>/dev/null)
    local TOTAL=$(kubectl get deployment -n "${ENVIRONMENT}" \
      --format='count(items[*])' 2>/dev/null)
    
    if [[ "${READY}" == "${TOTAL}" ]] && [[ "${TOTAL}" -gt 0 ]]; then
      log "✓ All deployments ready"
      return 0
    fi
    
    log "Waiting for deployments: ${READY}/${TOTAL} ready"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
  done
  
  error "Deployment verification timeout"
}

# Generate deployment summary
generate_summary() {
  local BUILD_ID="$1"
  local ENVIRONMENT="$2"
  
  log ""
  log "╔════════════════════════════════════════╗"
  log "║  ✅ DEPLOYMENT COMPLETED               ║"
  log "╚════════════════════════════════════════╝"
  log ""
  log "Deployment Information:"
  log "  Environment: ${ENVIRONMENT}"
  log "  Components: ${COMPONENTS}"
  log "  Build ID: ${BUILD_ID}"
  log "  Timestamp: ${TIMESTAMP}"
  log ""
  log "Next Steps:"
  log "  1. Monitor build: gcloud builds log ${BUILD_ID} --stream"
  log "  2. Check deployment: kubectl get deployment -n ${ENVIRONMENT}"
  log "  3. View audit trail: cat scripts/automation/audit/orchestration_*.log"
  log "  4. Review release notes: cat CHANGELOG.md"
  log ""
  log "Support:"
  log "  Documentation: scripts/k8s-health-checks/README.md"
  log "  Configuration: scripts/k8s-health-checks/CONFIGURATION.md"
  log "  Troubleshooting: scripts/k8s-health-checks/README.md#troubleshooting"
  log ""
}

# Main execution
main() {
  parse_arguments "$@"
  
  log "╔════════════════════════════════════════╗"
  log "║  Direct Deployment Automation           ║"
  log "║  Starting deployment workflow...        ║"
  log "╚════════════════════════════════════════╝"
  log ""
  
  # Verify prerequisites
  verify_prerequisites
  
  # Verify safety
  verify_deployment_safety
  
  # Submit build
  local BUILD_ID
  BUILD_ID=$(submit_build "${ENVIRONMENT}")
  
  # Watch build (if not dry-run)
  if [[ "${DRY_RUN}" != "true" ]]; then
    watch_build "${BUILD_ID}"
    
    # Verify results
    verify_deployment_results "${ENVIRONMENT}"
  fi
  
  # Generate summary
  generate_summary "${BUILD_ID}" "${ENVIRONMENT}"
  
  log "Deployment workflow completed ✓"
}

# Execute main
main "$@"
