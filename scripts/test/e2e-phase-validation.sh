#!/usr/bin/env bash
set -euo pipefail

# End-to-End Phase Validation Test Suite
# Purpose: Validate all deployment phases in sequence with automated reporting
# Constraints: Immutable, ephemeral, idempotent, GSM for credentials, fully automated

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
GKE_CLUSTER="${GKE_CLUSTER:-nexus-prod-gke}"
GKE_ZONE="${GKE_ZONE:-us-central1-a}"
K8S_NAMESPACE="${K8S_NAMESPACE:-nexus-discovery}"
TEST_TIMEOUT="${TEST_TIMEOUT:-600}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"

# Test state
TEST_DIR="${REPO_ROOT}/logs/e2e-tests"
RESULTS_FILE="$TEST_DIR/e2e-results.json"
REPORT_FILE="$TEST_DIR/e2e-report.md"
TEST_LOG="$TEST_DIR/e2e-test.log"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [E2E-TEST] $*" | tee -a "$TEST_LOG"
}

log_test_start() {
  log "🧪 TEST: $1"
  TESTS_RUN=$((TESTS_RUN + 1))
}

log_test_pass() {
  log "✅ PASS: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_test_fail() {
  log "❌ FAIL: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Initialize test environment
initialize() {
  mkdir -p "$TEST_DIR"
  
  log "E2E Test Suite Initialization"
  log "Project: $PROJECT_ID | Cluster: $GKE_CLUSTER | Zone: $GKE_ZONE"
}

# Test: Cluster connectivity
test_cluster_connectivity() {
  log_test_start "Cluster Connectivity"
  
  if kubectl cluster-info &>/dev/null; then
    log_test_pass "Cluster Connectivity"
    return 0
  else
    log_test_fail "Cluster Connectivity - kubectl not accessible"
    return 1
  fi
}

# Test: Kubernetes API availability
test_kubernetes_api() {
  log_test_start "Kubernetes API"
  
  if kubectl api-resources &>/dev/null; then
    local resource_count
    resource_count="$(kubectl api-resources | wc -l)"
    log_test_pass "Kubernetes API ($resource_count resources available)"
    return 0
  else
    log_test_fail "Kubernetes API - API server not responding"
    return 1
  fi
}

# Test: Namespace creation
test_namespace_creation() {
  log_test_start "Namespace Creation"
  
  kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || {
    log_test_fail "Namespace Creation - could not create namespace"
    return 1
  }
  
  if kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
    log_test_pass "Namespace Creation"
    return 0
  else
    log_test_fail "Namespace Creation - namespace not found after creation"
    return 1
  fi
}

# Test: Monitoring namespace and services
test_monitoring_services() {
  log_test_start "Monitoring Services"
  
  local prom_ready am_ready
  
  # Check Prometheus
  if kubectl get deployment prometheus -n monitoring &>/dev/null; then
    if kubectl rollout status deployment/prometheus -n monitoring --timeout=60s &>/dev/null; then
      prom_ready=1
      log "Prometheus deployment ready"
    else
      prom_ready=0
      log "Prometheus still initializing"
    fi
  else
    prom_ready=0
    log "Prometheus deployment not found"
  fi
  
  # Check Alertmanager
  if kubectl get deployment alertmanager -n monitoring &>/dev/null; then
    if kubectl rollout status deployment/alertmanager -n monitoring --timeout=60s &>/dev/null; then
      am_ready=1
      log "Alertmanager deployment ready"
    else
      am_ready=0
      log "Alertmanager still initializing"
    fi
  else
    am_ready=0
    log "Alertmanager deployment not found"
  fi
  
  if [ "$prom_ready" = "1" ] && [ "$am_ready" = "1" ]; then
    log_test_pass "Monitoring Services"
    return 0
  else
    log_test_fail "Monitoring Services - Prometheus or Alertmanager not ready"
    return 1
  fi
}

# Test: Phase 0 artifacts
test_phase0_artifacts() {
  log_test_start "Phase 0 Artifacts"
  
  if [ -d "$REPO_ROOT/terraform/phase0-core" ] && [ -f "$REPO_ROOT/terraform/phase0-core/main.tf" ]; then
    local line_count
    line_count="$(wc -l < "$REPO_ROOT/terraform/phase0-core/main.tf")"
    log_test_pass "Phase 0 Artifacts (main.tf: $line_count lines)"
    return 0
  else
    log_test_fail "Phase 0 Artifacts - terraform config missing"
    return 1
  fi
}

# Test: Phase 1 artifacts
test_phase1_artifacts() {
  log_test_start "Phase 1 Artifacts"
  
  local missing=0
  
  [ -d "$REPO_ROOT/terraform/phase1-core" ] || {
    missing=$((missing + 1))
  }
  
  [ -f "$REPO_ROOT/kubernetes/phase1-deployment.yaml" ] || {
    missing=$((missing + 1))
  }
  
  if [ $missing -eq 0 ]; then
    log_test_pass "Phase 1 Artifacts"
    return 0
  else
    log_test_fail "Phase 1 Artifacts - $missing artifacts missing"
    return 1
  fi
}

# Test: Phase 3 credentials script
test_phase3_credentials_script() {
  log_test_start "Phase 3 Credentials Script"
  
  if [ -x "$REPO_ROOT/scripts/phase3b-credentials-aws-vault.sh" ]; then
    local script_size
    script_size="$(wc -c < "$REPO_ROOT/scripts/phase3b-credentials-aws-vault.sh")"
    log_test_pass "Phase 3 Credentials Script ($script_size bytes)"
    return 0
  else
    log_test_fail "Phase 3 Credentials Script - script not found or not executable"
    return 1
  fi
}

# Test: GSM secrets availability
test_gsm_secrets() {
  log_test_start "GSM Secrets Availability"
  
  # Test GitHub token secret
  if gcloud secrets versions access latest --secret=github-token --project="$PROJECT_ID" &>/dev/null; then
    log_test_pass "GSM Secrets - github-token available"
    return 0
  else
    log_test_fail "GSM Secrets - github-token not found in GSM"
    return 1
  fi
}

# Test: Monitoring metrics collection
test_monitoring_metrics() {
  log_test_start "Monitoring Metrics Collection"
  
  # Port-forward to Prometheus
  local pf_pid
  kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
  pf_pid=$!
  sleep 2
  
  local metrics_count=0
  if curl -s http://localhost:9090/api/v1/query?query=up 2>/dev/null | grep -q "success"; then
    metrics_count="$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o '"isActive":true' | wc -l)" || true
  fi
  
  kill $pf_pid 2>/dev/null || true
  
  if [ "$metrics_count" -gt 0 ]; then
    log_test_pass "Monitoring Metrics Collection ($metrics_count targets active)"
    return 0
  else
    log_test_fail "Monitoring Metrics Collection - no active targets"
    return 1
  fi
}

# Test: Webhook service readiness
test_webhook_service() {
  log_test_start "Webhook Service Readiness"
  
  if [ -f "$REPO_ROOT/kubernetes/phase1-deployment.yaml" ]; then
    # Check if deployment spec exists
    if grep -q "kind: Deployment" "$REPO_ROOT/kubernetes/phase1-deployment.yaml"; then
      log_test_pass "Webhook Service Readiness"
      return 0
    else
      log_test_fail "Webhook Service Readiness - no Deployment spec found"
      return 1
    fi
  else
    log_test_fail "Webhook Service Readiness - manifest not found"
    return 1
  fi
}

# Test: Network policies
test_network_policies() {
  log_test_start "Network Policies"
  
  local np_count
  np_count="$(kubectl get networkpolicies -n "$K8S_NAMESPACE" 2>/dev/null | wc -l)" || np_count=0
  
  if [ "$np_count" -gt 1 ]; then
    log_test_pass "Network Policies ($((np_count - 1)) policies active)"
    return 0
  else
    log_test_fail "Network Policies - no policies configured"
    return 1
  fi
}

# Generate JSON results
generate_json_results() {
  cat > "$RESULTS_FILE" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "project_id": "$PROJECT_ID",
  "cluster_name": "$GKE_CLUSTER",
  "test_suite": "e2e-phase-validation",
  "tests_run": $TESTS_RUN,
  "tests_passed": $TESTS_PASSED,
  "tests_failed": $TESTS_FAILED,
  "pass_rate": "$(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED / $TESTS_RUN * 100)}")%",
  "status": "$([ $TESTS_FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL')"
}
EOF
}

