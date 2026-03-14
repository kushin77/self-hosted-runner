#!/bin/bash
set -e

# Enable Horizontal Pod Autoscaling for SSO Platform
# Configures HPA for Keycloak and OAuth2-Proxy based on CPU/Memory metrics

KEYCLOAK_MIN_REPLICAS="${1:-2}"
KEYCLOAK_MAX_REPLICAS="${2:-10}"
OAUTH2_MIN_REPLICAS="${3:-2}"
OAUTH2_MAX_REPLICAS="${4:-8}"
CPU_THRESHOLD="${5:-70}"
MEMORY_THRESHOLD="${6:-80}"

echo "📈 Configuring Horizontal Pod Autoscaling for SSO Platform"
echo "   Keycloak replicas: $KEYCLOAK_MIN_REPLICAS-$KEYCLOAK_MAX_REPLICAS"
echo "   OAuth2-Proxy replicas: $OAUTH2_MIN_REPLICAS-$OAUTH2_MAX_REPLICAS"
echo "   CPU threshold: ${CPU_THRESHOLD}%"
echo "   Memory threshold: ${MEMORY_THRESHOLD}%"
echo ""

# Check if metrics-server is running
echo "✔️  Checking for metrics-server..."
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
  echo "   ✅ Metrics-server is running"
else
  echo "   ⚠️  Metrics-server not found. Attempting to install..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.6.4/components.yaml
  echo "   ✅ Metrics-server installed"
fi

# Wait for metrics to be available
echo "⏳ Waiting for metrics-server to become ready..."
kubectl rollout status deployment/metrics-server -n kube-system --timeout=300s || {
  echo "⚠️  Metrics-server may take a few minutes to start collecting metrics"
}

# Create HPA for Keycloak
echo "⚙️  Configuring Keycloak autoscaling..."
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: keycloak-hpa
  namespace: keycloak
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: keycloak
  minReplicas: $KEYCLOAK_MIN_REPLICAS
  maxReplicas: $KEYCLOAK_MAX_REPLICAS
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: $CPU_THRESHOLD
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: $MEMORY_THRESHOLD
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
      - type: Pods
        value: 1
        periodSeconds: 60
      selectPolicy: Min
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
EOF
echo "   ✅ Keycloak HPA configured"

# Create HPA for OAuth2-Proxy
echo "⚙️  Configuring OAuth2-Proxy autoscaling..."
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: oauth2-proxy-hpa
  namespace: oauth2-proxy
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: oauth2-proxy
  minReplicas: $OAUTH2_MIN_REPLICAS
  maxReplicas: $OAUTH2_MAX_REPLICAS
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: $CPU_THRESHOLD
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: $MEMORY_THRESHOLD
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
      selectPolicy: Min
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 50
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
EOF
echo "   ✅ OAuth2-Proxy HPA configured"

# Verify HPAs
echo ""
echo "📊 Verifying autoscaling configuration..."
kubectl get hpa -n keycloak
kubectl get hpa -n oauth2-proxy

echo ""
echo "✅ Autoscaling enablement complete!"
echo ""
echo "📝 Monitoring autoscaling:"
echo "   # Watch Keycloak HPA status"
echo "   kubectl get hpa -n keycloak -w"
echo ""
echo "   # Watch scaling events"
echo "   kubectl describe hpa keycloak-hpa -n keycloak"
echo ""
echo "   # View current metrics for Keycloak pods"
echo "   kubectl top pods -n keycloak"
echo ""
echo "⚠️  Note: Metrics take ~1-2 minutes to stabilize after deployment"
