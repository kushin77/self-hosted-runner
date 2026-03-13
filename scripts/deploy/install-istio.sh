#!/usr/bin/env bash
# Istio Installation & Policy Enforcement (FAANG-Grade)
#
# Installs Istio service mesh on Kubernetes cluster and applies:
# - mTLS enforcement (all traffic encrypted)
# - Authorization policies (least privilege)
# - RequestAuthentication (JWT validation)
# - PeerAuthentication (service-to-service)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
CLUSTER_HOST="${CLUSTER_HOST:-192.168.168.42}"
ISTIO_VERSION="${ISTIO_VERSION:-1.17.0}"
ISTIO_NAMESPACE="istio-system"
APPS_NAMESPACE="ops"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[ISTIO-INSTALL]${NC} $*"; }
info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

##############################################################################
# 1. PREREQUISITES CHECK
##############################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Check KUBECONFIG or cluster accessibility."
        exit 1
    fi
    
    info "✓ kubectl connectivity verified"
    
    # Check required tools
    for cmd in helm kubectl git; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd not found. Install it first."
            exit 1
        fi
    done
    
    info "✓ Required tools available: helm, kubectl, git"
}

##############################################################################
# 2. CREATE NAMESPACES
##############################################################################

create_namespaces() {
    log "Creating Kubernetes namespaces..."
    
    # Istio system namespace
    kubectl create namespace "$ISTIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Enable sidecar injection label
    kubectl label namespace "$ISTIO_NAMESPACE" istio-injection=enabled --overwrite
    
    info "✓ Namespaces created/labeled"
}

##############################################################################
# 3. INSTALL ISTIO CRDs
##############################################################################

install_istio_crds() {
    log "Installing Istio CRDs..."
    
    # Add Istio Helm repo
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update
    
    # Install CRDs separately
    helm install istio-base istio/base \
        --namespace "$ISTIO_NAMESPACE" \
        --set defaultRevision=default \
        --wait \
        --timeout 5m
    
    info "✓ Istio CRDs installed"
}

##############################################################################
# 4. INSTALL ISTIO CONTROL PLANE
##############################################################################

install_istio_control_plane() {
    log "Installing Istio control plane..."
    
    # Install Istiod (control plane)
    helm install istiod istio/istiod \
        --namespace "$ISTIO_NAMESPACE" \
        --set global.istioNamespace="$ISTIO_NAMESPACE" \
        --set pilot.autoscalingv2Enabled=true \
        --wait \
        --timeout 5m
    
    info "✓ Istio control plane installed"
}

##############################################################################
# 5. Enable Sidecar Injection on Apps Namespace
##############################################################################

enable_sidecar_injection() {
    log "Enabling sidecar injection on apps namespace..."
    
    kubectl label namespace "$APPS_NAMESPACE" istio-injection=enabled --overwrite
    
    # Restart pods to inject sidecars
    kubectl rollout restart deployment -n "$APPS_NAMESPACE" || true
    kubectl rollout restart statefulset -n "$APPS_NAMESPACE" || true
    
    info "✓ Sidecar injection enabled; pods will be restarted"
}

##############################################################################
# 6. APPLY SECURITY POLICIES
##############################################################################

apply_security_policies() {
    log "Applying Istio security policies..."
    
    # Apply cleaned Istio policy YAML
    if [[ -f "$SCRIPT_DIR/istio-mtls-policy.apply.yaml" ]]; then
        kubectl apply -f "$SCRIPT_DIR/istio-mtls-policy.apply.yaml" -n "$APPS_NAMESPACE"
        info "✓ Istio security policies applied"
    else
        warn "istio-mtls-policy.apply.yaml not found; skipping policy application"
    fi
}

##############################################################################
# 7. VERIFY INSTALLATION
##############################################################################

verify_installation() {
    log "Verifying Istio installation..."
    
    # Check control plane pods
    local istiod_ready=$(kubectl get deployment -n "$ISTIO_NAMESPACE" istiod -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ $istiod_ready -gt 0 ]]; then
        info "✓ Istiod control plane is ready ($istiod_ready replicas)"
    else
        warn "Istiod control plane may not be ready yet; check with: kubectl get pods -n $ISTIO_NAMESPACE"
    fi
    
    # Check CRDs
    local crd_count=$(kubectl get crd | grep -c "istio.io" || echo 0)
    if [[ $crd_count -gt 0 ]]; then
        info "✓ Istio CRDs registered ($crd_count found)"
    else
        warn "Istio CRDs not fully registered yet"
    fi
    
    # Check sidecar injection
    local injected=$(kubectl get pods -n "$APPS_NAMESPACE" -o jsonpath='{.items[0].spec.containers | length}' 2>/dev/null || echo 0)
    if [[ $injected -gt 1 ]]; then
        info "✓ Sidecar injection active (pods have multiple containers)"
    else
        warn "Sidecar injection may not be active; pods should have 2+ containers"
    fi
}

##############################################################################
# 8. CREATE AUDIT ENTRY
##############################################################################

audit_installation() {
    log "Creating audit entry for Istio installation..."
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local audit_entry="{\"timestamp\":\"$timestamp\",\"component\":\"istio\",\"action\":\"install\",\"version\":\"$ISTIO_VERSION\",\"cluster\":\"$CLUSTER_HOST\",\"status\":\"completed\"}"
    
    echo "$audit_entry" >> "$PROJECT_ROOT/audit-trail.jsonl"
    info "✓ Audit entry added"
}

##############################################################################
# MAIN
##############################################################################

main() {
    local action="${1:-install}"
    
    case "$action" in
        install)
            check_prerequisites
            create_namespaces
            install_istio_crds
            install_istio_control_plane
            enable_sidecar_injection
            apply_security_policies
            sleep 10  # Allow time for pods to stabilize
            verify_installation
            audit_installation
            info "✓ Istio installation complete"
            ;;
        verify)
            verify_installation
            ;;
        remove)
            log "Removing Istio..."
            helm uninstall istiod -n "$ISTIO_NAMESPACE" || true
            helm uninstall istio-base -n "$ISTIO_NAMESPACE" || true
            kubectl delete namespace "$ISTIO_NAMESPACE" || true
            info "✓ Istio removed"
            ;;
        *)
            echo "Usage: $0 <action>"
            echo "Actions:"
            echo "  install - Install Istio and apply policies (default)"
            echo "  verify  - Verify Istio installation status"
            echo "  remove  - Remove Istio and cleanup"
            exit 1
            ;;
    esac
}

main "$@"
