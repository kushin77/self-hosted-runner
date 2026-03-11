#!/usr/bin/env bash
set -euo pipefail

# Post-Deployment Validation & Monitoring Setup
# Validates all deployment requirements and configures observability
# Output: JSONL validation report

ENDPOINT="${ENDPOINT:-http://192.168.168.42:8000}"
ONPREM_HOST="${ONPREM_HOST:-192.168.168.42}"
ONPREM_USER="${ONPREM_USER:-akushnir}"
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

# Fetch SSH key from GSM/Vault/KMS for remote execution if no SSH key provided
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRED_SCRIPT="${REPO_ROOT}/scripts/ops/fetch_credentials.sh"
# Only source credential fetcher if an SSH key is not already supplied
if [ -z "${SSH_KEY_PATH:-}" ] && [ -f "$CRED_SCRIPT" ]; then
  set +e
  # shellcheck source=/dev/null
  source "$CRED_SCRIPT" 2>/dev/null || true
  set -e
fi

# Check 1: API is reachable (try canonical health paths, fall back to SSH)
echo "[1] Checking API reachability..."
HEALTH_OK=false
http_status() {
  curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"
}

if [ "$(http_status "$ENDPOINT/api/v1/secrets/health")" = "200" ]; then
  HEALTH_PATH="/api/v1/secrets/health"
  HEALTH_OK=true
elif [ "$(http_status "$ENDPOINT/api/v1/secrets/health/all")" = "200" ]; then
  HEALTH_PATH="/api/v1/secrets/health/all"
  HEALTH_OK=true
fi

if [ "$HEALTH_OK" = true ]; then
  log_validation "api_reachable" "PASS" "API responding at $ENDPOINT (health: $HEALTH_PATH)"
  REMOTE_MODE=false
elif [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH:-}" ] && [ -n "$ONPREM_HOST" ]; then
  echo "  Direct API unreachable; falling back to SSH remote validation on $ONPREM_HOST"
  log_validation "api_reachable" "PASS" "API checked via SSH to $ONPREM_HOST"
  REMOTE_MODE=true
  HEALTH_PATH="/api/v1/secrets/health"
else
  log_validation "api_reachable" "FAIL" "API unreachable at $ENDPOINT and no SSH key available"
  exit 1
fi

# api_curl will use HEALTH_PATH when checking health structure

# SSH helper — runs a command on the on-prem host via the secret-fetched key.
# Usage: ssh_exec "command" (returns stdout; exit code forwarded)
ssh_exec() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      -i "$SSH_KEY_PATH" "$ONPREM_USER@$ONPREM_HOST" "$1" 2>/dev/null
}

# curl helper — uses SSH tunnel when in REMOTE_MODE
api_curl() {
  local path="$1"
  if [ "$REMOTE_MODE" = true ]; then
    ssh_exec "curl -sf http://localhost:8000${path}" 2>/dev/null
  else
    curl -sf --connect-timeout 5 "${ENDPOINT}${path}" 2>/dev/null
  fi
}

# Check 2: Health endpoint structure
echo "[2] Validating health endpoint..."
# Use the detected HEALTH_PATH if set (from reachability check)
if [ -n "${HEALTH_PATH:-}" ]; then
  CHECK_PATH="$HEALTH_PATH"
else
  CHECK_PATH="/api/v1/secrets/health/all"
fi

if HEALTH=$(api_curl "$CHECK_PATH"); then
  if echo "$HEALTH" | jq -e '.providers' > /dev/null 2>&1; then
    log_validation "health_structure" "PASS" "Health response contains providers list"
  elif echo "$HEALTH" | jq -e '.status' > /dev/null 2>&1; then
    STATUS=$(echo "$HEALTH" | jq -r '.status')
    log_validation "health_structure" "PASS" "Health response valid (status: $STATUS)"
  else
    log_validation "health_structure" "FAIL" "Health response missing required fields"
  fi
else
  log_validation "health_structure" "FAIL" "Health endpoint not responding"
fi

# Check 3: Provider resolution (POST with a test secret name)
echo "[3] Testing provider resolution..."
TEST_SECRET_NAME="postdeploy-test-$(date +%s)"
if [ "$REMOTE_MODE" = true ]; then
  RESOLVE=$(ssh_exec "curl -s -X POST 'http://localhost:8000/api/v1/secrets/resolve?secret_name=$TEST_SECRET_NAME'" ) || true
