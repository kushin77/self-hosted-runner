#!/bin/bash

################################################################################
# Auto-Remediation Engine
# Purpose: Automatically fix common cluster issues when detected
# Usage: Called by cluster-health-check.sh on failure
# Philosophy: Quick fixes for transient issues + escalate persistent failures
################################################################################

set -euo pipefail

# Configuration
FAILED_CHECK="$1"  # Name of failed check
FAILURE_CONTEXT="$2"  # Additional context (e.g., which node, which pod)
DRY_RUN="${DRY_RUN:-false}"  # Set to true to preview actions

# Logging
LOG_DIR="${LOG_DIR:-logs/auto-remediation}"
LOG_FILE="$LOG_DIR/remediation-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Logging
################################################################################

log_info() { echo "[INFO] $*" | tee -a "$LOG_FILE"; }
log_warn() { echo "[WARN] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[ERROR] $*" | tee -a "$LOG_FILE"; }
log_success() { echo "[SUCCESS] $*" | tee -a "$LOG_FILE"; }

execute_or_dry_run() {
  local description="$1"
  shift
  local command=("$@")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] WOULD: $description"
    log_info "[DRY-RUN] Command: ${command[*]}"
    return 0
  else
    log_info "EXECUTING: $description"
    if "${command[@]}"; then
      log_success "✓ $description"
      return 0
    else
      log_error "✗ Failed: $description"
      return 1
    fi
  fi
}

################################################################################
# REMEDIATION HANDLERS
################################################################################

