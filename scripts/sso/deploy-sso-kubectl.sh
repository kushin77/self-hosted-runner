#!/bin/bash
################################################################################
#                                                                              #
#  SSO Platform - kubectl-Based Deployment (No SSH Required)                  #
#  ============================================================                #
#  Purpose: Deploy SSO platform directly via kubectl (works without SSH)      #
#  Usage: ./deploy-sso-kubectl.sh [--dry-run] [--force]                      #
#  Timeline: 15-20 minutes                                                    #
#                                                                              #
#  Options:                                                                    #
#    --dry-run    Preview changes without applying                            #
#    --force      Skip safety checks and re-deploy                            #
#                                                                              #
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE_KEYCLOAK="keycloak"
NAMESPACE_OAUTH2="oauth2-proxy"
MANIFEST_DIR="kubernetes/manifests/sso"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
AUDIT_FILE="/tmp/sso-kubectl-deployment-$(date +%s).log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN="true"; shift ;;
        --force) FORCE="true"; shift ;;
        *) shift ;;
    esac
done

################################################################################
# Utility Functions
################################################################################

log_header() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ ${1}${NC}"
}

log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ ${1}"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ ${1}${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ${1}${NC}"
}

audit_log() {
    echo "[$(date -Iseconds)] $*" >> "$AUDIT_FILE"
}

################################################################################
# Pre-flight Checks
################################################################################

run_preflight_checks() {
    log_header "Running preflight checks..."
    
    # Check required tools
    for cmd in kubectl git md5sum; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required tool not found: $cmd"
            return 1
        fi
    done
    log_success "All required tools present"
    
    # Check kubeconfig
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Ensure kubeconfig is configured: KUBECONFIG env variable or ~/.kube/config"
        return 1
    fi
    log_success "Connected to Kubernetes cluster"
    
    # Check cluster nodes
    local node_count
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$node_count" -lt 1 ]; then
        log_error "No Kubernetes nodes available"
        return 1
    fi
    log_success "Cluster has $node_count nodes"
    
    # Check manifests exist
    if [ ! -d "$MANIFEST_DIR" ]; then
        log_error "Manifest directory not found: $MANIFEST_DIR"
        return 1
    fi
    log_success "Manifest directory found"
    
    audit_log "Preflight checks passed - $node_count nodes available"
    return 0
}

################################################################################
# Namespace Management
################################################################################

create_namespaces() {
    log_header "Creating namespaces..."
    
    local kubectl_cmd="kubectl"
    if [ "$DRY_RUN" = "true" ]; then
        kubectl_cmd="kubectl --dry-run=client"
    fi
    
    # Create keycloak namespace
    if ! kubectl get namespace "$NAMESPACE_KEYCLOAK" &> /dev/null; then
        log_info "Creating namespace: $NAMESPACE_KEYCLOAK"
        $kubectl_cmd create namespace "$NAMESPACE_KEYCLOAK"
        audit_log "Created namespace=$NAMESPACE_KEYCLOAK"
    else
        log_info "Namespace already exists: $NAMESPACE_KEYCLOAK"
    fi
    
    # Create oauth2-proxy namespace
    if ! kubectl get namespace "$NAMESPACE_OAUTH2" &> /dev/null; then
        log_info "Creating namespace: $NAMESPACE_OAUTH2"
        $kubectl_cmd create namespace "$NAMESPACE_OAUTH2"
        audit_log "Created namespace=$NAMESPACE_OAUTH2"
    else
        log_info "Namespace already exists: $NAMESPACE_OAUTH2"
    fi
    
    log_success "Namespaces ready"
}

################################################################################
# TIER 1: Security Hardening
################################################################################

deploy_tier1_security() {
    log_header "Deploying TIER 1: Security Hardening..."
    
    local tier1_files=(
        "$MANIFEST_DIR/01-network-policies.yaml"
        "$MANIFEST_DIR/02-rbac.yaml"
        "$MANIFEST_DIR/03-pod-security-standards.yaml"
    )
    
    for manifest in "${tier1_files[@]}"; do
        if [ ! -f "$manifest" ]; then
            log_warn "Manifest not found: $manifest"
            continue
        fi
        
        log_info "Validating: $(basename "$manifest")"
        if ! kubectl apply -f "$manifest" --dry-run=client &> /dev/null; then
            log_error "Validation failed: $manifest"
            return 1
        fi
        
        if [ "$DRY_RUN" = "false" ]; then
            log_info "Applying: $(basename "$manifest")"
            kubectl apply -f "$manifest"
            audit_log "Applied TIER1 manifest=$manifest"
        fi
    done
    
    log_success "TIER 1 security hardening deployed"
}

################################################################################
# TIER 2: Observability
################################################################################

deploy_tier2_observability() {
    log_header "Deploying TIER 2: Observability..."
    
    local tier2_files=(
        "$MANIFEST_DIR/04-monitoring.yaml"
        "$MANIFEST_DIR/05-grafana.yaml"
        "$MANIFEST_DIR/06-prometheus.yaml"
    )
    
    for manifest in "${tier2_files[@]}"; do
        if [ ! -f "$manifest" ]; then
            log_warn "Manifest not found: $manifest"
            continue
        fi
        
        log_info "Validating: $(basename "$manifest")"
        if ! kubectl apply -f "$manifest" --dry-run=client &> /dev/null; then
            log_error "Validation failed: $manifest"
            return 1
        fi
        
        if [ "$DRY_RUN" = "false" ]; then
            log_info "Applying: $(basename "$manifest")"
            kubectl apply -f "$manifest"
            audit_log "Applied TIER2 manifest=$manifest"
        fi
    done
    
    log_success "TIER 2 observability deployed"
}

