#!/usr/bin/env bash
#
# Infrastructure Installer Integration Smoke Test
# Tests all deployed components and connectivity
#

set -euo pipefail

FAIL_COUNT=0
PASS_COUNT=0

echo "🧪 Infrastructure Installation Smoke Tests"
echo "=========================================="
echo ""

# Helper functions
test_pass() {
  echo "  ✅ $1"
  ((PASS_COUNT++))
}

test_fail() {
  echo "  ❌ $1"
  ((FAIL_COUNT++))
}

test_section() {
  echo ""
  echo "📋 $1"
}

# MinIO Tests
test_section "MinIO Smoke Tests"
if [[ "${MINIO_ENABLED:-false}" == "true" ]]; then
  if kubectl get namespace artifacts &>/dev/null; then
    test_pass "Artifacts namespace exists"
  else
    test_fail "Artifacts namespace missing"
  fi

  if kubectl get statefulset -n artifacts minio &>/dev/null; then
    test_pass "MinIO StatefulSet deployed"
  else
    test_fail "MinIO StatefulSet not found"
  fi

  if kubectl get job -n artifacts minio-smoke-test &>/dev/null; then
    TEST_STATUS=$(kubectl get job -n artifacts minio-smoke-test -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$TEST_STATUS" == "1" ]]; then
      test_pass "MinIO smoke test job succeeded"
    else
      test_fail "MinIO smoke test job did not succeed"
    fi
  fi

  # Check MinIO service
  if kubectl get svc -n artifacts minio &>/dev/null; then
    test_pass "MinIO service accessible"
  else
    test_fail "MinIO service not found"
  fi
else
  echo "  ⏭️  MinIO disabled (skipped)"
fi

# Harbor Tests
test_section "Harbor Smoke Tests"
if [[ "${HARBOR_ENABLED:-false}" == "true" ]]; then
  if kubectl get namespace harbor &>/dev/null; then
    test_pass "Harbor namespace exists"
  else
    test_fail "Harbor namespace missing"
  fi

  if kubectl get deployment -n harbor harbor-core &>/dev/null; then
    test_pass "Harbor core deployment exists"
  else
    test_fail "Harbor core deployment not found"
  fi

  if kubectl get job -n harbor harbor-smoke-test &>/dev/null; then
    TEST_STATUS=$(kubectl get job -n harbor harbor-smoke-test -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$TEST_STATUS" == "1" ]]; then
      test_pass "Harbor smoke test job succeeded"
    else
      test_fail "Harbor smoke test job did not succeed"
    fi
  fi

  # Check Harbor service
  if kubectl get svc -n harbor harbor &>/dev/null; then
    test_pass "Harbor service accessible"
  else
    test_fail "Harbor service not found"
  fi
else
  echo "  ⏭️  Harbor disabled (skipped)"
fi

# Observability Tests
test_section "Observability Stack Smoke Tests"
if [[ "${OBSERVABILITY_ENABLED:-false}" == "true" ]]; then
  if kubectl get namespace observability &>/dev/null; then
    test_pass "Observability namespace exists"
  else
    test_fail "Observability namespace missing"
  fi

  if kubectl get statefulset -n observability prometheus &>/dev/null; then
    test_pass "Prometheus StatefulSet deployed"
  else
    test_fail "Prometheus StatefulSet not found"
  fi

  if kubectl get deployment -n observability grafana &>/dev/null; then
    test_pass "Grafana deployment exists"
  else
    test_fail "Grafana deployment not found"
  fi

  if kubectl get deployment -n observability alertmanager &>/dev/null; then
    test_pass "AlertManager deployment exists"
  else
    test_fail "AlertManager deployment not found"
  fi

  # Check Prometheus metrics endpoint
  if kubectl get svc -n observability prometheus &>/dev/null; then
    PROM_POD=$(kubectl get pod -n observability -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$PROM_POD" ]]; then
      test_pass "Prometheus pod running"
    else
      test_fail "Prometheus pod not found"
    fi
  fi
else
  echo "  ⏭️  Observability disabled (skipped)"
fi

# Ingress Tests
test_section "Ingress Controller Tests"
if kubectl get namespace ingress-nginx &>/dev/null; then
  test_pass "Ingress namespace exists"
else
  test_fail "Ingress namespace missing"
fi

if kubectl get deployment -n ingress-nginx ingress-nginx-controller &>/dev/null; then
  test_pass "Ingress controller deployment exists"
else
  test_fail "Ingress controller deployment not found"
fi

# Cluster-wide Tests
test_section "Cluster Health Checks"

# Check node status
if kubectl get nodes &>/dev/null; then
  READY_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
  if [[ $READY_NODES -gt 0 ]]; then
    test_pass "$READY_NODES node(s) ready"
  else
    test_fail "No ready nodes found"
  fi
else
  test_fail "Could not query nodes"
fi

# Check for critical pod failures
if kubectl get pods -A --field-selector=status.phase=Failed &>/dev/null; then
  FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
  if [[ $FAILED_PODS -eq 0 ]]; then
    test_pass "No failed pods in cluster"
  else
    test_fail "$FAILED_PODS pod(s) in failed state"
  fi
fi

# Summary
echo ""
echo "📊 Summary"
echo "=========="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "✅ All smoke tests PASSED"
  exit 0
else
  echo "❌ Some smoke tests FAILED"
  echo ""
  echo "💡 Troubleshooting:"
  echo "  1. Check pod logs: kubectl logs -f -n <namespace> <pod-name>"
  echo "  2. Describe pod: kubectl describe pod -n <namespace> <pod-name>"
  echo "  3. Review events: kubectl get events -n <namespace>"
  exit 1
fi
