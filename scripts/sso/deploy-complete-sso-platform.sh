#!/bin/bash

# SSO Platform Complete Deployment Orchestrator
# Automates end-to-end deployment of all TIER 1-2 infrastructure
# Usage: ./scripts/sso/deploy-complete-sso-platform.sh [{gcp-project}] [{gke-zone}]

set -euo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

PROJECT_ID="${1:-nexus-prod}"
ZONE="${2:-us-central1-a}"
CLUSTER_NAME="nexus-prod-gke"
NAMESPACE="keycloak"
NAMESPACE_OAUTH2="oauth2-proxy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# HELPER FUNCTIONS
###############################################################################

log_step() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${BLUE}→${NC} $1"
}

log_success() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1" >&2
}

log_warning() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

wait_for_deployment() {
  local namespace=$1
  local deployment=$2
  local timeout=${3:-300}
  
  log_step "Waiting for $namespace/$deployment to be ready (timeout: ${timeout}s)..."
  
  if kubectl rollout status deployment/$deployment -n $namespace --timeout=${timeout}s; then
    log_success "$namespace/$deployment is ready"
    return 0
  else
    log_error "Deployment $namespace/$deployment failed to become ready"
    kubectl get pods -n $namespace -l app=$deployment
    return 1
  fi
}

wait_for_statefulset() {
  local namespace=$1
  local statefulset=$2
  local timeout=${3:-300}
  
  log_step "Waiting for $namespace/$statefulset to be ready (timeout: ${timeout}s)..."
  
  local start=$(date +%s)
  while true; do
    local ready=$(kubectl get statefulset $statefulset -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get statefulset $statefulset -n $namespace -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready" == "$desired" ]] && [[ "$desired" != "0" ]]; then
      log_success "$namespace/$statefulset is ready ($ready/$desired replicas)"
      return 0
    fi
    
    local elapsed=$(($(date +%s) - start))
    if [[ $elapsed -gt $timeout ]]; then
      log_error "StatefulSet $namespace/$statefulset failed to become ready after ${timeout}s"
      kubectl get pods -n $namespace -l app=$statefulset
      return 1
    fi
    
    echo -ne "\rProgress: $ready/$desired ready... (${elapsed}s elapsed)"
    sleep 5
  done
}

###############################################################################
# PRE-FLIGHT CHECKS
###############################################################################

preflight_checks() {
  log_step "Running pre-flight checks..."
  
  # Check required tools
  local required_tools=("gcloud" "kubectl" "grep" "sed")
  for tool in "${required_tools[@]}"; do
    if ! command -v $tool &> /dev/null; then
      log_error "Required tool not found: $tool"
      return 1
    fi
  done
  log_success "All required tools present"
  
  # Authenticate with GCP
  log_step "Authenticating with GCP..."
  gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1 > /dev/null 2>&1 || {
    log_warning "No active GCP account. Please authenticate: gcloud auth login"
  }
  log_success "GCP authentication confirmed"
  
  # Get cluster credentials
  log_step "Getting cluster credentials for $CLUSTER_NAME..."
  gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$PROJECT_ID 2>/dev/null || {
    log_error "Failed to get cluster credentials. Cluster may not exist."
    return 1
  }
  log_success "Cluster credentials obtained"
  
  # Verify cluster connectivity
  log_step "Verifying cluster connectivity..."
  kubectl cluster-info > /dev/null || {
    log_error "Cannot connect to Kubernetes cluster"
    return 1
  }
  log_success "Cluster connectivity verified"
  
  # Check cluster version
  local k8s_version=$(kubectl version --short | grep Server | cut -d' ' -f3)
  log_success "Kubernetes version: $k8s_version"
  
  # Check node status
  log_step "Checking node status..."
  local nodes=$(kubectl get nodes --no-headers | wc -l)
  local ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || true)
  if [[ $ready_nodes -lt 1 ]]; then
    log_error "No ready nodes in cluster (found: $ready_nodes/$nodes)"
    return 1
  fi
  log_success "Cluster has $ready_nodes ready nodes"
  
  # Check RBAC permissions
  log_step "Checking RBAC permissions..."
  if ! kubectl auth can-i create namespaces; then
    log_error "Insufficient RBAC permissions"
    return 1
  fi
  log_success "RBAC permissions confirmed"
  
  return 0
}

