#!/bin/bash

################################################################################
# Kubernetes Cluster Health Check Script
# Purpose: Pre-deployment cluster validation with retry logic & alerting
# Usage: ./cluster-health-check.sh [--verbose] [--max-retries N]
################################################################################

set -euo pipefail

# Configuration
CLUSTER_NAME="${GKE_CLUSTER_NAME:-nexus-gke-main}"
PROJECT_ID="${GCP_PROJECT_ID}"
REGION="${GKE_REGION:-us-central1}"
MAX_RETRIES="${1:--1}"
INITIAL_BACKOFF=2
MAX_BACKOFF=32
VERBOSE="${VERBOSE:-false}"

# State
RETRY_COUNT=0
BACKOFF_DELAY=$INITIAL_BACKOFF

# Logging
LOG_DIR="${LOG_DIR:-logs/health-checks}"
LOG_FILE="$LOG_DIR/cluster-health-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

debug() {
  if [[ "$VERBOSE" == "true" ]]; then
    log_info "[DEBUG] $*"
  fi
}

################################################################################
# Health Check Functions
################################################################################

check_gcloud_auth() {
  log_info "Checking gcloud authentication..."
  
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    log_error "No active gcloud authentication found"
    return 1
  fi
  
  debug "gcloud authentication OK"
  return 0
}

check_cluster_exists() {
  log_info "Checking if cluster '$CLUSTER_NAME' exists..."
  
  if ! gcloud container clusters describe "$CLUSTER_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status)" &>/dev/null; then
    log_error "Cluster '$CLUSTER_NAME' not found in region $REGION"
    return 1
  fi
  
  debug "Cluster exists"
  return 0
}

check_cluster_status() {
  log_info "Checking cluster status..."
  
  local status=$(gcloud container clusters describe "$CLUSTER_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status)")
  
  if [[ "$status" != "RUNNING" ]]; then
    log_error "Cluster status is '$status', expected 'RUNNING'"
    return 1
  fi
  
  debug "Cluster status: $status"
  return 0
}

check_control_plane() {
  log_info "Checking control plane health..."
  
  local master=$(gcloud container clusters describe "$CLUSTER_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(masterStatus)")
  
  if [[ -z "$master" || "$master" != "RUNNING" ]]; then
    log_error "Control plane is not healthy (status: $master)"
    return 1
  fi
  
  debug "Control plane status: $master"
  return 0
}

check_nodes_ready() {
  log_info "Checking node pool readiness..."
  
  if ! kubectl get nodes --no-headers &>/dev/null; then
    log_error "Cannot connect to Kubernetes API"
    return 1
  fi
  
  local total_nodes=$(kubectl get nodes --no-headers | wc -l)
  local ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || true)
  
  if [[ $ready_nodes -eq 0 ]]; then
    log_error "No nodes are in 'Ready' state (total: $total_nodes)"
    return 1
  fi
  
  log_info "Nodes ready: $ready_nodes/$total_nodes"
  
  if [[ $ready_nodes -lt $total_nodes ]]; then
    log_warn "Some nodes not ready: $((total_nodes - ready_nodes)) nodes unavailable"
    # Don't fail yet - this may be transitional
  fi
  
  return 0
}

check_api_server() {
  log_info "Checking Kubernetes API server..."
  
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach Kubernetes API server"
    return 1
  fi
  
  debug "Kubernetes API server is reachable"
  return 0
}

check_core_namespaces() {
  log_info "Checking core namespaces..."
  
  local required_ns=("kube-system" "kube-public")
  
  for ns in "${required_ns[@]}"; do
    if ! kubectl get namespace "$ns" &>/dev/null; then
      log_error "Required namespace '$ns' not found"
      return 1
    fi
    debug "Namespace '$ns' exists"
  done
  
  return 0
}

check_dns() {
  log_info "Checking DNS service..."
  
  if ! kubectl get service -n kube-system kube-dns &>/dev/null; then
    log_error "DNS service not found in kube-system"
    return 1
  fi
  
  debug "DNS service is available"
  return 0
}

check_network_connectivity() {
  log_info "Checking network connectivity..."
  
  # Deploy a test pod to verify network connectivity
  local test_pod="health-check-test-$RANDOM"
  
  kubectl run "$test_pod" \
    --image=busybox:latest \
    --restart=Never \
    --command -- sleep 60 \
    2>/dev/null || {
    log_error "Failed to create test pod for network check"
    return 1
  }
  
  # Wait for pod to be ready
  local max_wait=30
  local waited=0
  while ! kubectl get pod "$test_pod" --field-selector=status.phase=Running &>/dev/null; do
    if [[ $waited -ge $max_wait ]]; then
      log_error "Test pod failed to reach Running state (timeout: ${max_wait}s)"
      kubectl delete pod "$test_pod" 2>/dev/null || true
      return 1
    fi
    sleep 1
    ((waited++))
  done
  
  # Cleanup
  kubectl delete pod "$test_pod" 2>/dev/null || true
  debug "Network connectivity verified"
  
  return 0
}

