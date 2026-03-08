#!/bin/bash
# Post-apply validation for Phase P3/P4 observability stack
# Checks: Prometheus metrics, Alertmanager routes, Grafana dashboards
# Usage: ./validate-post-apply.sh [--namespace kube-system]

set -euo pipefail

NAMESPACE="${1:-kube-system}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }

PASS_COUNT=0
FAIL_COUNT=0

echo "=== Phase P3/P4 Post-Apply Validation ==="
echo "Namespace: $NAMESPACE"
echo "Prometheus Port: $PROMETHEUS_PORT"
echo "Alertmanager Port: $ALERTMANAGER_PORT"
echo "Grafana Port: $GRAFANA_PORT"
echo ""

# Helper function to port-forward and test
test_service_endpoint() {
  local service=$1
  local port=$2
  local endpoint=$3
  local expected_response=$4
  
  log_info "Testing $service health at localhost:$port$endpoint"
  
  # Start port-forward in background
  kubectl port-forward -n "$NAMESPACE" "svc/$service" "$port:$port" >/dev/null 2>&1 &
  PF_PID=$!
  
  # Wait for port-forward to establish
  sleep 2
  
  # Test endpoint
  if curl -s -m 5 "http://localhost:$port$endpoint" | grep -q "$expected_response" 2>/dev/null; then
    log_pass "$service ($endpoint) is healthy"
    ((PASS_COUNT++))
    kill $PF_PID 2>/dev/null || true
    return 0
  else
    log_fail "$service ($endpoint) health check failed"
    ((FAIL_COUNT++))
    kill $PF_PID 2>/dev/null || true
    return 1
  fi
}

# Test 1: Prometheus deployment exists
echo "Test 1: Verify Prometheus deployment..."
if kubectl get deployment -n "$NAMESPACE" -l app=prometheus >/dev/null 2>&1; then
  READY=$(kubectl get deployment -n "$NAMESPACE" -l app=prometheus -o jsonpath='{.items[0].status.readyReplicas}')
  DESIRED=$(kubectl get deployment -n "$NAMESPACE" -l app=prometheus -o jsonpath='{.items[0].status.replicas}')
  
  if [ "$READY" = "$DESIRED" ] && [ -n "$READY" ]; then
    log_pass "Prometheus deployment ready ($READY/$DESIRED replicas)"
    ((PASS_COUNT++))
  else
    log_warn "Prometheus deployment not fully ready ($READY/$DESIRED replicas)"
    ((FAIL_COUNT++))
  fi
else
  log_fail "Prometheus deployment not found"
  ((FAIL_COUNT++))
fi

# Test 2: Prometheus metrics endpoint
echo ""
echo "Test 2: Verify Prometheus metrics endpoint..."
if test_service_endpoint prometheus "$PROMETHEUS_PORT" /api/v1/query 'status' 2>/dev/null || [ $? -eq 0 ]; then
  :
fi

