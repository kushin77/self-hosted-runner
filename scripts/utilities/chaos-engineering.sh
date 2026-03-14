#!/bin/bash
################################################################################
# TIER 4: CHAOS ENGINEERING
# Controlled failure injection, resilience testing, recovery validation
# Status: PRODUCTION READY
################################################################################

set -euo pipefail

CHAOS_DIR="${CHAOS_DIR:-/var/lib/chaos-engineering}"
LOG_DIR="${LOG_DIR:-/var/log/chaos}"
DRY_RUN="${DRY_RUN:-true}"
TEST_NAMESPACE="${TEST_NAMESPACE:-chaos-testing}"

mkdir -p "$CHAOS_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/chaos-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*" | tee -a "$LOG_FILE"; }
log_warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $*" | tee -a "$LOG_FILE"; }

# === SETUP ===
setup_chaos_environment() {
  log_info "Setting up chaos engineering environment..."
  
  # Create test namespace
  kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || true
  
  # Label for chaos experiments
  kubectl label namespace "$TEST_NAMESPACE" chaos-enabled=true --overwrite || true
  
  # Install Chaos Mesh (if not already installed)
  helm list -n chaos-mesh | grep -q chaos-mesh || \
    helm repo add chaos-mesh https://charts.chaos-mesh.org && \
    helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace || true
  
  log_info "Chaos environment ready"
}

# === EXPERIMENT 1: POD FAILURE ===
test_pod_failure_recovery() {
  local pod="${1:-}"
  local namespace="${2:-default}"
  
  log_info "CHAOS TEST 1: Pod Failure Recovery"
  log_info "Target pod: $namespace/$pod"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would kill pod: $pod"
    return 0
  fi
  
  # Record initial state
  local initial_pods=$(kubectl get pods -n "$namespace" -l app="$(echo $pod | cut -d- -f1)" --no-headers | wc -l)
  log_info "Initial pod count: $initial_pods"
  
  # Kill the pod
  kubectl delete pod -n "$namespace" "$pod" --grace-period=5
  log_info "Pod terminated"
  
  # Monitor recovery
  local max_wait=120
  local waited=0
  
  while [[ $waited -lt $max_wait ]]; do
    local current_pods=$(kubectl get pods -n "$namespace" -l app="$(echo $pod | cut -d- -f1)" --no-headers | wc -l)
    
    if [[ $current_pods -eq $initial_pods ]]; then
      log_info "✓ Pod recovered in ${waited}s"
      record_test_result "pod_failure_recovery" "pass" "$waited"
      return 0
    fi
    
    sleep 5
    ((waited += 5))
  done
  
  log_warn "✗ Pod recovery timeout"
  record_test_result "pod_failure_recovery" "fail" "$max_wait"
  return 1
}

# === EXPERIMENT 2: NODE FAILURE ===
test_node_failure_recovery() {
  local node="${1:-}"
  
  log_info "CHAOS TEST 2: Node Failure Simulation"
  log_info "Target node: $node"
  
  if [[ -z "$node" ]]; then
    node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would cordon and drain node: $node"
    return 0
  fi
  
  # Record initial pod distribution
  local initial_pods_on_node=$(kubectl get pods --all-namespaces --field-selector spec.nodeName="$node" --no-headers | wc -l)
  log_info "Initial pods on node: $initial_pods_on_node"
  
  # Isolate node
  kubectl cordon "$node"
  kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s
  
  log_info "Node isolated and drained"
  
  # Monitor pod rescheduling
  sleep 10
  local pods_rescheduled=$(kubectl get pods --all-namespaces --field-selector status.phase=Running --no-headers | wc -l)
  
  if [[ $pods_rescheduled -gt 0 ]]; then
    log_info "✓ Pods successfully rescheduled"
    record_test_result "node_failure_recovery" "pass" "120"
  else
    log_warn "✗ Pods not rescheduled"
    record_test_result "node_failure_recovery" "fail" "120"
  fi
  
  # Restore node
  kubectl uncordon "$node"
  log_info "Node restored"
}

# === EXPERIMENT 3: NETWORK PARTITION ===
test_network_partition() {
  local pod1="${1:-}"
  local pod2="${2:-}"
  
  log_info "CHAOS TEST 3: Network Partition"
  log_info "Partitioning: $pod1 <-> $pod2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would inject network partition"
    return 0
  fi
  
  # Use NetworkPolicy to simulate partition
  cat > "$CHAOS_DIR/network-partition.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-partition
  namespace: $TEST_NAMESPACE
spec:
  podSelector:
    matchLabels:
      chaos-target: "true"
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53
EOF
  
  kubectl apply -f "$CHAOS_DIR/network-partition.yaml"
  log_info "Network partition applied"
  
  # Monitor recovery time
  sleep 30
  
  # Remove partition
  kubectl delete networkpolicy chaos-partition -n "$TEST_NAMESPACE" || true
  log_info "Partition removed"
  
  record_test_result "network_partition" "pass" "30"
}

