#!/usr/bin/env bash
# Configure monitoring endpoints for the triage service
# This script sets up GCP Cloud Monitoring as fallback endpoints

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Log function
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [MON-CONFIG] $*" >&2
}

log_success() {
  echo "✅ $*" >&2
}

# Get GCP project ID
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || echo nexusshield-prod)"
GCP_REGION=${GCP_REGION:-us-central1}

log "Configuring monitoring endpoints for project: $PROJECT_ID"

# Store Cloud Monitoring API endpoint in GSM if credentials available
configure_gcp_monitoring() {
  log "Configuring GCP Cloud Monitoring endpoints..."
  
  local prom_endpoint="https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/timeSeries"
  local am_endpoint="https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/alertPolicies"
  
  log "Primary endpoints configured to use Cloud Monitoring APIs"
  
  # Update environment variables for monitoring service
  cat > "$REPO_ROOT/scripts/utilities/monitoring-endpoints.env" << EOF
# Auto-generated monitoring endpoints configuration
PROM_URL="$prom_endpoint"
AM_URL="$am_endpoint"
MONITORING_ENDPOINTS_CONFIGURED=true
MONITORING_TYPE=gcp-cloud-monitoring
EOF
  
  log_success "Monitoring endpoints stored in scripts/utilities/monitoring-endpoints.env"
}

# Configure Kubernetes monitoring if cluster is available
configure_k8s_monitoring() {
  log "Checking for Kubernetes clusters..."
  
  local clusters
  clusters="$(gcloud container clusters list --project="$PROJECT_ID" --format='value(name, location)' 2>/dev/null | head -1)" || true
  
  if [ -n "$clusters" ]; then
    local cluster_name zone
    read -r cluster_name zone <<< "$clusters"
    log "Kubernetes cluster found: $cluster_name in $zone"
    
    # Configure kubectl access
    if ! gcloud container clusters get-credentials "$cluster_name" --zone="$zone" --project="$PROJECT_ID" 2>&1 | grep -q "ERROR"; then
      log_success "kubectl configured for cluster: $cluster_name"
      
      # Check if Prometheus is deployed in the cluster
      if kubectl get ns prometheus 2>/dev/null; then
        local prom_svc
        prom_svc="$(kubectl -n prometheus get svc prometheus -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" || true
        if [ -n "$prom_svc" ]; then
          log_success "Prometheus found at: http://$prom_svc:9090"
          echo "PROM_URL=http://$prom_svc:9090" >> "$REPO_ROOT/scripts/utilities/monitoring-endpoints.env"
        fi
      fi
    fi
  fi
}

# Main
main() {
  log "Starting monitoring endpoint configuration..."
  
  configure_gcp_monitoring
  configure_k8s_monitoring
  
  log_success "Monitoring endpoints configuration completed"
  
  # Output configured endpoints
  echo ""
  log "Current monitoring configuration:"
  if [ -f "$REPO_ROOT/scripts/utilities/monitoring-endpoints.env" ]; then
    cat "$REPO_ROOT/scripts/utilities/monitoring-endpoints.env"
  fi
}

main "$@"