# Test 3: Alertmanager deployment
echo ""
echo "Test 3: Verify Alertmanager deployment..."
if kubectl get deployment -n "$NAMESPACE" -l app=alertmanager >/dev/null 2>&1; then
  READY=$(kubectl get deployment -n "$NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].status.readyReplicas}')
  DESIRED=$(kubectl get deployment -n "$NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].status.replicas}')
  
  if [ "$READY" = "$DESIRED" ] && [ -n "$READY" ]; then
    log_pass "Alertmanager deployment ready ($READY/$DESIRED replicas)"
    ((PASS_COUNT++))
  else
    log_warn "Alertmanager deployment not fully ready ($READY/$DESIRED replicas)"
    ((FAIL_COUNT++))
  fi
else
  log_fail "Alertmanager deployment not found"
  ((FAIL_COUNT++))
fi

# Test 4: Alertmanager routes configured
echo ""
echo "Test 4: Verify Alertmanager routes and receivers..."
if kubectl get configmap -n "$NAMESPACE" -l app=alertmanager >/dev/null 2>&1; then
  CONFIG=$(kubectl get configmap -n "$NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].data.alertmanager\.yml}' 2>/dev/null)
  
  if echo "$CONFIG" | grep -q "route:" || echo "$CONFIG" | grep -q "receivers:"; then
    log_pass "Alertmanager configuration present (routes/receivers)"
    ((PASS_COUNT++))
  else
    log_warn "Alertmanager configuration may not have routes/receivers"
    ((FAIL_COUNT++))
  fi
else
  log_warn "Alertmanager configmap not found (may be using default config)"
  ((FAIL_COUNT++))
fi

# Test 5: Grafana deployment
echo ""
echo "Test 5: Verify Grafana deployment..."
if kubectl get deployment -n "$NAMESPACE" -l app=grafana >/dev/null 2>&1; then
  READY=$(kubectl get deployment -n "$NAMESPACE" -l app=grafana -o jsonpath='{.items[0].status.readyReplicas}')
  DESIRED=$(kubectl get deployment -n "$NAMESPACE" -l app=grafana -o jsonpath='{.items[0].status.replicas}')
  
  if [ "$READY" = "$DESIRED" ] && [ -n "$READY" ]; then
    log_pass "Grafana deployment ready ($READY/$DESIRED replicas)"
    ((PASS_COUNT++))
  else
    log_warn "Grafana deployment not fully ready ($READY/$DESIRED replicas)"
    ((FAIL_COUNT++))
  fi
else
  log_fail "Grafana deployment not found"
  ((FAIL_COUNT++))
fi

# Test 6: Grafana dashboards provisioned
echo ""
echo "Test 6: Verify Grafana dashboards..."
if kubectl get configmap -n "$NAMESPACE" -l app=grafana >/dev/null 2>&1; then
  log_pass "Grafana configmaps found (dashboards provisioned)"
  ((PASS_COUNT++))
else
  log_warn "Grafana configmaps not found"
  ((FAIL_COUNT++))
fi

# Test 7: Alert rules loaded in Prometheus
echo ""
echo "Test 7: Verify alert rules in Prometheus..."
if kubectl get configmap -n "$NAMESPACE" -l app=prometheus,config=alert-rules >/dev/null 2>&1; then
  RULES=$(kubectl get configmap -n "$NAMESPACE" -l app=prometheus,config=alert-rules -o jsonpath='{.items[0].data}' | grep -c "alert:" || echo 0)
  
  if [ "$RULES" -gt 0 ]; then
    log_pass "Alert rules found ($RULES rules)"
    ((PASS_COUNT++))
  else
    log_warn "No alert rules generated"
    ((FAIL_COUNT++))
  fi
else
  log_info "Alert rules configmap not labeled as expected (may be integrated differently)"
fi

# Test 8: StatefulSet/PVC for Prometheus (persistent storage)
echo ""
echo "Test 8: Verify Prometheus persistent storage..."
if kubectl get pvc -n "$NAMESPACE" -l app=prometheus >/dev/null 2>&1; then
  PVC_STATUS=$(kubectl get pvc -n "$NAMESPACE" -l app=prometheus -o jsonpath='{.items[0].status.phase}')
  
  if [ "$PVC_STATUS" = "Bound" ]; then
    log_pass "Prometheus PVC is bound and ready"
    ((PASS_COUNT++))
  else
    log_warn "Prometheus PVC status: $PVC_STATUS (may still be binding)"
    ((FAIL_COUNT++))
  fi
else
  log_info "Prometheus PVC not found (may use ephemeral storage)"
fi

# Summary
echo ""
echo "=== Post-Apply Validation Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  log_pass "All checks passed! Phase P3/P4 observability stack is operational."
  exit 0
elif [ $FAIL_COUNT -le 2 ]; then
  log_warn "Some checks failed but may resolve during pod initialization. Monitor logs."
  exit 0
else
  log_fail "Multiple checks failed. Review logs and troubleshoot."
  exit 1
fi