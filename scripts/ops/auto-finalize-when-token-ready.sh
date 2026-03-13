#!/bin/bash
set -euo pipefail

PROJECT_ID="nexusshield-prod"
SECRET_NAME="cloudflare-api-token"
REPO_ROOT="/home/akushnir/self-hosted-runner"
LOG_FILE="$REPO_ROOT/logs/cutover/auto-finalize-token-watch.log"
INTERVAL_SECONDS="${TOKEN_WATCH_INTERVAL_SECONDS:-30}"

mkdir -p "$REPO_ROOT/logs/cutover"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG_FILE"
}

is_valid_token() {
  local token="$1"
  [[ -n "$token" && "$token" != "PLACEHOLDER_TOKEN_AWAITING_INPUT" ]]
}

log "Auto-finalize watcher started (interval=${INTERVAL_SECONDS}s, project=${PROJECT_ID}, secret=${SECRET_NAME})"

while true; do
  token="$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT_ID" 2>/dev/null || true)"

  if is_valid_token "$token"; then
    export CF_API_TOKEN="$token"
    log "Valid Cloudflare token detected in GSM. Triggering finalize-deployment.sh"

    if bash "$REPO_ROOT/scripts/ops/finalize-deployment.sh" >> "$LOG_FILE" 2>&1; then
      log "Finalization completed successfully. Exiting watcher."
      exit 0
    else
      log "Finalization failed. Retrying on next interval."
    fi
  else
    log "Token not ready (missing/placeholder). Waiting..."
  fi

  sleep "$INTERVAL_SECONDS"
done
