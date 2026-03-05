#!/usr/bin/env bash
set -euo pipefail

# Run a KEDA smoke test against a cluster using provided kubeconfig.
# Usage:
#   STAGING_KUBECONFIG=/path/to/kubeconfig ./scripts/ci/run-keda-smoke-test.sh
# or
#   export KUBECONFIG=/path/to/kubeconfig && ./scripts/ci/run-keda-smoke-test.sh

KUBE=${STAGING_KUBECONFIG:-${KUBECONFIG:-}}
if [[ -z "$KUBE" ]]; then
  echo "ERROR: set STAGING_KUBECONFIG or KUBECONFIG to point to the cluster kubeconfig" >&2
  exit 2
fi

export KUBECONFIG="$KUBE"

echo "Using kubeconfig: $KUBECONFIG"

# Ensure kubectl exists
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH" >&2
  exit 3
fi

NAMESPACE=${NAMESPACE:-runners}

echo "Creating namespace $NAMESPACE if missing"
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

# Deploy Pushgateway test harness
PUSHGATEWAY_YAML=deploy/autoscaling/test-harness/pushgateway-deployment.yaml
if [[ -f "$PUSHGATEWAY_YAML" ]]; then
  echo "Applying Pushgateway test harness: $PUSHGATEWAY_YAML"
  kubectl apply -f "$PUSHGATEWAY_YAML" -n "$NAMESPACE"
else
  echo "Warning: $PUSHGATEWAY_YAML not found; skipping Pushgateway deployment"
fi

# Wait for Pushgateway to be ready (best-effort)
if kubectl -n "$NAMESPACE" get deploy pushgateway >/dev/null 2>&1; then
  echo "Waiting for pushgateway deployment to be ready..."
  kubectl -n "$NAMESPACE" rollout status deploy/pushgateway --timeout=120s || true
fi

# Generate test metrics if metric generator exists
METRIC_GEN=deploy/autoscaling/test-harness/metric-generator.sh
if [[ -x "$METRIC_GEN" ]]; then
  echo "Running metric generator against Pushgateway"
  PUSHGATEWAY_URL=${PUSHGATEWAY_URL:-http://pushgateway.$NAMESPACE.svc:9091}
  PUSHGATEWAY_URL="$PUSHGATEWAY_URL" "$METRIC_GEN"
else
  echo "Metric generator not found or not executable: $METRIC_GEN"
fi

# Apply sample ScaledObject and runner deployment
SAMPLE_DEPLOY=deploy/autoscaling/sample/github-runner-deployment.yaml
SAMPLE_SCALED=deploy/autoscaling/sample/scaledobject.yaml
if [[ -f "$SAMPLE_DEPLOY" ]]; then
  echo "Applying sample runner deployment"
  kubectl apply -f "$SAMPLE_DEPLOY" -n "$NAMESPACE"
fi
if [[ -f "$SAMPLE_SCALED" ]]; then
  echo "Applying sample ScaledObject"
  kubectl apply -f "$SAMPLE_SCALED" -n "$NAMESPACE"
fi

echo "Observing pods for 60s"
kubectl get pods -n "$NAMESPACE" --watch --no-headers &
WATCH_PID=$!
sleep 60
kill $WATCH_PID || true

cat <<EOF
Smoke test completed. Next steps:
 - Inspect ScaledObject and KEDA operator logs if scaling didn't occur.
 - Run cleanup: kubectl delete -f $SAMPLE_SCALED -f $SAMPLE_DEPLOY -f $PUSHGATEWAY_YAML -n $NAMESPACE
EOF
