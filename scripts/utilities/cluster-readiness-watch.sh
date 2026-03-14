#!/usr/bin/env bash
set -euo pipefail

# Cluster Readiness Watch & Auto-deployment Automation
# Purpose: Monitor GKE cluster provisioning and auto-deploy monitoring stack
# Constraints: Immutable, ephemeral, idempotent, GSM for all credentials, no manual ops

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration from environment/GSM
PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
GKE_CLUSTER="${GKE_CLUSTER:-nexus-prod-gke}"
GKE_ZONE="${GKE_ZONE:-us-central1-a}"
K8S_NAMESPACE="${K8S_NAMESPACE:-nexus-discovery}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"
MAX_WAIT_MINUTES="${MAX_WAIT_MINUTES:-30}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"

# State tracking
STATE_DIR="${REPO_ROOT}/logs/cluster-readiness"
STATUS_FILE="$STATE_DIR/cluster-readiness.status"
DEPLOYMENT_LOG="$STATE_DIR/deployment.log"

# Logging functions
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [CLUSTER-WATCH] $*" | tee -a "$DEPLOYMENT_LOG"
}

log_success() {
  echo "✅ $*" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
  echo "❌ $*" | tee -a "$DEPLOYMENT_LOG"
  return 1
}

# Initialize
initialize() {
  mkdir -p "$STATE_DIR"
  
  # Create initial status file
  cat > "$STATUS_FILE" << EOF
timestamp_start=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
cluster_name=$GKE_CLUSTER
cluster_zone=$GKE_ZONE
project_id=$PROJECT_ID
status=initializing
message=cluster readiness watch started
EOF

  log "Cluster readiness watch initialized"
  log "Project: $PROJECT_ID | Cluster: $GKE_CLUSTER | Zone: $GKE_ZONE"
}

# Poll cluster status
poll_cluster_status() {
  local cluster_info
  cluster_info="$(gcloud container clusters describe "$GKE_CLUSTER" \
    --zone="$GKE_ZONE" \
    --project="$PROJECT_ID" \
    --format='value(status,currentNodeCount,currentMasterVersion)' 2>/dev/null)" || {
    return 1
  }
  
  echo "$cluster_info"
}

# Wait for cluster to become RUNNING
wait_for_cluster() {
  local start_time
  start_time=$(date +%s)
  local max_wait_sec=$((MAX_WAIT_MINUTES * 60))
  
  log "Polling for cluster status (max wait: ${MAX_WAIT_MINUTES} minutes)..."
  
  while true; do
    local elapsed_sec
    elapsed_sec=$(($(date +%s) - start_time))
    
    if [ $elapsed_sec -gt $max_wait_sec ]; then
      log_error "Cluster provisioning timeout after ${MAX_WAIT_MINUTES} minutes"
      return 1
    fi
    
    local status node_count version
    read -r status node_count version <<< "$(poll_cluster_status)" 2>/dev/null || {
      local elapsed_min=$((elapsed_sec / 60))
      log "Cluster info unavailable (${elapsed_min}m elapsed)... retrying in ${POLL_INTERVAL}s"
      sleep "$POLL_INTERVAL"
      continue
    }
    
    local elapsed_min=$((elapsed_sec / 60))
    log "Status: $status | Nodes: $node_count | Kubernetes: $version (${elapsed_min}m elapsed)"
    
    if [ "$status" = "RUNNING" ]; then
      log_success "Cluster is RUNNING after ${elapsed_min} minutes"
      return 0
    fi
    
    sleep "$POLL_INTERVAL"
  done
}

# Get kubectl credentials
configure_kubectl() {
  log "Configuring kubectl access to cluster..."
  
  gcloud container clusters get-credentials "$GKE_CLUSTER" \
    --zone="$GKE_ZONE" \
    --project="$PROJECT_ID" 2>&1 | grep -v "WARNING" || true
  
  # Verify kubectl access
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Failed to configure kubectl access"
    return 1
  fi
  
  log_success "kubectl configured successfully"
}

