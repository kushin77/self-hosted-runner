#!/usr/bin/env bash
set -euo pipefail

# Wrapper for scheduled monitoring -> GitHub issue triage.
# Supports GSM-backed token retrieval and fail-safe skip behavior.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

AUDIT_LOG="${REPO_ROOT}/logs/monitoring-alert-issue-triage.jsonl"
WARNING_LOG="${REPO_ROOT}/logs/monitoring-alert-issue-triage.warning"
LOCK_FILE="${REPO_ROOT}/logs/monitoring-alert-issue-triage.lock"
STATUS_FILE="${REPO_ROOT}/logs/monitoring-alert-issue-triage.status"
mkdir -p "$(dirname "$AUDIT_LOG")"

PROM_URL="${PROM_URL:-http://localhost:9090}"
AM_URL="${AM_URL:-http://localhost:9093}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-kushin77/self-hosted-runner}"
GITHUB_TOKEN_GSM_SECRET="${GITHUB_TOKEN_GSM_SECRET:-github-token}"
TRIAGE_STRICT_MODE="${TRIAGE_STRICT_MODE:-false}"

log_event() {
  local event="$1"
  local details="${2:-}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"details\":\"${details//\"/\\\"}\"}" >> "$AUDIT_LOG"
}

write_status() {
  local state="$1"
  local message="${2:-}"
  cat > "$STATUS_FILE" <<EOF
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
state=${state}
message=${message}
EOF
}

skip_and_exit() {
  local reason="$1"
  log_event "triage_skip" "$reason"
  write_status "skip" "$reason"
  emit_skip_warning_if_repeated
  exit 0
}

rotate_audit_log() {
  local max_lines="${TRIAGE_AUDIT_MAX_LINES:-5000}"
  local line_count

  if ! [[ "$max_lines" =~ ^[0-9]+$ ]] || [ "$max_lines" -lt 100 ]; then
    max_lines=5000
  fi

  [ -f "$AUDIT_LOG" ] || return 0
  line_count="$(wc -l < "$AUDIT_LOG" 2>/dev/null || echo 0)"
  if [ "$line_count" -gt "$max_lines" ]; then
    tail -n "$max_lines" "$AUDIT_LOG" > "${AUDIT_LOG}.tmp" && mv "${AUDIT_LOG}.tmp" "$AUDIT_LOG"
  fi
}

emit_skip_warning_if_repeated() {
  local threshold="${TRIAGE_SKIP_ALERT_THRESHOLD:-3}"
  local recent

  if ! [[ "$threshold" =~ ^[0-9]+$ ]] || [ "$threshold" -lt 1 ]; then
    threshold=3
  fi

  recent="$(tail -n "$threshold" "$AUDIT_LOG" 2>/dev/null || true)"
  if [ -n "$recent" ] && [ "$(printf "%s\n" "$recent" | grep -c '"event":"triage_skip"' || true)" -ge "$threshold" ]; then
    cat > "$WARNING_LOG" <<EOF
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
status=warning
message=Repeated triage skips detected
threshold=${threshold}
action=Verify GITHUB_TOKEN_GSM_SECRET and GCP_PROJECT_ID; validate Prometheus/Alertmanager reachability
EOF
  fi
}

clear_skip_warning() {
  rm -f "$WARNING_LOG" 2>/dev/null || true
}

endpoint_ready() {
  local url="$1"
  [ -z "$url" ] && return 1
  curl -fsS --max-time 3 "$url" >/dev/null 2>&1
}

rotate_audit_log

if ! command -v flock >/dev/null 2>&1; then
  skip_and_exit "missing flock command"
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  skip_and_exit "another triage run is already in progress"
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud is required when GITHUB_TOKEN is not set; skipping triage run" >&2
    skip_and_exit "missing gcloud and no GITHUB_TOKEN"
  fi

  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
  if [ -z "$GCP_PROJECT_ID" ]; then
    echo "GCP_PROJECT_ID is required for GSM token retrieval; skipping triage run" >&2
    skip_and_exit "missing GCP_PROJECT_ID"
  fi

  token_result=""
  token_status=0
  token_error=""
  set +e
  token_result="$(gcloud secrets versions access latest --secret="$GITHUB_TOKEN_GSM_SECRET" --project="$GCP_PROJECT_ID" 2>&1)"
  token_status=$?
  set -e
  if [ $token_status -eq 0 ] && [ -n "$token_result" ]; then
    token="$token_result"
  else
    token_error="$(printf "%s" "$token_result" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)"
    echo "Failed to load GitHub token from GSM secret: $GITHUB_TOKEN_GSM_SECRET; skipping triage run" >&2
    if [ -n "$token_error" ]; then
      skip_and_exit "missing or inaccessible GSM secret ${GITHUB_TOKEN_GSM_SECRET}; gcloud_error=${token_error}"
    fi
    skip_and_exit "missing or inaccessible GSM secret ${GITHUB_TOKEN_GSM_SECRET}"
  fi
  export GITHUB_TOKEN="$token"
fi

clear_skip_warning

# If neither endpoint is reachable, skip this cycle (timer will retry).
if ! endpoint_ready "${PROM_URL}/-/ready" && ! endpoint_ready "${AM_URL}/-/ready"; then
  echo "Prometheus/Alertmanager not reachable; skipping triage run" >&2
  skip_and_exit "monitoring endpoints unreachable prom=${PROM_URL} am=${AM_URL}"
fi

export PROM_URL
export AM_URL
export GITHUB_REPOSITORY

if ./scripts/monitoring/triage_alerts_to_github_issues.sh; then
  log_event "triage_run_success" "triage script completed successfully"
  write_status "ok" "triage script completed successfully"
  exit 0
fi

if [ "${TRIAGE_STRICT_MODE,,}" = "true" ]; then
  log_event "triage_failed" "triage script failed in strict mode"
  write_status "failed" "triage script failed in strict mode"
  exit 1
fi

skip_and_exit "triage script execution failed; running fail-safe no-op"