else
  RESOLVE=$(curl -s -X POST "${ENDPOINT}/api/v1/secrets/resolve?secret_name=$TEST_SECRET_NAME") || true
fi

if echo "$RESOLVE" | jq -e '.resolved_provider // .primary_provider' > /dev/null 2>&1; then
  PRIMARY=$(echo "$RESOLVE" | jq -r '.resolved_provider // .primary_provider')
  log_validation "provider_resolve" "PASS" "Primary provider: $PRIMARY"
else
  log_validation "provider_resolve" "FAIL" "Unable to resolve primary provider"
fi

# Check 4: Credentials endpoint exists
echo "[4] Testing credentials endpoint..."
if api_curl "/api/v1/secrets/credentials?name=test" > /dev/null 2>&1; then
  log_validation "credentials_endpoint" "PASS" "Credentials endpoint working"
else
  log_validation "credentials_endpoint" "FAIL" "Credentials endpoint not responding"
fi

# Check 5: Migrations endpoint exists
echo "[5] Testing migrations endpoint..."
if api_curl "/api/v1/secrets/migrations" > /dev/null 2>&1; then
  log_validation "migrations_endpoint" "PASS" "Migrations endpoint working"
else
  log_validation "migrations_endpoint" "FAIL" "Migrations endpoint not responding"
fi

# Check 6: Audit endpoint exists
echo "[6] Testing audit endpoint..."
if api_curl "/api/v1/secrets/audit" > /dev/null 2>&1; then
  log_validation "audit_endpoint" "PASS" "Audit endpoint working"
else
  log_validation "audit_endpoint" "FAIL" "Audit endpoint not responding"
fi

# Check 7: Service logs accessible
echo "[7] Checking service logs..."
if [ "$REMOTE_MODE" = true ]; then
  if ssh_exec "sudo -n journalctl -u canonical-secrets-api.service -n 5" > /dev/null 2>&1; then
    log_validation "service_logs" "PASS" "Systemd logs accessible (via SSH)"
  else
    log_validation "service_logs" "FAIL" "Cannot access systemd logs (via SSH)"
  fi
else
  if sudo -n journalctl -u canonical-secrets-api.service -n 5 > /dev/null 2>&1; then
    log_validation "service_logs" "PASS" "Systemd logs accessible"
  else
    log_validation "service_logs" "FAIL" "Cannot access systemd logs (sudo unavailable or no logs)"
  fi
fi

## Check 8: Environment file exists and is readable
## Allows override with CANONICAL_ENV_FILE for local testing
ENV_FILE=${CANONICAL_ENV_FILE:-/etc/canonical_secrets.env}
echo "[8] Checking environment configuration..."
if [ "$REMOTE_MODE" = true ]; then
  # remote check uses sudo non-interactively
  if ssh_exec "test -f $ENV_FILE && sudo -n test -r $ENV_FILE" 2>/dev/null; then
    log_validation "env_config" "PASS" "Environment file configured (via SSH)"
  else
    log_validation "env_config" "FAIL" "Environment file missing or unreadable (via SSH)"
  fi
else
  if [ -f "$ENV_FILE" ] && [ -r "$ENV_FILE" ]; then
    log_validation "env_config" "PASS" "Environment file configured"
  else
    log_validation "env_config" "FAIL" "Environment file missing or unreadable"
  fi
fi

# Check 9: Service is enabled
echo "[9] Checking service enablement..."
  if [ "$REMOTE_MODE" = true ]; then
    if ssh_exec "sudo -n systemctl is-enabled canonical-secrets-api.service" > /dev/null 2>&1; then
      log_validation "service_enabled" "PASS" "Service enabled for auto-start (via SSH)"
    else
      log_validation "service_enabled" "FAIL" "Service not enabled (via SSH)"
    fi
  else
    if sudo -n systemctl is-enabled canonical-secrets-api.service > /dev/null 2>&1; then
      log_validation "service_enabled" "PASS" "Service enabled for auto-start"
    else
      log_validation "service_enabled" "FAIL" "Service not enabled (sudo unavailable or disabled)"
    fi
  fi

# Check 10: Service is running
echo "[10] Checking service status..."
  if [ "$REMOTE_MODE" = true ]; then
    if ssh_exec "sudo -n systemctl is-active canonical-secrets-api.service" > /dev/null 2>&1; then
      log_validation "service_running" "PASS" "Service is running (via SSH)"
    else
      log_validation "service_running" "FAIL" "Service is not running (via SSH)"
    fi
  else
    if sudo -n systemctl is-active canonical-secrets-api.service > /dev/null 2>&1; then
      log_validation "service_running" "PASS" "Service is running"
    else
      log_validation "service_running" "FAIL" "Service is not running (sudo unavailable or inactive)"
    fi
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
  VALIDATION_EXIT=0
