#!/bin/bash
# Kubernetes Cluster Readiness Probe
# Ensures cluster is fully operational with health checks
# Fully idempotent, GSM-based credentials, no manual ops

set -euo pipefail

PROJECT="nexusshield-prod"
CLUSTER="nexus-prod-gke"
ZONE="us-central1-a"
TIMEOUT=300
RETRY_COUNT=5
RETRY_DELAY=10

# ===== 1. Credential Management (GSM Only) =====
get_cred() {
  local secret=$1
  gcloud secrets versions access latest --secret="$secret" --project="$PROJECT" 2>/dev/null || echo ""
}

# ===== 2. Cluster Connectivity Check =====
check_cluster_accessible() {
  local max_attempts=5
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
      echo "✅ Cluster accessible"
      return 0
    fi
    echo "⏳ Cluster check attempt $((attempt+1))/$max_attempts"
    sleep $RETRY_DELAY
    ((attempt++))
  done
  
  echo "❌ Cluster not accessible after $max_attempts attempts"
  return 1
}

# ===== 3. API Server Health =====
check_api_server() {
  if kubectl cluster-info 2>/dev/null | grep -q "Kubernetes master"; then
    echo "✅ API Server healthy"
    return 0
  fi
  echo "⚠️ API Server health check inconclusive"
  return 1
}

# ===== 4. Node Readiness =====
check_nodes_ready() {
  local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
  local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
  
  if [ "$total_nodes" -gt 0 ] && [ "$ready_nodes" -gt 0 ]; then
    echo "✅ Nodes ready: $ready_nodes/$total_nodes"
    return 0
  fi
  echo "⚠️ Nodes not ready: $ready_nodes/$total_nodes"
  return 1
}

# ===== 5. Core Namespaces  =====
check_namespaces() {
  for ns in default kube-system kube-public; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      echo "✅ Namespace $ns exists"
    else
      echo "⚠️ Namespace $ns missing"
      return 1
    fi
  done
  return 0
}

# ===== 6. System Pods Status =====
check_system_pods() {
  local check_ns="kube-system"
  local running=$(kubectl get pods -n "$check_ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
  
  if [ "$running" -gt 0 ]; then
    echo "✅ System pods running: $running"
    return 0
  fi
  echo "⚠️ No running system pods detected"
  return 1
}

# ===== MAIN READINESS CHECK =====
main() {
  echo "🔍 Kubernetes Cluster Readiness Check"
  echo "  Cluster: $CLUSTER (Zone: $ZONE)"
  echo "  Project: $PROJECT"
  echo "  Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  
  local checks_passed=0
  local checks_total=6
  
  check_cluster_accessible && ((checks_passed++)) || true
  check_api_server && ((checks_passed++)) || true
  check_nodes_ready && ((checks_passed++)) || true
  check_namespaces && ((checks_passed++)) || true
  check_system_pods && ((checks_passed++)) || true
  
  echo ""
  echo "📊 Results: $checks_passed/$checks_total checks passed"
  
  if [ $checks_passed -eq $checks_total ]; then
    echo "✅ Cluster fully ready"
    return 0
  elif [ $checks_passed -ge 3 ]; then
    echo "⚠️ Cluster partially ready"
    return 1
  else
    echo "❌ Cluster not ready"
    return 2
  fi
}

main "$@"