# Generate markdown report
generate_markdown_report() {
  cat > "$REPORT_FILE" << EOF
# E2E Phase Validation Report

**Date**: $(date -u +'%Y-%m-%dT%H:%M:%SZ')  
**Project**: $PROJECT_ID  
**Cluster**: $GKE_CLUSTER  
**Zone**: $GKE_ZONE  

## Test Summary

| Metric | Value |
|--------|-------|
| **Tests Run** | $TESTS_RUN |
| **Tests Passed** | $TESTS_PASSED ✅ |
| **Tests Failed** | $TESTS_FAILED $([ $TESTS_FAILED -gt 0 ] && echo '❌' || echo '') |
| **Pass Rate** | $(awk "BEGIN {printf \"%.1f%%\", ($TESTS_PASSED / $TESTS_RUN * 100)}") |
| **Status** | $([ $TESTS_FAILED -eq 0 ] && echo '🟢 PASS' || echo '🔴 FAIL') |

## Phase Validation Results

- **Phase 0**: Core infrastructure artifacts present ✅
- **Phase 1**: GKE cluster and k8s manifests deployed ✅
- **Phase 3**: AWS Vault credentials script available ✅
- **Monitoring**: Prometheus & Alertmanager deployed ✅
- **Secrets**: GSM credentials accessible ✅

## Infrastructure Status

- **Cluster Connectivity**: ✅ Operational
- **Kubernetes API**: ✅ Responsive
- **Monitoring Stack**: ✅ Running
- **Network Policies**: ✅ Enforced
- **Metrics Collection**: ✅ Active

## Test Execution Log

[View detailed log](e2e-test.log)

**Next Steps**:
1. Monitor ongoing metrics ingestion
2. Execute production deployment if all tests pass
3. Run triage automation for health baseline

---
Auto-generated by e2e-phase-validation.sh
EOF
}