else
  echo "❌ $FAILED validation(s) failed!"
  cat "$REPORT_FILE" | jq -s '.'
  VALIDATION_EXIT=1
fi

# --- Post-validation: run full verifier, upload evidence, optionally comment on GitHub issue
VERIFIER_SCRIPT="${VERIFIER_SCRIPT:-$REPO_ROOT/scripts/ops/verify_deployment.sh}"
VERIFIER_OUTPUT="/tmp/deployment_verification_$(date +%s).txt"
S3_BUCKET="${S3_BUCKET:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ISSUE_OWNER="${ISSUE_OWNER:-kushin77}"
ISSUE_REPO="${ISSUE_REPO:-self-hosted-runner}"
ISSUE_NUMBER="${ISSUE_NUMBER:-2594}"

echo "[post] Running verifier: $VERIFIER_SCRIPT"
if [ -x "$VERIFIER_SCRIPT" ]; then
  set +e
  ONPREM_HOST="$ONPREM_HOST" ONPREM_USER="$ONPREM_USER" "$VERIFIER_SCRIPT" |& tee "$VERIFIER_OUTPUT"
  VERIFIER_EXIT=${PIPESTATUS[0]}
  set -e
  if [ "$VERIFIER_EXIT" -eq 0 ]; then
    log_validation "verifier_run" "PASS" "Verifier completed successfully"
  else
    log_validation "verifier_run" "FAIL" "Verifier reported issues (exit: $VERIFIER_EXIT)"
  fi
else
  echo "Verifier script not found or not executable: $VERIFIER_SCRIPT"
  log_validation "verifier_run" "FAIL" "Verifier missing: $VERIFIER_SCRIPT"
  VERIFIER_EXIT=2
fi

# Upload verifier output to S3 if configured
S3_URL=""
if [ -n "$S3_BUCKET" ] && command -v aws >/dev/null 2>&1; then
  echo "[post] Uploading verifier output to s3://$S3_BUCKET/verification/"
  AWS_KEY="verification/$(basename "$VERIFIER_OUTPUT")"
  if aws s3 cp "$VERIFIER_OUTPUT" "s3://$S3_BUCKET/$AWS_KEY" --acl bucket-owner-full-control >/dev/null 2>&1; then
    S3_URL="s3://$S3_BUCKET/$AWS_KEY"
    log_validation "s3_upload" "PASS" "Uploaded verifier output to $S3_URL"
  else
    log_validation "s3_upload" "FAIL" "Failed to upload verifier output to s3://$S3_BUCKET"
  fi
fi

# Post a concise comment to the tracking GitHub issue if token is present
if [ -n "$GITHUB_TOKEN" ]; then
  echo "[post] Posting verification summary to GitHub issue #$ISSUE_NUMBER"
  SNIPPET=$(head -n 200 "$VERIFIER_OUTPUT" | sed 's/"/\\"/g' | sed -n '1,200p')
  if [ -n "$S3_URL" ]; then
    BODY="Post-deploy verification run attached: $S3_URL\\n\\nSnippet:\\n\\n$SNIPPET"
  else
    BODY="Post-deploy verification run (no S3 upload configured). Snippet:\\n\\n$SNIPPET"
  fi
  # Build JSON safely using jq if available, otherwise fallback
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg body "$BODY" '{body: $body}' > /tmp/pp_comment.json
  else
    printf '{"body":"%s"}' "$BODY" > /tmp/pp_comment.json
  fi
  curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
    "https://api.github.com/repos/$ISSUE_OWNER/$ISSUE_REPO/issues/$ISSUE_NUMBER/comments" \
    -d @/tmp/pp_comment.json || echo "Warning: failed to post GitHub comment"
fi

# Ephemeral: clean up secret SSH key from tempfile
if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH:-}" ]; then
  rm -f "$SSH_KEY_PATH"
  echo "[cleanup] Removed ephemeral SSH key: $SSH_KEY_PATH"
fi

# Exit with the original validation exit code (non-zero if any core checks failed)
if [ "$VALIDATION_EXIT" -ne 0 ]; then
  exit "$VALIDATION_EXIT"
fi