# Create monitoring namespace
create_monitoring_namespace() {
  log "Creating monitoring namespace..."
  
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - || true
  
  # Add labels
  kubectl label namespace monitoring \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite 2>/dev/null || true
  
  log_success "Monitoring namespace ready"
}

# Deploy Prometheus to cluster
deploy_prometheus() {
  log "Deploying Prometheus to cluster..."
  
  # Create ConfigMap from local Prometheus config
  kubectl create configmap prometheus-config \
    --from-file="$REPO_ROOT/monitoring/prometheus.yml" \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f - || true
  
  # Create Prometheus deployment
  cat > /tmp/prometheus-deployment.yaml << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 9090
          name: http
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
        args:
        - "--config.file=/etc/prometheus/prometheus.yml"
        - "--storage.tsdb.path=/prometheus"
        - "--storage.tsdb.retention.time=7d"
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: 9090
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  type: ClusterIP
  ports:
  - port: 9090
    targetPort: 9090
    name: http
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
YAML
  
  kubectl apply -f /tmp/prometheus-deployment.yaml || {
    log_error "Failed to deploy Prometheus"
    return 1
  }
  
  # Wait for Prometheus to be ready
  log "Waiting for Prometheus deployment to become ready..."
  if kubectl rollout status deployment/prometheus -n monitoring --timeout=300s 2>&1 | grep -q "successfully"; then
    log_success "Prometheus deployed and ready"
  else
    log_error "Prometheus deployment failed to reach ready state"
    return 1
  fi
}

# Deploy Alertmanager to cluster
deploy_alertmanager() {
  log "Deploying Alertmanager to cluster..."
  
  # Create ConfigMap from local Alertmanager config
  kubectl create configmap alertmanager-config \
    --from-file="$REPO_ROOT/monitoring/alertmanager/alertmanager.yml" \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f - || true
  
  # Create Alertmanager deployment
  cat > /tmp/alertmanager-deployment.yaml << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      serviceAccountName: alertmanager
      containers:
      - name: alertmanager
        image: prom/alertmanager:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 9093
          name: http
        volumeMounts:
        - name: config
          mountPath: /etc/alertmanager
        - name: storage
          mountPath: /alertmanager
        args:
        - "--config.file=/etc/alertmanager/alertmanager.yml"
        - "--storage.path=/alertmanager"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 200m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: 9093
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: config
        configMap:
          name: alertmanager-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  selector:
    app: alertmanager
  type: ClusterIP
  ports:
  - port: 9093
    targetPort: 9093
    name: http
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: alertmanager
  namespace: monitoring
YAML
  
  kubectl apply -f /tmp/alertmanager-deployment.yaml || {
    log_error "Failed to deploy Alertmanager"
    return 1
  }
  
  # Wait for Alertmanager to be ready
  log "Waiting for Alertmanager deployment to become ready..."
  if kubectl rollout status deployment/alertmanager -n monitoring --timeout=300s 2>&1 | grep -q "successfully"; then
    log_success "Alertmanager deployed and ready"
  else
    log_error "Alertmanager deployment failed to reach ready state"
    return 1
  fi
}

# Update monitoring endpoints configuration
update_monitoring_endpoints() {
  log "Updating monitoring endpoints configuration..."
  
  # Get Prometheus service cluster IP
  local prom_ip
  prom_ip="$(kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" || {
    log_error "Failed to get Prometheus service IP"
    return 1
  }
  
  local am_ip
  am_ip="$(kubectl get svc alertmanager -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" || {
    log_error "Failed to get Alertmanager service IP"
    return 1
  }
  
  # Update endpoints configuration
  cat > "$REPO_ROOT/scripts/utilities/monitoring-endpoints.env" << EOF
# Auto-generated monitoring endpoints (cluster deployed)
PROM_URL="http://$prom_ip:9090"
AM_URL="http://$am_ip:9093"
MONITORING_ENDPOINTS_CONFIGURED=true
MONITORING_TYPE=kubernetes-cluster
MONITORING_NAMESPACE=monitoring
CLUSTER_NAME=$GKE_CLUSTER
EOF
  
  log_success "Monitoring endpoints updated: Prometheus=$prom_ip:9090, Alertmanager=$am_ip:9093"
}

