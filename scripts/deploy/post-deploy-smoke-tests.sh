#!/usr/bin/env bash
# ============================================================================
# POST-DEPLOY SMOKE TESTS — Immutable, Idempotent Health Verification
# ============================================================================
# Runs basic health checks on deployed services. If any check fails,
# initiates automated rollback to the previous known-good revision.
# Usage: post-deploy-smoke-tests.sh <service_name> [region] [max_attempts]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="${1:?SERVICE_NAME required (e.g., nexus-shield-portal-backend)}"
GCP_REGION="${2:-us-central1}"
MAX_ATTEMPTS="${3:-30}"
ATTEMPT_INTERVAL=2

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo)}"
: ${PROJECT:?GCP_PROJECT not set}

log_info() { echo "[INFO] $*" >&2; }
log_success() { echo "[✓ SUCCESS] $*" >&2; }
log_error() { echo "[✗ ERROR] $*" >&2; }
log_warn() { echo "[⚠ WARN] $*" >&2; }

# ============================================================================
# HEALTH CHECKS
# ============================================================================

get_service_url() {
  gcloud run services describe "$SERVICE_NAME" \
    --platform managed --project "$PROJECT" --region "$GCP_REGION" \
    --format='value(status.url)' 2>/dev/null || echo ""
}

wait_for_service_ready() {
  log_info "Waiting for service $SERVICE_NAME to become ready..."
  local attempt=0
  while [ $attempt -lt "$MAX_ATTEMPTS" ]; do
    local url
    url=$(get_service_url) && [ -n "$url" ] && break
    attempt=$((attempt + 1))
    [ $attempt -lt "$MAX_ATTEMPTS" ] && sleep "$ATTEMPT_INTERVAL"
  done
  
  if [ -z "$url" ]; then
    log_error "Service did not become ready within $((MAX_ATTEMPTS * ATTEMPT_INTERVAL))s"
    return 1
  fi
  echo "$url"
}

check_health_endpoint() {
  local url="$1"
  log_info "Checking health endpoint: $url/health"
  if curl -sSf "${url}/health" -m 10 >/dev/null 2>&1; then
    log_success "Health check passed"
    return 0
  else
    log_error "Health check failed"
    return 1
  fi
}

check_readiness_endpoint() {
  local url="$1"
  log_info "Checking readiness endpoint: $url/ready"
  if curl -sSf "${url}/ready" -m 10 >/dev/null 2>&1; then
    log_success "Readiness check passed"
    return 0
  else
    log_error "Readiness check failed"
    return 1
  fi
}

check_status_endpoint() {
  local url="$1"
  log_info "Checking status endpoint: $url/api/v1/status"
  if curl -sSf "${url}/api/v1/status" -m 10 >/dev/null 2>&1; then
    log_success "Status check passed"
    return 0
  else
    log_warn "Status endpoint unavailable (not critical)"
    return 0
  fi
}

# ============================================================================
# ROLLBACK
# ============================================================================

get_current_revision() {
  gcloud run services describe "$SERVICE_NAME" \
    --platform managed --project "$PROJECT" --region "$GCP_REGION" \
    --format='value(status.traffic[0].revisionName)' 2>/dev/null || echo ""
}

get_previous_revision() {
  gcloud run revisions list --service="$SERVICE_NAME" \
    --platform managed --project "$PROJECT" --region "$GCP_REGION" \
    --format='value(name)' --limit=2 2>/dev/null | sed -n '2p' || echo ""
}

rollback_to_previous() {
  local prev
  prev=$(get_previous_revision)
  
  if [ -z "$prev" ]; then
    log_error "No previous revision found; cannot rollback"
    return 1
  fi
  
  log_warn "Rolling back to previous revision: $prev"
  gcloud run services update-traffic "$SERVICE_NAME" \
    --region="$GCP_REGION" --project="$PROJECT" \
    --to-revisions="${prev}=100" --platform=managed >/dev/null 2>&1
  
  log_success "Rollback initiated to $prev"
}

# ============================================================================
# MAIN FLOW
# ============================================================================

main() {
  log_info "=== POST-DEPLOY SMOKE TESTS ==="
  log_info "Service: $SERVICE_NAME (region: $GCP_REGION)"
  
  # Wait for service to be ready
  SERVICE_URL=$(wait_for_service_ready) || {
    log_error "Service failed to become ready; aborting tests"
    exit 1
  }
  log_success "Service URL: $SERVICE_URL"
  
  # Run health checks
  local checks_passed=0
  local checks_failed=0
  
  if check_health_endpoint "$SERVICE_URL"; then
    ((checks_passed++))
  else
    ((checks_failed++))
  fi
  
  if check_readiness_endpoint "$SERVICE_URL"; then
    ((checks_passed++))
  else
    ((checks_failed++))
  fi
  
  if check_status_endpoint "$SERVICE_URL"; then
    ((checks_passed++))
  else
    ((checks_failed++))
  fi
  
  log_info "Smoke tests: $checks_passed passed, $checks_failed failed"
  
  # If any critical check fails, rollback
  if [ $checks_failed -gt 0 ]; then
    log_error "Smoke tests failed; initiating rollback..."
    if rollback_to_previous; then
      log_error "DEPLOYMENT FAILED AND ROLLED BACK"
      exit 2
    else
      log_error "DEPLOYMENT FAILED — ROLLBACK ALSO FAILED (manual intervention needed)"
      exit 3
    fi
  fi
  
  log_success "=== ALL SMOKE TESTS PASSED ==="
  exit 0
}

main "$@"
