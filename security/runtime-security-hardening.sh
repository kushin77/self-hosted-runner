#!/usr/bin/env bash

# Kubernetes Runtime Security & RBAC Hardening (FAANG-Grade)
#
# Implements:
# - Pod Security Standards (PSS) enforcement
# - RBAC least-privilege configuration
# - Network Policies
# - Security Contexts
# - Pod Disruption Budgets
# - Falco runtime detection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[RUNTIME-SEC]${NC} $*"; }
info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

##############################################################################
# 1. POD SECURITY STANDARDS (PSS)
##############################################################################

apply_pod_security_standards() {
    log "Applying Pod Security Standards..."
    
    # Apply Pod Security Standards to namespaces
    kubectl label namespace default \
        pod-security.kubernetes.io/enforce=restricted \
        pod-security.kubernetes.io/audit=restricted \
        pod-security.kubernetes.io/warn=restricted \
        --overwrite 2>/dev/null || warn "Could not label namespace"
    
    info "Pod Security Standards applied to 'default' namespace"
}

##############################################################################
# 2. RBAC CONFIGURATION
##############################################################################

create_rbac_policies() {
    log "Creating least-privilege RBAC policies..."
    
    # Create service account for application
    kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: default
---
# ClusterRole: Read-only access to specific resources
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: app-readonly
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]  # Minimal explicit access if required; otherwise remove
---
# ClusterRoleBinding: Bind role to service account
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-readonly-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-readonly
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: default
---
# Role: Pod-specific permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-pod-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["pods/status"]
  verbs: ["get"]
---
# RoleBinding: Bind pod role to service account
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-pod-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-pod-role
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: default
EOF

    info "RBAC policies created"
}

##############################################################################
# 3. SECURITY CONTEXTS
##############################################################################

create_security_context_policy() {
    log "Creating Pod Security Policy equivalent (PodSecurityPolicy/PSS)..."
    
    # Create Pod with restrictive security context
    kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod-example
  namespace: default
spec:
  serviceAccountName: app-sa
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:latest
    imagePullPolicy: Always
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE  # Only if needed
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: var-run
      mountPath: /var/run
  volumes:
  - name: tmp
    emptyDir: {}
  - name: var-run
    emptyDir: {}
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - myapp
          topologyKey: kubernetes.io/hostname
EOF

    info "Security context policy applied"
}

##############################################################################
# 4. NETWORK POLICIES
##############################################################################

apply_network_policies() {
    log "Applying Network Policies..."
    
    kubectl apply -f - <<'EOF'
---
# Deny all ingress by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Deny all egress except to DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress-except-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
# Allow ingress from Istio ingress gateway
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - protocol: TCP
      port: 8080
---
# Allow egress to specific services only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-specific-egress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - podSelector:
        matchLabels:
          app: cache
    ports:
    - protocol: TCP
      port: 6379
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

    info "Network Policies applied"
}

##############################################################################
# 5. POD DISRUPTION BUDGETS
##############################################################################

create_pod_disruption_budgets() {
    log "Creating Pod Disruption Budgets..."
    
    kubectl apply -f - <<'EOF'
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
  namespace: default
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: backend
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: database-pdb
  namespace: default
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: database
EOF

    info "Pod Disruption Budgets created"
}

##############################################################################
# 6. RESOURCE QUOTAS & LIMITS
##############################################################################

apply_resource_quotas() {
    log "Applying Resource Quotas and LimitRanges..."
    
    kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: default
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "50"
    persistentvolumeclaims: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: compute-limits
  namespace: default
spec:
  limits:
  - max:
      cpu: "2"
      memory: "2Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
    type: Container
  - max:
      cpu: "4"
      memory: "4Gi"
    min:
      cpu: "100m"
      memory: "128Mi"
    type: Pod
EOF

    info "Resource quotas applied"
}

##############################################################################
# 7. RBAC AUDIT
##############################################################################

audit_rbac() {
    log "Auditing current RBAC configuration..."
    
    # List all service accounts
    echo -e "\n${BLUE}Service Accounts:${NC}"
    kubectl get serviceaccount -A --no-headers | head -20
    
    # List all role bindings
    echo -e "\n${BLUE}Role Bindings:${NC}"
    kubectl get rolebinding -A --no-headers | head -20
    
    # List all cluster role bindings
    echo -e "\n${BLUE}Cluster Role Bindings:${NC}"
    kubectl get clusterrolebinding --no-headers | grep -v system: | head -20
    
    # Check for wildcards in RBAC (overly permissive)
    echo -e "\n${BLUE}Checking for overly permissive RBAC rules:${NC}"
    kubectl get clusterrole -o json | jq '.items[] | select(.rules[].verbs[]=="*" or .rules[].resources[]=="*") | .metadata.name' | head -10
}

##############################################################################
# 8. RUNTIME SECURITY (Falco)
##############################################################################

install_falco() {
    log "Installing Falco for runtime security monitoring..."
    
    # Check if Helm is available
    if ! command -v helm &> /dev/null; then
        warn "Helm not found; skipping Falco installation"
        return
    fi
    
    # Add Falco Helm repo
    helm repo add falcosecurity https://falcosecurity.github.io/charts || true
    helm repo update
    
    # Install Falco
    kubectl create namespace falco 2>/dev/null || true
    
    helm upgrade --install falco falcosecurity/falco \
        --namespace falco \
        --set falco.grpc.enabled=true \
        --set falco.grpcOutput.enabled=true \
        --values - <<'EOF'
falco:
  rules_file:
  - /etc/falco/rules.d
  - /etc/falco/rules.yaml
  
  rulesOutput:
    enabled: true
    
  grpc:
    enabled: true
    unbuffered: true
    
  grpcOutput:
    enabled: true
    
  logLevel: notice

falcoctl:
  artifact:
    install:
      enabled: true
      plugins_dir: /usr/share/falco/plugins
      
falcoauditlog:
  enabled: true
  
driver:
  kind: kmod
EOF

    info "Falco installed"
}

##############################################################################
# 9. SECURITY SCANNING
##############################################################################

scan_cluster_security() {
    log "Scanning cluster for security issues..."
    
    # Check for privileged containers
    echo -e "\n${YELLOW}Checking for privileged containers:${NC}"
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep -v "^$" | grep true || echo "No privileged containers found"
    
    # Check for root running containers
    echo -e "\n${YELLOW}Checking for containers running as root:${NC}"
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.runAsUser}{"\n"}{end}' | grep -E "root|$|^[0-9]*$" || echo "No root containers found"
    
    # Check for containers without resource limits
    echo -e "\n${YELLOW}Checking for containers without resource limits:${NC}"
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' -o json | jq '.items[] | select(.spec.containers[].resources.limits == null) | "\(.metadata.namespace) \(.metadata.name)"' || echo "All containers have resource limits"
}

##############################################################################
# MAIN
##############################################################################

main() {
    local action="${1:-apply}"
    
    case "$action" in
        apply)
            log "Applying comprehensive runtime security hardening..."
            apply_pod_security_standards
            create_rbac_policies
            create_security_context_policy
            apply_network_policies
            create_pod_disruption_budgets
            apply_resource_quotas
            install_falco
            info "Runtime security hardening complete"
            ;;
        audit)
            audit_rbac
            scan_cluster_security
            ;;
        scan)
            scan_cluster_security
            ;;
        *)
            echo "Usage: $0 <action>"
            echo "Actions:"
            echo "  apply  - Apply all security hardening policies"
            echo "  audit  - Audit current RBAC configuration"
            echo "  scan   - Scan cluster for security issues"
            exit 1
            ;;
    esac
}

main "$@"
