#!/bin/bash
# Kubernetes Health Check Monitoring Integration
# Exports health check results to monitoring systems
# Supports Prometheus, Cloud Monitoring, and custom HTTP endpoints

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_READINESS="$SCRIPT_DIR/cluster-readiness.sh"

PROJECT="${PROJECT:-nexusshield-prod}"
CLUSTER="${CLUSTER:-nexus-prod-gke}"
ZONE="${ZONE:-us-central1-a}"

# Monitoring endpoints (configure via environment variables)
PROMETHEUS_ENDPOINT="${PROMETHEUS_ENDPOINT:-}"
STACKDRIVER_ENABLED="${STACKDRIVER_ENABLED:-true}"
CUSTOM_ENDPOINT="${CUSTOM_ENDPOINT:-}"

# ===== Run Health Check =====
echo "🔍 Running health check..."
HEALTH_OUTPUT=$("$CLUSTER_READINESS" 2>&1)
HEALTH_STATUS=$?

# Extract metrics from output
CLUSTER_ACCESSIBLE=$(echo "$HEALTH_OUTPUT" | grep -q "Cluster accessible" && echo "1" || echo "0")
API_SERVER_HEALTHY=$(echo "$HEALTH_OUTPUT" | grep -q "API Server healthy" && echo "1" || echo "0")
NODES_READY=$(echo "$HEALTH_OUTPUT" | grep -oP "Nodes ready: \K\d+" | head -1 || echo "0")
SYSTEM_PODS=$(echo "$HEALTH_OUTPUT" | grep -oP "System pods running: \K\d+" | head -1 || echo "0")

TIMESTAMP=$(date -u +%s)
ISO_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "✅ Health check complete: Exit code $HEALTH_STATUS"
echo ""

# ===== Export to Prometheus Pushgateway =====
if [ -n "$PROMETHEUS_ENDPOINT" ]; then
  echo "📊 Pushing metrics to Prometheus Pushgateway..."
  
  METRICS=$(cat <<EOF
# HELP k8s_cluster_accessible Cluster is accessible and responsive
# TYPE k8s_cluster_accessible gauge
k8s_cluster_accessible{cluster="$CLUSTER",zone="$ZONE",project="$PROJECT"} $CLUSTER_ACCESSIBLE

# HELP k8s_api_server_healthy API server is healthy
# TYPE k8s_api_server_healthy gauge
k8s_api_server_healthy{cluster="$CLUSTER",zone="$ZONE",project="$PROJECT"} $API_SERVER_HEALTHY

# HELP k8s_nodes_available Number of available nodes
# TYPE k8s_nodes_available gauge
k8s_nodes_available{cluster="$CLUSTER",zone="$ZONE",project="$PROJECT"} $NODES_READY

# HELP k8s_system_pods_running Number of system pods running
# TYPE k8s_system_pods_running gauge
k8s_system_pods_running{cluster="$CLUSTER",zone="$ZONE",project="$PROJECT"} $SYSTEM_PODS

# HELP k8s_health_check_exit_code Exit code of last health check
# TYPE k8s_health_check_exit_code gauge
k8s_health_check_exit_code{cluster="$CLUSTER",zone="$ZONE",project="$PROJECT"} $HEALTH_STATUS

# HELP k8s_health_check_timestamp Unix timestamp of last health check
# TYPE k8s_health_check_timestamp gauge
k8s_health_check_timestamp{cluster="$CLUSTER",zone="$ZONE",project="$PROJECT"} $TIMESTAMP
EOF
)
  
  echo "$METRICS" | curl -X POST --data-binary @- \
    "$PROMETHEUS_ENDPOINT/metrics/job/k8s-health-check/instance/$CLUSTER" \
    -H "Content-Type: text/plain; version=0.0.4" \
    2>/dev/null && echo "✅ Prometheus metrics pushed" || echo "⚠️ Prometheus push failed"
fi

echo ""

# ===== Export to Google Cloud Monitoring =====
if [ "$STACKDRIVER_ENABLED" = "true" ]; then
  echo "📈 Pushing metrics to Cloud Monitoring..."
  
  gcloud monitoring time-series create \
    --type="custom.googleapis.com/k8s/health_check" \
    --metric-labels="cluster=$CLUSTER,zone=$ZONE" \
    --resource-type="global" \
    --value="$HEALTH_STATUS" \
    --project="$PROJECT" \
    2>/dev/null && echo "✅ Cloud Monitoring metrics pushed" || echo "⚠️ Cloud Monitoring push failed"
fi

echo ""

# ===== Export to Custom Endpoint =====
if [ -n "$CUSTOM_ENDPOINT" ]; then
  echo "🔗 Sending metrics to custom endpoint..."
  
  CUSTOM_PAYLOAD=$(cat <<EOF
{
  "timestamp": "$ISO_TIMESTAMP",
  "cluster": "$CLUSTER",
  "zone": "$ZONE",
  "project": "$PROJECT",
  "status": $([ $HEALTH_STATUS -eq 0 ] && echo '"ready"' || echo '"degraded"'),
  "health_status_code": $HEALTH_STATUS,
  "metrics": {
    "cluster_accessible": $CLUSTER_ACCESSIBLE,
    "api_server_healthy": $API_SERVER_HEALTHY,
    "nodes_available": $NODES_READY,
    "system_pods_running": $SYSTEM_PODS
  }
}
EOF
)
  
  curl -X POST "$CUSTOM_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$CUSTOM_PAYLOAD" \
    2>/dev/null && echo "✅ Custom endpoint metrics sent" || echo "⚠️ Custom endpoint push failed"
fi

echo ""
echo "✅ Monitoring export complete"
exit 0