# Update status and create GitHub issue
finalize_deployment() {
  log "Finalizing deployment and updating tracking..."
  
  # Update status file
  cat > "$STATUS_FILE" << EOF
timestamp_start=$(head -1 "$STATUS_FILE" | cut -d= -f2)
timestamp_complete=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
cluster_name=$GKE_CLUSTER
cluster_zone=$GKE_ZONE
project_id=$PROJECT_ID
status=complete
message=cluster readiness watch and monitoring deployment complete
prometheus_url=http://$(kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null):9090
alertmanager_url=http://$(kubectl get svc alertmanager -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null):9093
EOF
  
  log_success "Deployment complete. Monitoring endpoints operational."
  log_success "See $DEPLOYMENT_LOG for full execution log"
}

# Create GitHub issue for tracking
create_github_issue() {
  log "Creating GitHub tracking issue..."
  
  local prom_url am_url
  prom_url="$(grep "prometheus_url" "$STATUS_FILE" | cut -d= -f2)"
  am_url="$(grep "alertmanager_url" "$STATUS_FILE" | cut -d= -f2)"
  
  cat > /tmp/cluster_readiness_issue.md << EOF
# ✅ Cluster Readiness: Monitoring Deployment Complete

**Status**: COMPLETE  
**Cluster**: $GKE_CLUSTER  
**Zone**: $GKE_ZONE  
**Project**: $PROJECT_ID  
**Completed**: $(grep "timestamp_complete" "$STATUS_FILE" | cut -d= -f2)

## Deployment Artifacts

- **Prometheus Endpoint**: $prom_url
- **Alertmanager Endpoint**: $am_url
- **Namespace**: monitoring
- **Deployment Log**: [logs/cluster-readiness/deployment.log](logs/cluster-readiness/deployment.log)

## Deployed Services

✅ Prometheus - Metrics collection and alerting  
✅ Alertmanager - Alert routing and aggregation  
✅ Monitoring Namespace - RBAC and network policies  

## Next Steps

1. Verify metrics ingestion: kubectl logs -n monitoring -l app=prometheus
2. Test alerting: kubectl logs -n monitoring -l app=alertmanager
3. Run triage to confirm operational: ./scripts/utilities/triage_all_phases_one_shot.sh

**Auto-closed by cluster-readiness automation**
EOF
  
  gh issue create \
    --repo "$GITHUB_REPO" \
    --title "✅ Cluster readiness watch: Monitoring stack deployed (automatic)" \
    --body "$(cat /tmp/cluster_readiness_issue.md)" \
    2>&1 | head -5 || true
}

# Main execution
main() {
  log "=== Cluster Readiness Watch & Auto-deployment ==="
  
  initialize
  
  if ! wait_for_cluster; then
    log_error "Cluster did not reach RUNNING state"
    cat > "$STATUS_FILE" << EOF
status=failed
message=cluster provisioning timeout
EOF
    return 1
  fi
  
  if ! configure_kubectl; then
    log_error "kubectl configuration failed"
    return 1
  fi
  
  if ! create_monitoring_namespace; then
    log_error "Monitoring namespace creation failed"
    return 1
  fi
  
  if ! deploy_prometheus; then
    log_error "Prometheus deployment failed"
    return 1
  fi
  
  if ! deploy_alertmanager; then
    log_error "Alertmanager deployment failed"
    return 1
  fi
  
  if ! update_monitoring_endpoints; then
    log_error "Endpoint update failed"
    return 1
  fi
  
  finalize_deployment
  create_github_issue
  
  log_success "Cluster readiness watch and deployment automation successful"
  return 0
}

# Handle cleanup
cleanup() {
  rm -f /tmp/prometheus-deployment.yaml /tmp/alertmanager-deployment.yaml /tmp/cluster_readiness_issue.md
}

trap cleanup EXIT

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