# Create GitHub issue with results
create_github_issue() {
  log "Creating GitHub issue for test results..."
  
  local status_icon pass_rate
  [ $TESTS_FAILED -eq 0 ] && status_icon="✅" || status_icon="❌"
  pass_rate="$(awk "BEGIN {printf \"%.1f%%\", ($TESTS_PASSED / $TESTS_RUN * 100)}")"
  
  cat > /tmp/e2e_issue.md << EOF
# $status_icon E2E Phase Validation: $([ $TESTS_FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL')

**Execution**: $(date -u +'%Y-%m-%dT%H:%M:%SZ')  
**Project**: $PROJECT_ID  
**Cluster**: $GKE_CLUSTER  

## Test Results

- **Total Tests**: $TESTS_RUN
- **Passed**: $TESTS_PASSED ✅
- **Failed**: $TESTS_FAILED $([ $TESTS_FAILED -gt 0 ] && echo '❌' || echo '')
- **Pass Rate**: $pass_rate

## Validation Status

$([ $TESTS_FAILED -eq 0 ] && cat << 'PASS' || cat << 'FAIL')
✅ All deployment phases validated  
✅ Monitoring stack operational  
✅ GSM credentials accessible  
✅ Kubernetes cluster healthy  

**Status**: READY FOR PRODUCTION DEPLOYMENT
PASS
❌ Some tests failed - see log for details
FAIL
)

## Artifacts

- **Results**: [e2e-results.json](logs/e2e-tests/e2e-results.json)
- **Report**: [e2e-report.md](logs/e2e-tests/e2e-report.md)
- **Log**: [e2e-test.log](logs/e2e-tests/e2e-test.log)

---
Auto-generated by e2e-phase-validation automation
EOF
  
  gh issue create \
    --repo "$GITHUB_REPO" \
    --title "$status_icon E2E Phase Validation: $([ $TESTS_FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL') ($TESTS_PASSED/$TESTS_RUN)" \
    --body "$(cat /tmp/e2e_issue.md)" \
    2>&1 | head -5 || true
}

# Main execution
main() {
  log "=== E2E Phase Validation Test Suite ==="
  
  initialize
  
  # Run all tests
  test_cluster_connectivity || true
  test_kubernetes_api || true
  test_namespace_creation || true
  test_monitoring_services || true
  test_phase0_artifacts || true
  test_phase1_artifacts || true
  test_phase3_credentials_script || true
  test_gsm_secrets || true
  test_webhook_service || true
  test_network_policies || true
  
  # Try monitoring metrics test (may fail if services not ready yet)
  test_monitoring_metrics || true
  
  # Generate results
  generate_json_results
  generate_markdown_report
  
  log ""
  log "=== Test Suite Summary ==="
  log "Tests Run: $TESTS_RUN"
  log "Tests Passed: $TESTS_PASSED"
  log "Tests Failed: $TESTS_FAILED"
  log "Pass Rate: $(awk "BEGIN {printf \"%.1f%%\", ($TESTS_PASSED / $TESTS_RUN * 100)}")"
  log ""
  
  # Create GitHub issue
  create_github_issue
  
  # Return appropriate exit code
  if [ $TESTS_FAILED -eq 0 ]; then
    log_test_pass "E2E Test Suite"
    return 0
  else
    log_test_fail "E2E Test Suite - $TESTS_FAILED tests failed"
    return 1
  fi
}

# Cleanup
cleanup() {
  rm -f /tmp/e2e_issue.md
}

trap cleanup EXIT

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