################################################################################
# Retry Logic with Exponential Backoff
################################################################################

run_health_checks() {
  local check_funcs=(
    "check_gcloud_auth"
    "check_cluster_exists"
    "check_cluster_status"
    "check_control_plane"
    "check_api_server"
    "check_core_namespaces"
    "check_dns"
    "check_nodes_ready"
    "check_network_connectivity"
  )
  
  for func in "${check_funcs[@]}"; do
    if ! $func; then
      log_error "Health check failed: $func"
      return 1
    fi
  done
  
  return 0
}

retry_with_backoff() {
  local max_attempts=${MAX_RETRIES:-3}
  if [[ $max_attempts -eq -1 ]]; then
    max_attempts=3
  fi
  
  RETRY_COUNT=0
  BACKOFF_DELAY=$INITIAL_BACKOFF
  
  while true; do
    log_info "Attempt $((RETRY_COUNT + 1))/$max_attempts..."
    
    if run_health_checks; then
      log_success "All health checks passed!"
      return 0
    fi
    
    ((RETRY_COUNT++))
    
    if [[ $RETRY_COUNT -ge $max_attempts ]]; then
      log_error "All retry attempts exhausted ($max_attempts attempts)"
      return 1
    fi
    
    log_warn "Health check failed. Retrying in ${BACKOFF_DELAY}s..."
    sleep "$BACKOFF_DELAY"
    
    # Exponential backoff: delay *= 2, max MAX_BACKOFF
    BACKOFF_DELAY=$((BACKOFF_DELAY * 2))
    if [[ $BACKOFF_DELAY -gt $MAX_BACKOFF ]]; then
      BACKOFF_DELAY=$MAX_BACKOFF
    fi
  done
}

################################################################################
# Alerting Functions
################################################################################

create_github_issue_on_failure() {
  if command -v gh &>/dev/null; then
    log_warn "Creating GitHub issue for cluster connectivity failure..."
    
    local issue_body="## Cluster Health Check Failure

**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Cluster**: $CLUSTER_NAME
**Region**: $REGION
**Project**: $PROJECT_ID

### Issue
Kubernetes cluster failed health checks after $RETRY_COUNT retry attempts.

### Checks Performed
- gcloud authentication
- Cluster existence
- Cluster status (RUNNING)
- Control plane health
- API server connectivity
- Core namespaces
- DNS service
- Node readiness
- Network connectivity

### Remediation Steps
1. Check cluster status: \`gcloud container clusters describe $CLUSTER_NAME --region $REGION\`
2. Review firewall rules
3. Check GCP service quotas
4. Review recent cluster events
5. Contact GCP support if issues persist

### Log File
See \`$LOG_FILE\` for detailed output.

---
*Automated health check alert*"
    
    gh issue create \
      --repo kushin77/self-hosted-runner \
      --title "🔴 Kubernetes Cluster Health Check Failure ($CLUSTER_NAME)" \
      --body "$issue_body" \
      --label "infrastructure" \
      --label "alert" \
      --label "kubernetes" 2>/dev/null || log_warn "Failed to create GitHub issue"
  fi
}

################################################################################
# Output Functions
################################################################################

generate_json_report() {
  local status="$1"
  local report_file="$LOG_DIR/health-report-$(date +%Y%m%d_%H%M%S).json"
  
  cat > "$report_file" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cluster": "$CLUSTER_NAME",
  "region": "$REGION",
  "project": "$PROJECT_ID",
  "status": "$status",
  "retry_count": $RETRY_COUNT,
  "backoff_delay": $BACKOFF_DELAY,
  "log_file": "$LOG_FILE"
}
EOF
  
  echo "$report_file"
}

################################################################################
# Main Execution
################################################################################

main() {
  log_info "=== Kubernetes Cluster Health Check ==="
  log_info "Cluster: $CLUSTER_NAME | Region: $REGION | Project: $PROJECT_ID"
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --verbose)
        VERBOSE=true
        shift
        ;;
      --max-retries)
        MAX_RETRIES="$2"
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  
  if retry_with_backoff; then
    log_success "Cluster is healthy and ready for deployment"
    generate_json_report "healthy"
    exit 0
  else
    log_error "Cluster health check FAILED"
    generate_json_report "unhealthy"
    create_github_issue_on_failure
    exit 1
  fi
}

# Execute main
main "$@"
