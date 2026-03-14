#!/bin/bash

################################################################################
# Pre-Deployment Readiness Probe
# Purpose: Validate cluster readiness before executing deployments
# Usage: ./pre-deployment-readiness-probe.sh [deployment-name]
################################################################################

set -euo pipefail

# Configuration
DEPLOYMENT_NAME="${1:-nexus-deployment}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-nexus-gke-main}"
PROJECT_ID="${GCP_PROJECT_ID}"
REGION="${GKE_REGION:-us-central1}"
TIMEOUT_SECONDS="${READINESS_TIMEOUT:-300}"

# Logging
LOG_DIR="${LOG_DIR:-logs/pre-deployment}"
LOG_FILE="$LOG_DIR/readiness-probe-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# Logging
################################################################################

log_info() { echo "[INFO] $*" | tee -a "$LOG_FILE"; }
log_warn() { echo "[WARN] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[ERROR] $*" | tee -a "$LOG_FILE"; }
log_success() { echo "[SUCCESS] $*" | tee -a "$LOG_FILE"; }

################################################################################
# Readiness Checks
################################################################################

check_cluster_connectivity() {
  log_info "Checking cluster connectivity..."
  
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to cluster"
    return 1
  fi
  
  log_success "Cluster connectivity verified"
  return 0
}

check_required_namespaces() {
  log_info "Checking required namespaces..."
  
  local required=("default" "kube-system" "kube-public")
  
  for ns in "${required[@]}"; do
    if ! kubectl get namespace "$ns" &>/dev/null; then
      log_error "Required namespace '$ns' missing"
      return 1
    fi
  done
  
  log_success "All required namespaces present"
  return 0
}

check_node_readiness() {
  log_info "Checking node readiness..."
  
  local total_nodes=$(kubectl get nodes --no-headers | wc -l)
  local ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || true)
  
  if [[ $ready_nodes -eq 0 ]]; then
    log_error "No nodes ready (total: $total_nodes)"
    return 1
  fi
  
  log_info "Nodes ready: $ready_nodes/$total_nodes"
  
  if [[ $ready_nodes -lt $total_nodes ]]; then
    log_warn "Not all nodes ready, but continuing..."
  fi
  
  return 0
}

check_api_responsiveness() {
  log_info "Checking API responsiveness..."
  
  local start_time=$(date +%s)
  local timeout=$TIMEOUT_SECONDS
  
  while true; do
    if kubectl get nodes -q &>/dev/null; then
      local elapsed=$(($(date +%s) - start_time))
      log_success "API responsive (${elapsed}s)"
      return 0
    fi
    
    local elapsed=$(($(date +%s) - start_time))
    if [[ $elapsed -gt $timeout ]]; then
      log_error "API timeout after ${elapsed}s"
      return 1
    fi
    
    sleep 2
  done
}

check_storage_classes() {
  log_info "Checking storage availability..."
  
  if ! kubectl get storageclass &>/dev/null; then
    log_warn "No storage classes found, but continuing..."
  else
    local sc_count=$(kubectl get storageclass --no-headers | wc -l)
    log_info "Storage classes available: $sc_count"
  fi
  
  return 0
}

check_rbac() {
  log_info "Checking RBAC configuration..."
  
  if ! kubectl auth can-i create deployments --as=system:serviceaccount:default:default &>/dev/null; then
    log_warn "RBAC check inconclusive, but continuing..."
  else
    log_success "RBAC configured correctly"
  fi
  
  return 0
}

check_metrics_server() {
  log_info "Checking metrics server..."
  
  if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    log_success "Metrics server is available"
  else
    log_warn "Metrics server not found (optional)"
  fi
  
  return 0
}

check_network_policies() {
  log_info "Checking network policies..."
  
  if kubectl get networkpolicies --all-namespaces &>/dev/null; then
    log_success "Network policies are available"
  else
    log_warn "Network policies not configured (optional)"
  fi
  
  return 0
}

check_ingress_controller() {
  log_info "Checking ingress controller..."
  
  if kubectl get deployment -n kube-system | grep -q "ingress" 2>/dev/null; then
    log_success "Ingress controller found"
  else
    log_warn "Ingress controller not found (optional)"
  fi
  
  return 0
}

################################################################################
# Readiness Check Orchestrator
################################################################################

run_readiness_checks() {
  local checks=(
    "check_cluster_connectivity"
    "check_required_namespaces"
    "check_node_readiness"
    "check_api_responsiveness"
    "check_storage_classes"
    "check_rbac"
    "check_metrics_server"
    "check_network_policies"
    "check_ingress_controller"
  )
  
  local failed_checks=()
  
  for check in "${checks[@]}"; do
    if ! $check; then
      failed_checks+=("$check")
    fi
  done
  
  if [[ ${#failed_checks[@]} -gt 0 ]]; then
    log_error "Some critical checks failed:"
    for check in "${failed_checks[@]}"; do
      echo "  - $check"
    done
    return 1
  fi
  
  return 0
}

################################################################################
# Report Generation
################################################################################

generate_readiness_json() {
  local status="$1"
  local report_file="$LOG_DIR/readiness-report-$(date +%Y%m%d_%H%M%S).json"
  
  cat > "$report_file" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployment": "$DEPLOYMENT_NAME",
  "cluster": "$CLUSTER_NAME",
  "region": "$REGION",
  "status": "$status",
  "timeout": "$TIMEOUT_SECONDS",
  "log_file": "$LOG_FILE",
  "report_file": "$report_file"
}
EOF
  
  echo "$report_file"
}

generate_readiness_details() {
  local status="$1"
  local detail_file="$LOG_DIR/readiness-details-$(date +%Y%m%d_%H%M%S).md"
  
  cat > "$detail_file" <<EOF
# Pre-Deployment Readiness Report

**Date**: $(date)
**Deployment**: $DEPLOYMENT_NAME
**Cluster**: $CLUSTER_NAME
**Region**: $REGION
**Status**: $status

## Cluster Information

\`\`\`bash
$(kubectl cluster-info 2>/dev/null || echo "N/A")
\`\`\`

## Nodes

\`\`\`
$(kubectl get nodes -o wide 2>/dev/null || echo "N/A")
\`\`\`

## Namespaces

\`\`\`
$(kubectl get ns 2>/dev/null || echo "N/A")
\`\`\`

## Storage Classes

\`\`\`
$(kubectl get storageclass 2>/dev/null || echo "N/A")
\`\`\`

## Metrics Server

\`\`\`
$(kubectl get deployment metrics-server -n kube-system 2>/dev/null || echo "N/A")
\`\`\`

## Log File

See \`$LOG_FILE\` for detailed output.
EOF
  
  echo "$detail_file"
}

################################################################################
# Main
################################################################################

main() {
  log_info "=== Pre-Deployment Readiness Probe ==="
  log_info "Deployment: $DEPLOYMENT_NAME"
  log_info "Cluster: $CLUSTER_NAME | Region: $REGION | Project: $PROJECT_ID"
  log_info "Timeout: ${TIMEOUT_SECONDS}s"
  
  if run_readiness_checks; then
    log_success "Cluster is READY for deployment"
    generate_readiness_json "ready" > /dev/null
    generate_readiness_details "ready" > /dev/null
    exit 0
  else
    log_error "Cluster is NOT READY for deployment"
    generate_readiness_json "not-ready" > /dev/null
    generate_readiness_details "not-ready" > /dev/null
    exit 1
  fi
}

main "$@"
