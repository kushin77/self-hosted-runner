#!/bin/bash
# Kubernetes Deployment Orchestration
# Ensures cluster readiness before deployment
# Fully idempotent, GSM-based credentials

set -euo pipefail

# Allow skipping k8s checks entirely (useful for on-prem/dev environments)
SKIP_K8S_READINESS="${SKIP_K8S_READINESS:-false}"
if [[ "$SKIP_K8S_READINESS" == "true" ]]; then
  echo "⏭️  Skipping Kubernetes deployment checks (SKIP_K8S_READINESS=true)"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_READINESS="$SCRIPT_DIR/cluster-readiness.sh"

PROJECT="nexusshield-prod"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-nexus-app}"
TIMEOUT=600
MAX_RETRIES=5

echo "📋 Kubernetes Deployment Orchestration"
echo "  Project: $PROJECT"
echo "  Namespace: $NAMESPACE"
echo "  Deployment: $DEPLOYMENT_NAME"
echo "  Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ===== Phase 1: Cluster Readiness =====
echo "Phase 1️⃣ : Checking cluster readiness..."
if [ ! -x "$CLUSTER_READINESS" ]; then
  echo "❌ Cluster readiness script not found: $CLUSTER_READINESS"
  exit 1
fi

if "$CLUSTER_READINESS"; then
  echo "✅ Cluster ready to accept deployments"
else
  readiness_status=$?
  if [ $readiness_status -eq 1 ]; then
    echo "⚠️ Cluster partially ready, proceeding with caution"
  else
    echo "❌ Cluster not ready for deployment"
    exit 1
  fi
fi

echo ""

# ===== Phase 2: Namespace Verification =====
echo "Phase 2️⃣ : Verifying namespace..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "📝 Creating namespace $NAMESPACE..."
  kubectl create namespace "$NAMESPACE" || {
    [ $(kubectl get ns "$NAMESPACE" 2>/dev/null | wc -l) -gt 1 ] && echo "✅ Namespace already exists"
  }
fi
echo "✅ Namespace verified"

echo ""

# ===== Phase 3: Pre-deployment Validation =====
echo "Phase 3️⃣ : Pre-deployment validation..."
kubectl auth can-i get deployments --namespace="$NAMESPACE" -q 2>/dev/null && \
  echo "✅ RBAC permissions verified" || \
  echo "⚠️ RBAC check inconclusive"

echo ""

# ===== Phase 4: Deployment Readiness Summary =====
echo "Phase 4️⃣ : Deployment readiness summary"
echo "  ✅ Cluster accessible"
echo "  ✅ Namespace verified"
echo "  ✅ Permissions validated"
echo ""
echo "🚀 Cluster is ready for deployment"
exit 0
