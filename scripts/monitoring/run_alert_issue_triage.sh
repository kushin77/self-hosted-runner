#!/usr/bin/env bash
set -euo pipefail

# Wrapper for scheduled monitoring -> GitHub issue triage.
# Supports GSM-backed token retrieval and fail-fast behavior.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

AUDIT_LOG="${REPO_ROOT}/logs/monitoring-alert-issue-triage.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")"

PROM_URL="${PROM_URL:-http://localhost:9090}"
AM_URL="${AM_URL:-http://localhost:9093}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-kushin77/self-hosted-runner}"
GITHUB_TOKEN_GSM_SECRET="${GITHUB_TOKEN_GSM_SECRET:-github-token}"

log_event() {
  local event="$1"
  local details="${2:-}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"details\":\"${details//\"/\\\"}\"}" >> "$AUDIT_LOG"
}

endpoint_ready() {
  local url="$1"
  [ -z "$url" ] && return 1
  curl -fsS --max-time 3 "$url" >/dev/null 2>&1
}

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud is required when GITHUB_TOKEN is not set; skipping triage run" >&2
    log_event "triage_skip" "missing gcloud and no GITHUB_TOKEN"
    exit 0
  fi

  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
  if [ -z "$GCP_PROJECT_ID" ]; then
    echo "GCP_PROJECT_ID is required for GSM token retrieval; skipping triage run" >&2
    log_event "triage_skip" "missing GCP_PROJECT_ID"
    exit 0
  fi

  token="$(gcloud secrets versions access latest --secret="$GITHUB_TOKEN_GSM_SECRET" --project="$GCP_PROJECT_ID" 2>/dev/null || true)"
  if [ -z "$token" ]; then
    echo "Failed to load GitHub token from GSM secret: $GITHUB_TOKEN_GSM_SECRET; skipping triage run" >&2
    log_event "triage_skip" "missing or inaccessible GSM secret ${GITHUB_TOKEN_GSM_SECRET}"
    exit 0
  fi
  export GITHUB_TOKEN="$token"
fi

# If neither endpoint is reachable, skip this cycle (timer will retry).
if ! endpoint_ready "${PROM_URL}/-/ready" && ! endpoint_ready "${AM_URL}/-/ready"; then
  echo "Prometheus/Alertmanager not reachable; skipping triage run" >&2
  log_event "triage_skip" "monitoring endpoints unreachable prom=${PROM_URL} am=${AM_URL}"
  exit 0
fi

export PROM_URL
export AM_URL
export GITHUB_REPOSITORY

exec ./scripts/monitoring/triage_alerts_to_github_issues.sh
