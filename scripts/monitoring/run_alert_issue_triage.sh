#!/usr/bin/env bash
set -euo pipefail

# Wrapper for scheduled monitoring -> GitHub issue triage.
# Supports GSM-backed token retrieval and fail-fast behavior.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

PROM_URL="${PROM_URL:-http://localhost:9090}"
AM_URL="${AM_URL:-http://localhost:9093}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-kushin77/self-hosted-runner}"
GITHUB_TOKEN_GSM_SECRET="${GITHUB_TOKEN_GSM_SECRET:-github-token}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud is required when GITHUB_TOKEN is not set" >&2
    exit 2
  fi

  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
  if [ -z "$GCP_PROJECT_ID" ]; then
    echo "GCP_PROJECT_ID is required for GSM token retrieval" >&2
    exit 2
  fi

  token="$(gcloud secrets versions access latest --secret="$GITHUB_TOKEN_GSM_SECRET" --project="$GCP_PROJECT_ID" 2>/dev/null || true)"
  if [ -z "$token" ]; then
    echo "Failed to load GitHub token from GSM secret: $GITHUB_TOKEN_GSM_SECRET" >&2
    exit 2
  fi
  export GITHUB_TOKEN="$token"
fi

export PROM_URL
export AM_URL
export GITHUB_REPOSITORY

exec ./scripts/monitoring/triage_alerts_to_github_issues.sh
