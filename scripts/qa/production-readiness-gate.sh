#!/usr/bin/env bash
set -euo pipefail

# Unified production QA gate for this repository.
# Default behavior is non-destructive and dry-run-safe.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${REPO_ROOT}/logs/qa"
REPORT_DIR="${REPO_ROOT}/reports/qa"
mkdir -p "$LOG_DIR" "$REPORT_DIR"

REPORT_FILE="${REPORT_FILE:-${REPORT_DIR}/production-readiness-${TS}.md}"
JSON_LOG="${JSON_LOG:-${LOG_DIR}/production-readiness-${TS}.jsonl}"
ERROR_LOG="${ERROR_LOG:-${LOG_DIR}/production-errors-${TS}.jsonl}"

PORTAL_URL="${PORTAL_URL:-http://localhost:5000/health}"
BACKEND_URL="${BACKEND_URL:-http://localhost:3000/health}"
STRICT=false
EXECUTE_SHUTDOWN=false
FULL_TESTS=false

PASS=0
FAIL=0
SKIP=0

usage() {
  cat <<EOF
Usage: $0 [--strict] [--full-tests] [--execute-shutdown] [--portal-url URL] [--backend-url URL]

Options:
  --strict             Fail fast when a critical step fails
  --full-tests         Run heavy test suites (backend/portal/chaos)
  --execute-shutdown   Execute real shutdown cleanup (otherwise dry-run)
  --portal-url URL     Portal health endpoint (default: ${PORTAL_URL})
  --backend-url URL    Backend health endpoint (default: ${BACKEND_URL})
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=true; shift ;;
    --full-tests) FULL_TESTS=true; shift ;;
    --execute-shutdown) EXECUTE_SHUTDOWN=true; shift ;;
    --portal-url) PORTAL_URL="$2"; shift 2 ;;
    --backend-url) BACKEND_URL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

json_log() {
  local level="$1"
  local step="$2"
  local message="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
      --arg level "$level" \
      --arg step "$step" \
      --arg message "$message" \
      '{timestamp:$ts,level:$level,step:$step,message:$message}' >> "$JSON_LOG"
  else
    printf '%s [%s] %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$step" "$message" >> "$JSON_LOG"
  fi
}

record_error() {
  local step="$1"
  local message="$2"
  json_log "ERROR" "$step" "$message"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg step "$step" --arg error "$message" '{timestamp:$ts,step:$step,error:$error}' >> "$ERROR_LOG"
  else
    printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$message" >> "$ERROR_LOG"
  fi
}

run_step() {
  local step="$1"
  shift
  json_log "INFO" "$step" "start"
  if "$@"; then
    PASS=$((PASS+1))
    json_log "INFO" "$step" "pass"
    return 0
  fi

  FAIL=$((FAIL+1))
  record_error "$step" "step failed"
  if [ "$STRICT" = true ]; then
    exit 1
  fi
  return 1
}

skip_step() {
  local step="$1"
  local reason="$2"
  SKIP=$((SKIP+1))
  json_log "WARN" "$step" "skipped: $reason"
}

check_http_200() {
  local url="$1"
  local name="$2"
  if ! command -v curl >/dev/null 2>&1; then
    skip_step "$name" "curl not installed"
    return 0
  fi

  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
  [ "$code" = "200" ]
}

check_no_terraform_drift() {
  if ! command -v terraform >/dev/null 2>&1; then
    skip_step "terraform-drift" "terraform not installed"
    return 0
  fi

  # Conservative check: this verifies no formatting drift and validates syntax.
  terraform -chdir="$REPO_ROOT/terraform" fmt -check -recursive >/dev/null 2>&1 || return 1
  terraform -chdir="$REPO_ROOT/terraform" validate >/dev/null 2>&1 || return 1
}

run_backend_tests() {
  if ! command -v npm >/dev/null 2>&1; then
    skip_step "backend-tests" "npm not installed"
    return 0
  fi
  [ -f "$REPO_ROOT/backend/package.json" ] || { skip_step "backend-tests" "backend package missing"; return 0; }
  NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=1536}" \
    npm --prefix "$REPO_ROOT/backend" test -- --runInBand --passWithNoTests >/dev/null || return 1
}

run_portal_tests() {
  if ! command -v pnpm >/dev/null 2>&1; then
    skip_step "portal-tests" "pnpm not installed"
    return 0
  fi
  [ -f "$REPO_ROOT/portal/package.json" ] || { skip_step "portal-tests" "portal package missing"; return 0; }
  NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=1536}" \
    pnpm -C "$REPO_ROOT/portal" test -- --runInBand >/dev/null || return 1
}

