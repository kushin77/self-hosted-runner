#!/usr/bin/env bash
set -euo pipefail

# Polling monitor for verify + DR workflow runs.
# - Idempotent: stores last seen run IDs in /tmp
# - Ephemeral: writes only to /tmp
# - Safe: uses gh CLI and posts comments to issues for reporting

REPO="kushin77/self-hosted-runner"
ISSUE_MASTER=1277
ISSUE_ACTIVATION=1239
# default poll interval reduced for faster detection; can be overridden by env var
POLL_INTERVAL=${POLL_INTERVAL:-30}
STATE_FILE="/tmp/selfhosted_poller_state.json"
ARTIFACT_DIR_BASE="/tmp/artifacts"

mkdir -p "$ARTIFACT_DIR_BASE"

jq_or_create() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"last_verify":0,"last_dr":0,"processed_ingest":false}' > "$STATE_FILE"
  fi
}

get_state() { jq -r ".${1}" "$STATE_FILE"; }
set_state() { jq ". + {\"$1\":$2}" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"; }

download_and_report() {
  local run_id=$1
  local name=$2
  local dir="$ARTIFACT_DIR_BASE/$name-$run_id"
  mkdir -p "$dir"
  echo "Downloading artifacts for $name run $run_id to $dir"
  gh run download "$run_id" --repo "$REPO" --dir "$dir" || true
  # Post a brief comment to master issue with artifact location
  body="Automated: artifacts for workflow run $run_id ($name) saved to $dir on operator runner."
  gh api repos/${REPO}/issues/$ISSUE_MASTER/comments -f body="$body" >/dev/null 2>&1 || true
}

trigger_workflows() {
  echo "Triggering workflows: verify + dr"
  gh workflow run verify-secrets-and-diagnose.yml --repo "$REPO" --ref main || true
  gh workflow run dr-smoke-test.yml --repo "$REPO" --ref main || true
}

detect_ingested() {
  # returns 0 if comment found
  gh api repos/${REPO}/issues/$ISSUE_ACTIVATION/comments --jq '.[].body' | grep -F "ingested: true" >/dev/null 2>&1
}

main() {
  jq_or_create
  echo "Starting monitor (poll interval: ${POLL_INTERVAL}s). State file: $STATE_FILE"
  while true; do
    # Check for operator trigger
    if detect_ingested; then
      processed=$(get_state processed_ingest)
      if [[ "$processed" != "true" ]]; then
        echo "Detected 'ingested: true' comment; triggering workflows"
        trigger_workflows
        set_state processed_ingest true
      fi
    fi

    # Check latest verify run
    latest_verify=$(gh run list --workflow=verify-secrets-and-diagnose.yml --repo "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo 0)
    last_verify=$(get_state last_verify)
    if [[ "$latest_verify" != "null" && "$latest_verify" -ne 0 && "$latest_verify" -ne "$last_verify" ]]; then
      echo "New verify run detected: $latest_verify (previous: $last_verify)"
      download_and_report "$latest_verify" verify
      set_state last_verify "$latest_verify"
    fi

    # Check latest dr run
    latest_dr=$(gh run list --workflow=dr-smoke-test.yml --repo "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo 0)
    last_dr=$(get_state last_dr)
    if [[ "$latest_dr" != "null" && "$latest_dr" -ne 0 && "$latest_dr" -ne "$last_dr" ]]; then
      echo "New DR run detected: $latest_dr (previous: $last_dr)"
      download_and_report "$latest_dr" dr
      set_state last_dr "$latest_dr"
    fi

    sleep "$POLL_INTERVAL"
  done
}

main "$@"
