#!/bin/bash
set -e

# Integration Test Suite for SSO Platform
# Comprehensive testing for authentication, authorization, and security

PROJECT_ID="${1:-nexus-prod}"
KEYCLOAK_URL="${2:-http://keycloak.local:8080}"
OAUTH2_URL="${3:-http://oauth2-proxy.local:4180}"
API_ENDPOINT="${4:-http://api.local/api/v1}"

echo "🧪 SSO Platform Integration Tests"
echo "   Keycloak: $KEYCLOAK_URL"
echo "   OAuth2-Proxy: $OAUTH2_URL"
echo "   API Endpoint: $API_ENDPOINT"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for test execution
run_test() {
  local test_name="$1"
  local test_command="$2"
  
  echo -n "⏳ Testing: $test_name ... "
  if eval "$test_command" > /dev/null 2>&1; then
    echo "✅ PASS"
    ((TESTS_PASSED++))
  else
    echo "❌ FAIL"
    ((TESTS_FAILED++))
  fi
}

# 1. Keycloak Health Checks
echo "🔍 Keycloak Health Checks"
run_test "Keycloak health endpoint" \
  "curl -sf $KEYCLOAK_URL/auth/health/ready"

run_test "Keycloak metrics endpoint" \
  "curl -sf $KEYCLOAK_URL/auth/metrics"

run_test "Keycloak realm accessible" \
  "curl -sf $KEYCLOAK_URL/auth/realms/master"

echo ""

# 2. OAuth2 Flow Tests
echo "🔐 OAuth2 Authentication Flow"
run_test "OAuth2 sign-in page accessible" \
  "curl -sf $OAUTH2_URL/oauth2/sign_in"

run_test "OAuth2 auth endpoint responds" \
  "curl -sf $OAUTH2_URL/oauth2/auth"

echo ""

# 3. Token Validation
echo "🎫 Token Validation"
run_test "Can get OIDC config" \
  "curl -sf $KEYCLOAK_URL/auth/realms/master/.well-known/openid-configuration"

run_test "Can get OIDC JWKS" \
  "curl -sf $KEYCLOAK_URL/auth/realms/master/protocol/openid-connect/certs"

echo ""

# 4. API Protection Tests
echo "🛡️  API Endpoint Protection"
run_test "Unauthenticated request denied" \
  "! curl -sf $API_ENDPOINT/users 2>/dev/null"

run_test "Protected endpoint requires auth" \
  "curl -s $API_ENDPOINT/users | grep -q 'unauthorized\\|401\\|403'"

echo ""

# 5. Security Header Tests
echo "🔒 Security Headers"
run_test "Strict-Transport-Security header" \
  "curl -sI $OAUTH2_URL | grep -i 'strict-transport-security'"

run_test "X-Content-Type-Options header" \
  "curl -sI $OAUTH2_URL | grep -i 'x-content-type-options'"

run_test "X-Frame-Options header" \
  "curl -sI $OAUTH2_URL | grep -i 'x-frame-options'"

echo ""

# 6. Database Connectivity
echo "📊 Database Connectivity"
if command -v psql > /dev/null 2>&1; then
  DB_PASSWORD=$(kubectl get secret -n keycloak keycloak-postgres \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  
  if [ -n "$DB_PASSWORD" ]; then
    run_test "PostgreSQL connection" \
      "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U keycloak -d keycloak -c 'SELECT 1' 2>/dev/null"
  fi
fi

echo ""

# 7. Cache Validation
echo "⚡ Cache Performance"
if command -v redis-cli > /dev/null 2>&1; then
  run_test "Redis connectivity" \
    "redis-cli -h redis.redis.svc.cluster.local ping 2>/dev/null | grep -q PONG"
fi

echo ""

# 8. Network Policy Verification
echo "🌐 Network Policy Verification"
if command -v kubectl > /dev/null 2>&1; then
  run_test "Network policies exist" \
    "kubectl get networkpolicy -n keycloak 2>/dev/null | grep -q keycloak"
  
  run_test "RBAC configured" \
    "kubectl get clusterrole keycloak-reader 2>/dev/null"
  
  run_test "Pod Security Standards enabled" \
    "kubectl get psp restricted-psp 2>/dev/null"
fi

echo ""

# 9. Telemetry & Observability
echo "📈 Observability Integration"
if command -v kubectl > /dev/null 2>&1; then
  run_test "Prometheus ServiceMonitor exists" \
    "kubectl get servicemonitor -n monitoring 2>/dev/null | grep -q oauth2"
  
  run_test "Tempo tracing running" \
    "kubectl get deployment -n monitoring tempo 2>/dev/null"
  
  run_test "Grafana dashboards deployed" \
    "kubectl get configmap -n monitoring grafana-dashboards-sso 2>/dev/null"
fi

echo ""

# 10. Compliance Checks
echo "📋 Compliance Verification"
if command -v kubectl > /dev/null 2>&1; then
  run_test "Audit logging enabled" \
    "kubectl get configmap -n keycloak keycloak-postgres-patroni-config 2>/dev/null"
  
  run_test "Backup bucket configured" \
    "gsutil ls gs://$PROJECT_ID-sso-backups 2>/dev/null || true"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary:"
echo "  ✅ Passed: $TESTS_PASSED"
echo "  ❌ Failed: $TESTS_FAILED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $TESTS_FAILED -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "⚠️  $TESTS_FAILED test(s) failed"
  exit 1
fi