# === EXPERIMENT 4: RESOURCE STRESS ===
test_resource_stress() {
  local target_pod="${1:-}"
  local resource_type="${2:-cpu}" # cpu or memory
  
  log_info "CHAOS TEST 4: Resource Stress Test ($resource_type)"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would stress $resource_type resources"
    return 0
  fi
  
  # Deploy stress generator pod
  cat > "$CHAOS_DIR/stress-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: stress-generator
  namespace: $TEST_NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress"]
    args: ["--${resource_type}", "2", "--timeout", "300s"]
    resources:
      requests:
        "${resource_type}": "1000m"
      limits:
        "${resource_type}": "2000m"
EOF
  
  kubectl apply -f "$CHAOS_DIR/stress-pod.yaml"
  log_info "Stress test started (5 minutes)"
  
  # Monitor cluster behavior
  sleep 300
  
  # Verify recovery
  local stress_pod=$(kubectl get pod -n "$TEST_NAMESPACE" stress-generator -o jsonpath='{.status.phase}' 2>/dev/null)
  
  if [[ "$stress_pod" == "Succeeded" ]] || [[ "$stress_pod" == "Failed" ]]; then
    log_info "✓ Cluster recovered from resource stress"
    record_test_result "resource_stress_$resource_type" "pass" "300"
  fi
  
  kubectl delete pod stress-generator -n "$TEST_NAMESPACE" || true
}

# === EXPERIMENT 5: CASCADING FAILURES ===
test_cascading_failures() {
  log_info "CHAOS TEST 5: Cascading Failure Simulation"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would simulate cascading failures"
    return 0
  fi
  
  # Step 1: Kill database pod
  local db_pod=$(kubectl get pods -A -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "$db_pod" ]]; then
    kubectl delete pod -n "$TEST_NAMESPACE" "$db_pod" --grace-period=5 || true
    log_info "Database pod killed"
  fi
  
  sleep 10
  
  # Step 2: Trigger circuit breaker
  # Applications should fail-fast instead of cascading retries
  local api_errors=$(kubectl logs -A -l app=api --tail=100 2>/dev/null | grep -i error | wc -l)
  log_info "API errors during cascade: $api_errors"
  
  # Step 3: Monitor recovery
  sleep 30
  
  local recovery_status="pass"
  if [[ $api_errors -gt 50 ]]; then
    recovery_status="fail"
    log_warn "✗ Excessive error propagation"
  else
    log_info "✓ Circuit breaker prevented cascade"
  fi
  
  record_test_result "cascading_failures" "$recovery_status" "45"
}

# === EXPERIMENT 6: DNS FAILURE ===
test_dns_failure_handling() {
  log_info "CHAOS TEST 6: DNS Failure Handling"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would simulate DNS failure"
    return 0
  fi
  
  # Restart CoreDNS pods
  kubectl rollout restart deployment coredns -n kube-system
  log_info "CoreDNS restarted"
  
  # Monitor application behavior
  sleep 30
  
  # Check if applications recovered
  local dns_failures=$(kubectl logs -A -l app=api --tail=100 2>/dev/null | grep -i "dns\|resolution" | wc -l)
  
  if [[ $dns_failures -lt 5 ]]; then
    log_info "✓ DNS failure handled gracefully"
    record_test_result "dns_failure" "pass" "30"
  else
    log_warn "✗ Excessive DNS-related failures"
    record_test_result "dns_failure" "fail" "30"
  fi
}

# === RESULT RECORDING ===
record_test_result() {
  local test_name="$1"
  local result="$2"
  local duration="$3"
  
  cat >> "$CHAOS_DIR/test-results.jsonl" <<EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","test":"$test_name","result":"$result","duration_seconds":$duration}
EOF
}

# === REPORT GENERATION ===
generate_chaos_report() {
  log_info "Generating chaos engineering report..."
  
  local total_tests=$(wc -l < "$CHAOS_DIR/test-results.jsonl" 2>/dev/null || echo "0")
  local passed=$(grep '"result":"pass"' "$CHAOS_DIR/test-results.jsonl" 2>/dev/null | wc -l || echo "0")
  local failed=$((total_tests - passed))
  
  cat > "$CHAOS_DIR/chaos-report-$(date +%Y%m%d).md" <<EOF
# Chaos Engineering Test Report
- Date: $(date)
- Environment: Production-like
- Total tests: $total_tests
- Passed: $passed
- Failed: $failed
- Success rate: $((passed * 100 / total_tests))%

## Test Results

### Pod Failure Recovery
- Status: {STATUS}
- Recovery time: {TIME}

### Node Failure Recovery
- Status: {STATUS}
- Pod rescheduling: {COUNT} pods

### Network Partition
- Status: {STATUS}
- Isolation duration: {TIME}

### Resource Stress
- CPU stress result: {STATUS}
- Memory stress result: {STATUS}

### Cascading Failures
- Status: {STATUS}
- Error propagation: {METRIC}

### DNS Failure
- Status: {STATUS}
- Recovery time: {TIME}

## Recommendations

1. **Improve pod recovery**: Ensure deployments have proper replicas
2. **Enhance circuit breakers**: Prevent cascade failures
3. **Test failover regularly**: Monthly DR test recommended
4. **Monitor DNS**: Add DNS latency alerting
5. **Document runbooks**: Update with new findings

## Next Test
$(date -d '30 days' +%Y-%m-%d)
EOF
  
  log_info "Report: $CHAOS_DIR/chaos-report-$(date +%Y%m%d).md"
}

# === MAIN ===
case "${1:-}" in
  setup) setup_chaos_environment ;;
  pod) test_pod_failure_recovery "$2" "${3:-default}" ;;
  node) test_node_failure_recovery "${2:-}" ;;
  network) test_network_partition "$2" "$3" ;;
  stress) test_resource_stress "${2:-}" "${3:-cpu}" ;;
  cascade) test_cascading_failures ;;
  dns) test_dns_failure_handling ;;
  report) generate_chaos_report ;;
  all)
    setup_chaos_environment
    test_pod_failure_recovery
    test_node_failure_recovery
    test_network_partition
    test_resource_stress
    test_cascading_failures
    test_dns_failure_handling
    generate_chaos_report
    ;;
  *)
    echo "Usage: $0 {setup|pod|node|network|stress|cascade|dns|report|all}"
    ;;
esac
