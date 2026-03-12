#!/usr/bin/env bash
set -euo pipefail

# Auto-rotate trigger: watches PRs and runs Cloud Build when ready.
# Usage: PROJECT_ID=my-gcp-project ./scripts/ops/auto_rotate_trigger.sh

PRS=(2850 2852)
REPO="kushin77/self-hosted-runner"
POLL_INTERVAL=${POLL_INTERVAL:-30}
TIMEOUT=${TIMEOUT:-1800}
LOGFILE="logs/rotate_trigger.log"

mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

start_ts=$(date +%s)
echo "[auto_rotate_trigger] Starting monitor for PRs: ${PRS[*]} (timeout=${TIMEOUT}s)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[auto_rotate_trigger] required command not found: $1" >&2
    exit 2
  fi
}

require_cmd gh

check_pr_merged() {
  local pr=$1
  local state
  state=$(gh pr view "$pr" --repo "$REPO" --json state -q '.state' 2>/dev/null || true)
  if [[ "$state" == "CLOSED" ]]; then
    # check merged flag
    merged=$(gh pr view "$pr" --repo "$REPO" --json merged -q '.merged' 2>/dev/null || echo false)
    if [[ "$merged" == "true" ]]; then
      echo "merged"
      return 0
    fi
  fi
  echo "open"
  return 1
}

all_merged=true
for pr in "${PRS[@]}"; do
  if ! check_pr_merged "$pr" >/dev/null 2>&1; then
    all_merged=false
    break
  fi
done

while :; do
  now_ts=$(date +%s)
  elapsed=$((now_ts - start_ts))
  if (( elapsed > TIMEOUT )); then
    echo "[auto_rotate_trigger] Timeout reached (${TIMEOUT}s). Exiting.";
    exit 0
  fi

  all_merged=true
  for pr in "${PRS[@]}"; do
    if ! check_pr_merged "$pr" >/dev/null 2>&1; then
      echo "[auto_rotate_trigger] PR #$pr not merged yet"
      all_merged=false
    else
      echo "[auto_rotate_trigger] PR #$pr merged"
    fi
  done

  if $all_merged; then
    echo "[auto_rotate_trigger] All PRs merged. Preparing to trigger Cloud Build."
    if [[ -z "${PROJECT_ID-}" ]]; then
      echo "[auto_rotate_trigger] PROJECT_ID not set; cannot trigger Cloud Build. Exiting.";
      exit 0
    fi
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "[auto_rotate_trigger] gcloud not available; cannot trigger Cloud Build. Exiting.";
      exit 0
    fi

    echo "[auto_rotate_trigger] Triggering Cloud Build with project ${PROJECT_ID}"
    gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
      --substitutions=PROJECT_ID=${PROJECT_ID},_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main || {
      echo "[auto_rotate_trigger] Cloud Build failed to start"; exit 1;
    }
    echo "[auto_rotate_trigger] Cloud Build triggered successfully.";
    exit 0
  fi

  sleep "$POLL_INTERVAL"
done