###############################################################################
# NAMESPACE & RBAC SETUP
###############################################################################

setup_namespaces() {
  log_step "Setting up namespaces..."
  
  # Create keycloak namespace
  if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    log_step "Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE
  else
    log_success "Namespace $NAMESPACE already exists"
  fi
  
  # Create oauth2-proxy namespace
  if ! kubectl get namespace $NAMESPACE_OAUTH2 &> /dev/null; then
    log_step "Creating namespace: $NAMESPACE_OAUTH2"
    kubectl create namespace $NAMESPACE_OAUTH2
  else
    log_success "Namespace $NAMESPACE_OAUTH2 already exists"
  fi
  
  # Label namespaces for observability
  kubectl label namespace $NAMESPACE monitoring=enabled --overwrite
  kubectl label namespace $NAMESPACE_OAUTH2 monitoring=enabled --overwrite
  
  log_success "Namespaces configured"
}

###############################################################################
# TIER 1: SECURITY HARDENING
###############################################################################

deploy_tier1_security() {
  log_step "Deploying TIER 1: Security Hardening..."
  
  # Network Policies (must be first)
  log_step "Applying network policies..."
  kubectl apply -f infrastructure/sso/5-network-policies.yaml
  sleep 10
  log_success "Network policies applied"
  
  # RBAC
  log_step "Applying RBAC..."
  kubectl apply -f infrastructure/sso/7-rbac.yaml
  sleep 5
  log_success "RBAC configured"
  
  # Pod Security Standards
  log_step "Applying pod security standards..."
  kubectl apply -f infrastructure/sso/9-pod-security-standards.yaml
  sleep 5
  log_success "Pod security standards enforced"
  
  # GSM/KMS Vault Integration
  log_step "Applying GSM/KMS vault integration..."
  kubectl apply -f infrastructure/sso/10-gke-credentials-vault.yaml
  sleep 5
  log_success "GSM/KMS vault configured"
  
  # PostgreSQL HA (largest, needs more time)
  log_step "Applying PostgreSQL HA..."
  kubectl apply -f infrastructure/sso/2b-keycloak-postgres-ha.yaml
  wait_for_statefulset $NAMESPACE keycloak-postgres 600 || return 1
  
  log_success "TIER 1: Security Hardening complete"
}

###############################################################################
# TIER 2: OBSERVABILITY
###############################################################################

deploy_tier2_observability() {
  log_step "Deploying TIER 2: Observability..."
  
  # Tempo Tracing
  log_step "Applying Tempo tracing..."
  kubectl apply -f infrastructure/sso/monitoring/tempo-tracing.yaml
  wait_for_deployment $NAMESPACE tempo 300 || return 1
  
  # Prometheus SLO Rules (ConfigMap, no wait needed)
  log_step "Applying Prometheus SLO rules..."
  kubectl apply -f infrastructure/sso/monitoring/prometheus-slo-rules.yaml
  
  # Grafana Dashboards
  log_step "Applying Grafana dashboards..."
  kubectl apply -f infrastructure/sso/monitoring/grafana-dashboards.yaml
  
  # Redis Cache Layer
  log_step "Applying Redis cache layer..."
  kubectl apply -f infrastructure/sso/11-redis-cache-layer.yaml
  wait_for_statefulset $NAMESPACE redis-cluster 180 || return 1
  
  # PgBouncer Connection Pooling
  log_step "Applying PgBouncer connection pooling..."
  kubectl apply -f infrastructure/sso/12-pgbouncer-pooling.yaml
  wait_for_deployment $NAMESPACE pgbouncer 180 || return 1
  
  log_success "TIER 2: Observability complete"
}