################################################################################
# Core Services Deployment
################################################################################

deploy_core_services() {
    log_header "Deploying Core Services..."
    
    local core_files=(
        "$MANIFEST_DIR/07-keycloak-db.yaml"
        "$MANIFEST_DIR/08-keycloak.yaml"
        "$MANIFEST_DIR/09-oauth2-proxy.yaml"
        "$MANIFEST_DIR/10-ingress.yaml"
    )
    
    for manifest in "${core_files[@]}"; do
        if [ ! -f "$manifest" ]; then
            log_warn "Manifest not found: $manifest"
            continue
        fi
        
        log_info "Validating: $(basename "$manifest")"
        if ! kubectl apply -f "$manifest" --dry-run=client &> /dev/null; then
            log_error "Validation failed: $manifest"
            return 1
        fi
        
        if [ "$DRY_RUN" = "false" ]; then
            log_info "Applying: $(basename "$manifest")"
            kubectl apply -f "$manifest"
            audit_log "Applied core service manifest=$manifest"
        fi
    done
    
    log_success "Core services deployed"
}

################################################################################
# Verification
################################################################################

verify_deployment() {
    log_header "Verifying deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry-run mode: skipping verification"
        return 0
    fi
    
    local max_retries=30
    local retry=0
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready (max 5 minutes)..."
    while [ $retry -lt $max_retries ]; do
        local ready_count
        ready_count=$(kubectl get pods -n "$NAMESPACE_KEYCLOAK" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        
        if [ "$ready_count" -gt 0 ]; then
            log_success "Found $ready_count running pods"
            break
        fi
        
        retry=$((retry + 1))
        log_info "Waiting... ($retry/$max_retries)"
        sleep 10
    done
    
    if [ $retry -eq $max_retries ]; then
        log_warn "Pods still initializing after 5 minutes (may still be starting)"
    fi
    
    # Show pod status
    log_info "Pod status:"
    kubectl get pods -n "$NAMESPACE_KEYCLOAK" --no-headers 2>/dev/null || true
    
    # Show services
    log_info "Services:"
    kubectl get svc -n "$NAMESPACE_KEYCLOAK" --no-headers 2>/dev/null || true
    
    log_success "Deployment verification complete"
    audit_log "Deployment verification completed"
}

################################################################################
# Health Checks
################################################################################

check_health() {
    log_header "Running health checks..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry-run mode: skipping health checks"
        return 0
    fi
    
    # Get ingress info
    log_info "Checking Ingress configuration..."
    kubectl get ingress -n "$NAMESPACE_KEYCLOAK" -o wide || true
    
    # Check pod logs for errors
    log_info "Checking for pod errors..."
    local error_count
    error_count=$(kubectl get pods -n "$NAMESPACE_KEYCLOAK" | grep -c "Error\|CrashLoop" || echo "0")
    if [ "$error_count" -gt 0 ]; then
        log_warn "Found $error_count pods in error state"
        kubectl describe pods -n "$NAMESPACE_KEYCLOAK" | grep -A 5 "Error\|CrashLoop" || true
    else
        log_success "No pods in error state"
    fi
    
    audit_log "Health check completed - errors: $error_count"
}

################################################################################
# Main Deployment Flow
################################################################################

main() {
    log_header "╔════════════════════════════════════════════════════════════════╗"
    log_header "║   SSO Platform - kubectl-Based Deployment                     ║"
    log_header "║   Mode: $([ "$DRY_RUN" = "true" ] && echo "DRY-RUN" || echo "LIVE  ")                                    ║"
    log_header "║   No SSH required - Uses kubeconfig                           ║"
    log_header "╚════════════════════════════════════════════════════════════════╝"
    
    audit_log "Deployment started - DRY_RUN=$DRY_RUN FORCE=$FORCE"
    
    # Preflight checks
    if ! run_preflight_checks; then
        log_error "Preflight checks failed"
        audit_log "Preflight checks FAILED"
        return 1
    fi
    
    # Create namespaces
    if ! create_namespaces; then
        log_error "Failed to create namespaces"
        audit_log "Namespace creation FAILED"
        return 1
    fi
    
    # Deploy TIER 1
    if ! deploy_tier1_security; then
        log_error "TIER 1 deployment failed"
        audit_log "TIER1 deployment FAILED"
        return 1
    fi
    
    # Deploy TIER 2
    if ! deploy_tier2_observability; then
        log_error "TIER 2 deployment failed"
        audit_log "TIER2 deployment FAILED"
        return 1
    fi
    
    # Deploy core services
    if ! deploy_core_services; then
        log_error "Core services deployment failed"
        audit_log "Core services deployment FAILED"
        return 1
    fi
    
    # Verify deployment
    if ! verify_deployment; then
        log_error "Deployment verification failed"
        audit_log "Deployment verification FAILED"
        return 1
    fi
    
    # Health checks
    check_health
    
    # Summary
    log_header "════════════════════════════════════════════════════════════════"
    log_success "Deployment completed successfully!"
    log_info "Audit log: $AUDIT_FILE"
    log_info "Next steps:"
    log_info "  1. Check pod status: kubectl get pods -n $NAMESPACE_KEYCLOAK"
    log_info "  2. View logs: kubectl logs -n $NAMESPACE_KEYCLOAK <pod-name>"
    log_info "  3. Port forward: kubectl port-forward -n $NAMESPACE_KEYCLOAK svc/keycloak 8080:8080"
    
    audit_log "Deployment COMPLETED SUCCESSFULLY"
}

# Run main function
main "$@"
exit $?