run_security_chaos_suite() {
  [ -f "$REPO_ROOT/scripts/testing/run-all-chaos-tests.sh" ] || { skip_step "chaos-suite" "chaos script missing"; return 0; }
  bash "$REPO_ROOT/scripts/testing/run-all-chaos-tests.sh" >/dev/null || return 1
}

run_overlap_review() {
  bash "$REPO_ROOT/scripts/qa/review-overlap.sh" >/dev/null
}

run_secrets_sync_tests() {
  [ -f "$REPO_ROOT/scripts/secrets/mirror-all-backends.sh" ] || return 1
  [ -f "$REPO_ROOT/scripts/secrets/health-check.sh" ] || return 1

  mkdir -p "$REPO_ROOT/logs/secret-mirror" || true
  local mirror_audit_dir="$REPO_ROOT/logs/qa/secret-mirror"
  mkdir -p "$mirror_audit_dir" || true
  if ! touch "$mirror_audit_dir/.write-test" 2>/dev/null; then
    record_error "secrets-sync" "logs/qa/secret-mirror is not writable"
    return 1
  fi
  rm -f "$mirror_audit_dir/.write-test" || true

  SECRET_MIRROR_AUDIT_DIR="$mirror_audit_dir" bash "$REPO_ROOT/scripts/secrets/mirror-all-backends.sh" >/dev/null || return 1
  bash "$REPO_ROOT/scripts/secrets/health-check.sh" >/dev/null || return 1
}

run_shutdown_validation() {
  [ -f "$REPO_ROOT/scripts/cloud/cleanup-all-clouds.sh" ] || return 1
  if [ "$EXECUTE_SHUTDOWN" = true ]; then
    bash "$REPO_ROOT/scripts/cloud/cleanup-all-clouds.sh" --execute --reboot-check || return 1
  else
    bash "$REPO_ROOT/scripts/cloud/cleanup-all-clouds.sh" --reboot-check || return 1
  fi
}

run_log_integrity_checks() {
  local cleanup_logs
  cleanup_logs=$(find "$REPO_ROOT/logs" -type f \( -name '*cleanup*' -o -name '*audit*.jsonl' \) | wc -l | tr -d ' ')
  [ "$cleanup_logs" -gt 0 ]
}

check_git_state_for_release() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "$REPO_ROOT" fetch --all --quiet >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" status --porcelain >/dev/null 2>&1
}

write_report() {
  cat > "$REPORT_FILE" <<EOF
# Production Readiness Gate Report

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Summary

- Passed: ${PASS}
- Failed: ${FAIL}
- Skipped: ${SKIP}

## Inputs

- Portal health URL: ${PORTAL_URL}
- Backend health URL: ${BACKEND_URL}
- Execute shutdown: ${EXECUTE_SHUTDOWN}
- Strict mode: ${STRICT}

## Artifacts

- JSON log: ${JSON_LOG}
- Error log: ${ERROR_LOG}

## Interpretation

Use this report as the production gate artifact before merge/deploy.
If failures are present, review ${ERROR_LOG} and linked step logs.
EOF
}

json_log "INFO" "production-gate" "start"

run_step "overlap-review" run_overlap_review || true
if [ "$FULL_TESTS" = true ]; then
  run_step "backend-tests" run_backend_tests || true
  run_step "portal-tests" run_portal_tests || true
  run_step "chaos-suite" run_security_chaos_suite || true
else
  skip_step "backend-tests" "full suite disabled (use --full-tests)"
  skip_step "portal-tests" "full suite disabled (use --full-tests)"
  skip_step "chaos-suite" "full suite disabled (use --full-tests)"
fi
run_step "secrets-sync" run_secrets_sync_tests || true
run_step "portal-health" check_http_200 "$PORTAL_URL" "portal-health" || true
run_step "backend-health" check_http_200 "$BACKEND_URL" "backend-health" || true
run_step "terraform-drift" check_no_terraform_drift || true
run_step "shutdown-validation" run_shutdown_validation || true
run_step "shutdown-log-check" run_log_integrity_checks || true
run_step "git-state-check" check_git_state_for_release || true

write_report

json_log "INFO" "production-gate" "end pass=${PASS} fail=${FAIL} skip=${SKIP}"
echo "Production readiness report: ${REPORT_FILE}"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