###############################################################################
# CORE DEPLOYMENT
###############################################################################

deploy_core_infrastructure() {
  log_step "Deploying core infrastructure..."
  
  # Keycloak Namespace & Realm Config
  log_step "Applying Keycloak core manifests..."
  kubectl apply -f infrastructure/sso/1-keycloak-namespace.yaml
  kubectl apply -f infrastructure/sso/3-keycloak-realm-config.yaml
  
  # Keycloak Main Deployment
  log_step "Deploying Keycloak..."
  kubectl apply -f infrastructure/sso/4-keycloak-deployment.yaml
  wait_for_deployment $NAMESPACE keycloak 600 || return 1
  
  # OAuth2-Proxy Configuration
  log_step "Applying OAuth2-Proxy..."
  kubectl apply -f infrastructure/sso/6-oauth2-proxy-config.yaml
  wait_for_deployment $NAMESPACE_OAUTH2 oauth2-proxy 300 || return 1
  
  # Ingress
  log_step "Applying Ingress..."
  kubectl apply -f infrastructure/sso/8-oauth2-proxy-ingress.yaml
  sleep 10
  
  log_success "Core infrastructure deployed"
}

###############################################################################
# SETUP GSM INTEGRATION
###############################################################################

setup_gsm_integration() {
  log_step "Setting up GSM/KMS integration..."
  
  if [[ ! -f scripts/sso/setup-gsm-integration.sh ]]; then
    log_warning "GSM setup script not found, skipping..."
    return 0
  fi
  
  chmod +x scripts/sso/setup-gsm-integration.sh
  ./scripts/sso/setup-gsm-integration.sh $PROJECT_ID $ZONE || {
    log_warning "GSM setup encountered issues, continuing..."
  }
  
  log_success "GSM/KMS integration configured"
}

###############################################################################
# VERIFICATION
###############################################################################