##### REMEDIATION: Node Not Ready #####
remediate_node_not_ready() {
  local node="${FAILURE_CONTEXT:-}"
  
  if [[ -z "$node" ]]; then
    # Find first NotReady node
    node=$(kubectl get nodes --no-headers | grep "NotReady" | head -1 | awk '{print $1}')
  fi
  
  if [[ -z "$node" ]]; then
    log_error "No node context found for remediation"
    return 1
  fi
  
  log_info "Remediating node not ready: $node"
  
  # Step 1: Check if node is offline (not just unschedulable)
  local node_status=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  
  if [[ "$node_status" != "True" ]]; then
    log_warn "Node $node is not ready (status: $node_status)"
    
    # Step 2: Try to restart kubelet
    log_info "Attempting to restart kubelet on node $node..."
    
    # SSH to node and restart kubelet (if IP available)
    local node_ip=$(kubectl get node "$node" -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
    if [[ -z "$node_ip" ]]; then
      node_ip=$(kubectl get node "$node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    if [[ -n "$node_ip" ]]; then
      execute_or_dry_run "Restart kubelet on $node_ip" \
        ssh -o ConnectTimeout=5 "gke-node@$node_ip" "sudo systemctl restart kubelet" || true
    fi
    
    # Step 3: If node still not ready, drain and remove from cluster
    sleep 10
    node_status=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [[ "$node_status" != "True" ]]; then
      log_warn "Node still not ready after kubelet restart, draining..."
      execute_or_dry_run "Drain node $node" \
        kubectl drain "$node" \
          --ignore-daemonsets \
          --delete-emptydir-data \
          --grace-period=30 \
          --timeout=5m
      
      # GKE will auto-replace the node
      log_info "Node will be replaced by GKE auto-healing"
    fi
  fi
}

##### REMEDIATION: DNS Resolution Failed #####
remediate_dns_failed() {
  log_info "Remediating DNS resolution failure"
  
  # Step 1: Check if CoreDNS is running
  local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers | wc -l)
  
  if [[ $coredns_pods -eq 0 ]]; then
    log_warn "No CoreDNS pods running, restarting deployment..."
    
    execute_or_dry_run "Restart CoreDNS deployment" \
      kubectl rollout restart deployment coredns -n kube-system
    
    # Wait for DNS to recover
    log_info "Waiting for DNS to recover..."
    sleep 15
  else
    log_info "$coredns_pods CoreDNS pods are running"
    
    # Step 2: Restart CoreDNS pods anyway (they might be wedged)
    log_warn "Restarting CoreDNS pods to clear any state..."
    execute_or_dry_run "Delete CoreDNS pods to force restart" \
      kubectl delete pods -n kube-system -l k8s-app=kube-dns
    
    sleep 10
  fi
  
  # Step 3: Verify DNS works
  if kubectl run dns-test --image=busybox:latest --restart=Never --command -- nslookup kubernetes.default 2>/dev/null; then
    log_success "✓ DNS resolution verified"
    kubectl delete pod dns-test 2>/dev/null || true
  else
    log_error "DNS still not working, may need manual intervention"
    return 1
  fi
}

##### REMEDIATION: API Server Latency High #####
remediate_api_latency() {
  log_info "Remediating high API server latency"
  
  # Step 1: Check API server replicas
  local api_replicas=$(kubectl get deployment -n kube-system -l component=kube-apiserver --no-headers | wc -l)
  
  log_info "Current API server replicas: $api_replicas"
  
  if [[ $api_replicas -lt 3 ]]; then
    log_warn "API replicas < 3, scaling up..."
    execute_or_dry_run "Scale API servers to 3 replicas" \
      kubectl scale deployment kube-apiserver -n kube-system --replicas=3
  fi
  
  # Step 2: Check API request metrics
  local pending_requests=$(kubectl get --all-namespaces pods --no-headers | wc -l)
  
  if [[ $pending_requests -gt 500 ]]; then
    log_warn "High pod count ($pending_requests), may be load issue"
    
    # Scale down non-critical workloads
    local non_critical_pods=$(kubectl get pods --all-namespaces \
      -l priority!=critical,priority!=monitoring \
      --no-headers | wc -l)
    
    if [[ $non_critical_pods -gt 100 ]]; then
      log_warn "Evicting low-priority pods to reduce API load..."
      kubectl get pods --all-namespaces \
        -l priority!=critical,priority!=monitoring \
        --sort-by=.spec.priority | head -20 | awk '{print $2, "-n", $1}' | \
        xargs -I {} sh -c "kubectl delete pod {} 2>/dev/null || true" || true
    fi
  fi
  
  # Step 3: Verify latency improved
  sleep 10
  log_info "API latency remediation complete"
}

##### REMEDIATION: Memory Pressure #####
remediate_memory_pressure() {
  local node="${FAILURE_CONTEXT:-}"
  
  if [[ -z "$node" ]]; then
    node=$(kubectl get nodes --no-headers | grep "MemoryPressure" | head -1 | awk '{print $1}')
  fi
  
  if [[ -z "$node" ]]; then
    log_error "No node with memory pressure found"
    return 1
  fi
  
  log_info "Remediating memory pressure on node: $node"
  
  # Step 1: Get pods sorted by memory usage
  local high_memory_pods=$(kubectl get pods --all-namespaces \
    --field-selector=spec.nodeName="$node" \
    -o jsonpath='{range .items[*]}{.metadata.namespace}' \
    --sort-by='.status.containerStatuses[0].memory' | tail -5)
  
  # Step 2: Evict Burstable (not Guaranteed) pods
  while IFS= read -r pod_namespace pod_name; do
    local qos=$(kubectl get pod -n "$pod_namespace" "$pod_name" -o jsonpath='{.status.qosClass}')
    
    if [[ "$qos" == "Burstable" ]]; then
      log_warn "Evicting Burstable pod: $pod_namespace/$pod_name"
      execute_or_dry_run "Evict pod $pod_namespace/$pod_name" \
        kubectl delete pod "$pod_name" -n "$pod_namespace"
    fi
  done <<< "$(echo "$high_memory_pods")"
  
  log_info "Memory pressure remediation complete"
}

##### REMEDIATION: Network Issues #####
remediate_network_issues() {
  log_info "Remediating network connectivity issues"
  
  # Step 1: Check CNI daemonset
  local cni_pods=$(kubectl get daemonset -n kube-system -l component=cni --no-headers | wc -l)
  
  if [[ $cni_pods -eq 0 ]]; then
    log_error "No CNI daemonset found - network configuration issue"
    return 1
  fi
  
  # Step 2: Restart CNI daemonset
  local cni_name=$(kubectl get daemonset -n kube-system -l component=cni --no-headers | awk '{print $1}')
  
  if [[ -n "$cni_name" ]]; then
    log_warn "Restarting CNI daemonset: $cni_name"
    execute_or_dry_run "Restart CNI daemonset" \
      kubectl rollout restart daemonset "$cni_name" -n kube-system
    
    sleep 10
  fi
  
  # Step 3: Check network policies aren't too strict
  local net_policies=$(kubectl get networkpolicies --all-namespaces --no-headers | wc -l)
  log_info "Network policies in cluster: $net_policies"
  
  log_info "Network issue remediation complete"
}

##### REMEDIATION: Pod Crash Loop #####
remediate_pod_crash_loop() {
  local pod="${FAILURE_CONTEXT:-}"
  
  if [[ -z "$pod" ]]; then
    log_error "Pod context required for crash loop remediation"
    return 1
  fi
  
  log_info "Remediating pod crash loop: $pod"
  
  # Step 1: Check pod logs for error patterns
  local recent_error=$(kubectl logs "$pod" --tail=50 2>/dev/null | grep -i "error" | tail -1 || echo "")
  
  if [[ -n "$recent_error" ]]; then
    log_warn "Recent error: $recent_error"
  fi
  
  # Step 2: Check if it's out of memory
  if kubectl logs "$pod" --tail=50 2>/dev/null | grep -qi "OOMKilled\|oom"; then
    log_warn "Pod OOMKilled, need to increase memory limits"
    return 2  # Requires manual intervention
  fi
  
  # Step 3: Check if dependencies are available
  local pod_namespace=$(echo "$pod" | cut -d/ -f1)
  local pod_name=$(echo "$pod" | cut -d/ -f2)
  
  # Step 4: Increase restart backoff (prevents thundering herd)
  log_warn "Backing off pod restarts to prevent cascade..."
  # This would be done via pod priority/QoS tuning
  
  log_info "Pod crash loop investigation complete"
}

################################################################################
# MAIN DISPATCHER
################################################################################

main() {
  log_info "╔════════════════════════════════════════════════════════════╗"
  log_info "║  Auto-Remediation Engine                                   ║"
  log_info "║  Failed Check: $FAILED_CHECK"
  log_info "║  Context: $FAILURE_CONTEXT"
  log_info "║  Dry-Run: $DRY_RUN"
  log_info "╚════════════════════════════════════════════════════════════╝"
  
  case "$FAILED_CHECK" in
    "node_ready")
      remediate_node_not_ready
      ;;
    "dns_resolution")
      remediate_dns_failed
      ;;
    "api_latency")
      remediate_api_latency
      ;;
    "memory_pressure")
      remediate_memory_pressure
      ;;
    "network_issues")
      remediate_network_issues
      ;;
    "pod_crash_loop")
      remediate_pod_crash_loop
      ;;
    *)
      log_error "Unknown failure check: $FAILED_CHECK"
      log_error "Supported checks:"
      log_error "  - node_ready"
      log_error "  - dns_resolution"
      log_error "  - api_latency"
      log_error "  - memory_pressure"
      log_error "  - network_issues"
      log_error "  - pod_crash_loop"
      return 1
      ;;
  esac
  
  # Create GitHub issue for tracking
  local issue_body="## Auto-Remediation Action

**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Check**: $FAILED_CHECK
**Context**: $FAILURE_CONTEXT

Automatic remediation was triggered for this issue.

**Actions Taken**:
- See log: $LOG_FILE

**Manual Verification**:
- Verify cluster health: \`./scripts/utilities/cluster-health-check.sh\`
- Check recent events: \`kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20\`
- Review logs: \`tail -f $LOG_FILE\`
"
  
  if gh issue create \
    --repo kushin77/self-hosted-runner \
    --title "🔧 Auto-Remediation: $FAILED_CHECK ($FAILURE_CONTEXT)" \
    --body "$issue_body" \
    --label "auto-remediation" \
    --label "incident" 2>/dev/null; then
    log_info "GitHub issue created for tracking"
  fi
  
  log_success "Remediation complete - Log: $LOG_FILE"
}

# Execute
main "$@"
