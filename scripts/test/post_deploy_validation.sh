#!/usr/bin/env bash
set -euo pipefail

# Post-Deployment Validation & Monitoring Setup
# Validates all deployment requirements and configures observability
# Output: JSONL validation report

ENDPOINT="${ENDPOINT:-http://localhost:8000}"
REPORT_FILE="/tmp/post_deploy_validation_$(date +%s).jsonl"

log_validation() {
  local check="$1"
  local status="$2"  # PASS/FAIL
  local details="${3:-}"
  
  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg check "$check" \
    --arg status "$status" \
    --arg details "$details" \
    '{timestamp: $ts, validation_check: $check, status: $status, details: $details}' \
    >> "$REPORT_FILE"
  
  echo "  $check: $status $([ -n "$details" ] && echo "($details)" || echo "")"
}

echo "========================================"
echo "Post-Deployment Validation & Monitoring"
echo "========================================"
echo "Endpoint: $ENDPOINT"
echo "Report: $REPORT_FILE"
echo ""

# Check 1: API is reachable
echo "[1] Checking API reachability..."
if curl -sf "$ENDPOINT/api/v1/secrets/health" > /dev/null 2>&1; then
  log_validation "api_reachable" "PASS" "API responding"
else
  log_validation "api_reachable" "FAIL" "API unreachable at $ENDPOINT"
  exit 1
fi

# Check 2: Health endpoint structure
echo "[2] Validating health endpoint..."
HEALTH=$(curl -sf "$ENDPOINT/api/v1/secrets/health")
if echo "$HEALTH" | jq -e '.status' > /dev/null 2>&1; then
  STATUS=$(echo "$HEALTH" | jq -r '.status')
  log_validation "health_structure" "PASS" "Health response valid (status: $STATUS)"
else
  log_validation "health_structure" "FAIL" "Health response missing required fields"
fi

# Check 3: Provider resolution
echo "[3] Testing provider resolution..."
RESOLVE=$(curl -sf "$ENDPOINT/api/v1/secrets/resolve")
if echo "$RESOLVE" | jq -e '.primary_provider' > /dev/null 2>&1; then
  PRIMARY=$(echo "$RESOLVE" | jq -r '.primary_provider')
  log_validation "provider_resolve" "PASS" "Primary provider: $PRIMARY"
else
  log_validation "provider_resolve" "FAIL" "Unable to resolve primary provider"
fi

# Check 4: Credentials endpoint exists
echo "[4] Testing credentials endpoint..."
if curl -sf "$ENDPOINT/api/v1/secrets/credentials?name=test" > /dev/null 2>&1; then
  log_validation "credentials_endpoint" "PASS" "Credentials endpoint working"
else
  log_validation "credentials_endpoint" "FAIL" "Credentials endpoint not responding"
fi

# Check 5: Migrations endpoint exists
echo "[5] Testing migrations endpoint..."
if curl -sf "$ENDPOINT/api/v1/secrets/migrations" > /dev/null 2>&1; then
  log_validation "migrations_endpoint" "PASS" "Migrations endpoint working"
else
  log_validation "migrations_endpoint" "FAIL" "Migrations endpoint not responding"
fi

# Check 6: Audit endpoint exists
echo "[6] Testing audit endpoint..."
if curl -sf "$ENDPOINT/api/v1/secrets/audit" > /dev/null 2>&1; then
  log_validation "audit_endpoint" "PASS" "Audit endpoint working"
else
  log_validation "audit_endpoint" "FAIL" "Audit endpoint not responding"
fi

# Check 7: Service logs accessible
echo "[7] Checking service logs..."
if sudo journalctl -u canonical-secrets-api.service -n 5 > /dev/null 2>&1; then
  log_validation "service_logs" "PASS" "Systemd logs accessible"
else
  log_validation "service_logs" "FAIL" "Cannot access systemd logs"
fi

# Check 8: Environment file exists and is readable
echo "[8] Checking environment configuration..."
if [ -f "/etc/canonical_secrets.env" ] && sudo test -r "/etc/canonical_secrets.env"; then
  log_validation "env_config" "PASS" "Environment file configured"
else
  log_validation "env_config" "FAIL" "Environment file missing or unreadable"
fi

# Check 9: Service is enabled
echo "[9] Checking service enablement..."
if sudo systemctl is-enabled canonical-secrets-api.service > /dev/null 2>&1; then
  log_validation "service_enabled" "PASS" "Service enabled for auto-start"
else
  log_validation "service_enabled" "FAIL" "Service not enabled"
fi

# Check 10: Service is running
echo "[10] Checking service status..."
if sudo systemctl is-active canonical-secrets-api.service > /dev/null 2>&1; then
  log_validation "service_running" "PASS" "Service is running"
else
  log_validation "service_running" "FAIL" "Service is not running"
fi

# Summary
echo ""
echo "========================================"
echo "Validation Summary"
echo "========================================"
PASSED=$(jq -s 'map(select(.status == "PASS")) | length' "$REPORT_FILE")
FAILED=$(jq -s 'map(select(.status == "FAIL")) | length' "$REPORT_FILE")
TOTAL=$((PASSED + FAILED))

echo "Total: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo "✅ All validation checks passed!"
  cat "$REPORT_FILE" | jq -s '.'
  exit 0
else
  echo "❌ $FAILED validation(s) failed!"
  cat "$REPORT_FILE" | jq -s '.'
  exit 1
fi