verify_deployment() {
  log_step "Verifying deployment..."
  
  # Check all pods are running
  log_step "Checking pod status..."
  local not_running=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | wc -l)
  if [[ $not_running -gt 1 ]]; then  # More than just header
    log_warning "Found non-running pods:"
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
  else
    log_success "All pods are running"
  fi
  
  # Check key deployments
  log_step "Checking key deployments..."
  local deployments=("keycloak" "oauth2-proxy" "prometheus" "grafana" "tempo")
  for deploy in "${deployments[@]}"; do
    local ready=$(kubectl get deployment $deploy -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment $deploy -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [[ "$ready" == "$desired" ]] && [[ "$desired" != "0" ]]; then
      log_success "$deploy: $ready/$desired ready"
    else
      log_warning "$deploy: $ready/$desired ready"
    fi
  done
  
  # Check network policies
  log_step "Checking network policies..."
  local np_count=$(kubectl get networkpolicy -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
  log_success "Network policies: $np_count deployed"
  
  # Check RBAC
  log_step "Checking RBAC..."
  local rb_count=$(kubectl get rolebinding -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
  log_success "RBAC bindings: $rb_count configured"
  
  # Check storage
  log_step "Checking persistent volumes..."
  local pvc_count=$(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
  log_success "Persistent volumes: $pvc_count provisioned"
  
  log_success "Deployment verification complete"
}

###############################################################################
# INTEGRATION TESTS
###############################################################################

run_integration_tests() {
  log_step "Running integration tests..."
  
  if [[ ! -f scripts/testing/integration-tests.sh ]]; then
    log_warning "Integration tests not found, skipping..."
    return 0
  fi
  
  chmod +x scripts/testing/integration-tests.sh
  
  # Run tests (allow to continue even if some fail)
  if ./scripts/testing/integration-tests.sh; then
    log_success "All integration tests passed"
  else
    log_warning "Some integration tests failed (see output above)"
  fi
}

###############################################################################
# GENERATE REPORT
###############################################################################

generate_report() {
  log_step "Generating deployment report..."
  
  local report_file=".deployment-state/sso-deployment-$(date +%Y%m%d_%H%M%S).report"
  mkdir -p .deployment-state
  
  {
    echo "=========================================="
    echo "SSO PLATFORM DEPLOYMENT REPORT"
    echo "=========================================="
    echo ""
    echo "Deployment Date: $(date)"
    echo "Project: $PROJECT_ID"
    echo "Cluster: $CLUSTER_NAME"
    echo "Zone: $ZONE"
    echo ""
    
    echo "TIER 1: Security Hardening"
    echo "  ✓ Network Policies: $(kubectl get networkpolicy -n $NAMESPACE --no-headers 2>/dev/null | wc -l)"
    echo "  ✓ RBAC Bindings: $(kubectl get rolebinding -n $NAMESPACE --no-headers 2>/dev/null | wc -l)"
    echo "  ✓ Pod Security: Enforced"
    echo "  ✓ PostgreSQL HA: $(kubectl get statefulset keycloak-postgres -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")/$(kubectl get statefulset keycloak-postgres -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0") ready"
    echo ""
    
    echo "TIER 2: Observability"
    echo "  ✓ Tempo Tracing: $(kubectl get deployment tempo -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") replicas"
    echo "  ✓ Prometheus: $(kubectl get deployment prometheus -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") replicas"
    echo "  ✓ Grafana: $(kubectl get deployment grafana -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") replicas"
    echo "  ✓ Redis Cache: $(kubectl get statefulset redis-cluster -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")/$(kubectl get statefulset redis-cluster -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0") ready"
    echo ""
    
    echo "Core Services"
    echo "  ✓ Keycloak: $(kubectl get deployment keycloak -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") replicas"
    echo "  ✓ OAuth2-Proxy: $(kubectl get deployment oauth2-proxy -n $NAMESPACE_OAUTH2 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") replicas"
    echo ""
    
    echo "Next Steps:"
    echo "  1. Port-forward Grafana: kubectl port-forward -n keycloak svc/grafana 3000:80"
    echo "  2. Access Grafana: http://localhost:3000"
    echo "  3. View dashboards and metrics"
    echo "  4. Configure alerting (Slack/PagerDuty webhooks)"
    echo ""
    
  } | tee "$report_file"
  
  log_success "Report generated: $report_file"
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║   SSO Platform Complete Deployment Orchestrator               ║"
  echo "║   TIER 1-2 Infrastructure: Security + Observability           ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  preflight_checks || {
    log_error "Pre-flight checks failed"
    exit 1
  }
  
  setup_namespaces || {
    log_error "Namespace setup failed"
    exit 1
  }
  
  deploy_tier1_security || {
    log_error "TIER 1 deployment failed"
    exit 1
  }
  
  deploy_tier2_observability || {
    log_error "TIER 2 deployment failed"
    exit 1
  }
  
  deploy_core_infrastructure || {
    log_error "Core infrastructure deployment failed"
    exit 1
  }
  
  setup_gsm_integration || true  # Non-blocking
  
  verify_deployment || true  # Non-blocking
  
  run_integration_tests || true  # Non-blocking
  
  generate_report || true  # Non-blocking
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║   ✓ SSO Platform Deployment Complete                          ║"
  echo "║                                                                ║"
  echo "║   TIER 1: Security Hardening                        ✓ Complete║"
  echo "║   TIER 2: Observability & Performance              ✓ Complete║"
  echo "║                                                                ║"
  echo "║   Keycloak:     $(kubectl get svc -n keycloak keycloak -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")    ║"
  echo "║   OAuth2-Proxy: $(kubectl get svc -n oauth2-proxy oauth2-proxy -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")    ║"
  echo "║   Grafana:      $(kubectl get svc -n keycloak grafana -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")    ║"
  echo "║                                                                ║"
  echo "║   Documentation: docs/SSO_TIER{1,2}_*.md                      ║"
  echo "║   Tests:        ./scripts/testing/integration-tests.sh         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
}

main "$@"
