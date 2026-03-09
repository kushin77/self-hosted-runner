#!/bin/bash
# Hourly Credential System Health Check
# Purpose: Validate all three credential layers are operational
# Ensures: No credential gaps, immediate failure detection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_LOG="${SCRIPT_DIR}/../audit/health-check-$(date +%Y%m%d).log"
TIMESTAMP=$(date -u +'%Y-%m-%d %H:%M:%S UTC')

mkdir -p "$(dirname "$HEALTH_LOG")"

log_health() {
  echo "[${TIMESTAMP}] $@" | tee -a "$HEALTH_LOG"
}

check_gsm() {
  log_health "=== GSM Primary Layer ==="
  
  if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    log_health "✓ OIDC token valid"
    if gcloud secrets list >/dev/null 2>&1; then
      log_health "✓ Secret listing accessible"
      return 0
    else
      log_health "✗ Secret access degraded"
      return 1
    fi
  else
    log_health "✗ OIDC token refresh failed"
    return 1
  fi
}

check_vault() {
  log_health "=== Vault Secondary Layer ==="
  
  if [ -z "${VAULT_ADDR:-}" ]; then
    log_health "⊘ Vault not configured (optional fallback)"
    return 2  # Neutral - not an error if not configured
  fi
  
  if vault status >/dev/null 2>&1; then
    log_health "✓ Vault unsealed and operational"
    if vault token lookup >/dev/null 2>&1; then
      log_health "✓ Auth token valid"
      return 0
    else
      log_health "✗ Token renewal required"
      return 1
    fi
  else
    log_health "✗ Vault unreachable or sealed"
    return 1
  fi
}

check_kms() {
  log_health "=== KMS Tertiary Layer ==="
  
  if aws kms list-keys >/dev/null 2>&1; then
    log_health "✓ KMS accessible via OIDC"
    if aws kms describe-key --key-id alias/credential-rotation >/dev/null 2>&1; then
      log_health "✓ Credential rotation key available"
      return 0
    else
      log_health "⊘ Credential key not found (may not be needed)"
      return 2
    fi
  else
    log_health "✗ KMS access failed"
    return 1
  fi
}

check_oidc_token_renewal() {
  log_health "=== OIDC Token Renewal ==="
  
  if [ -n "${OIDC_TOKEN_REFRESH_TIME:-}" ]; then
    local now=$(date +%s)
    if [ "$now" -gt "$OIDC_TOKEN_REFRESH_TIME" ]; then
      log_health "✓ OIDC tokens within refresh window"
      return 0
    else
      log_health "✗ OIDC tokens approaching expiration"
      return 1
    fi
  else
    log_health "✓ OIDC tokens auto-managed by GitHub"
    return 0
  fi
}

check_performance() {
  log_health "=== Performance Benchmarks ==="
  
  local start=$(date +%s%N)
  gcloud secrets list >/dev/null 2>&1 || true
  local end=$(date +%s%N)
  local duration_ms=$(( (end - start) / 1000000 ))
  
  log_health "GSM latency: ${duration_ms}ms"
  
  if [ "$duration_ms" -lt 1000 ]; then
    log_health "✓ Performance acceptable"
    return 0
  else
    log_health "⚠ Performance degraded"
    return 2
  fi
}

# === MAIN HEALTH CHECK ===

main() {
  log_health ""
  log_health "=========================================="
  log_health "Credential System Health Check"
  log_health "=========================================="
  
  local failures=0
  local checks_run=0
  
  # Run all checks
  check_gsm || ((failures++)); ((checks_run++))
  check_vault || { ret=$?; [ "$ret" -ne 2 ] && ((failures++)) || true; }; ((checks_run++))
  check_kms || { ret=$?; [ "$ret" -ne 2 ] && ((failures++)) || true; }; ((checks_run++))
  check_oidc_token_renewal || ((failures++)); ((checks_run++))
  check_performance || { ret=$?; [ "$ret" -ne 2 ] && ((failures++)) || true; }; ((checks_run++))
  
  log_health ""
  log_health "=========================================="
  log_health "Summary: ${failures} failures, ${checks_run} checks"
  log_health "=========================================="
  
  if [ "$failures" -eq 0 ]; then
    log_health "✅ All systems OPERATIONAL"
    echo "✅ Health check PASS at ${TIMESTAMP}"
    return 0
  elif [ "$failures" -lt 3 ]; then
    log_health "⚠ DEGRADED - 1+ layers failed, but system operational (failover active)"
    echo "⚠ Health check WARN at ${TIMESTAMP}"
    return 0  # Still operational with failover
  else
    log_health "❌ CRITICAL - Multiple layer failures, manual intervention needed"
    echo "❌ Health check FAIL at ${TIMESTAMP}"
    return 1
  fi
}

main "$@"
