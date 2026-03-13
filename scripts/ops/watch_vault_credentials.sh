#!/usr/bin/env bash
# Poll GSM for VAULT_ADDR and VAULT_TOKEN and trigger Cloud Build when present
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
GSM_PROJECT="${GSM_PROJECT:-nexusshield-prod}"
CB_PROJECT="${PROJECT_ID:-nexusshield-prod}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-2880}" # default 24 hours at 30s intervals
ISSUE_NUMBER="${ISSUE_NUMBER:-2856}"
LOGFILE="logs/watch_vault.log"

mkdir -p "$(dirname "$LOGFILE")"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE" >&2; }

is_valid_value() {
  local v="$1"
  if [[ -z "$v" ]]; then
    return 1
  fi
  if [[ "$v" =~ PLACEHOLDER|REDACTED|your\.|your_|example ]]; then
    return 1
  fi
  return 0
}

fetch_secret() {
  local name="$1"
  gcloud secrets versions access latest --secret="$name" --project="$GSM_PROJECT" --format='get(payload.data)' 2>/dev/null | base64 --decode || true
}

attempt=0
log "Starting Vault credential watcher (project=$GSM_PROJECT), polling every ${POLL_INTERVAL}s"
while true; do
  attempt=$((attempt+1))
  log "Attempt $attempt/$MAX_ATTEMPTS: checking GSM for VAULT_ADDR and VAULT_TOKEN"

  VAULT_ADDR_VAL=$(fetch_secret VAULT_ADDR)
  VAULT_TOKEN_VAL=$(fetch_secret VAULT_TOKEN)

  if is_valid_value "$VAULT_ADDR_VAL" && is_valid_value "$VAULT_TOKEN_VAL"; then
    log "Valid Vault credentials detected. Triggering Cloud Build rotation."

    # trigger Cloud Build (no substitutions expected)
    set -o pipefail
    build_id=$(gcloud builds submit --project="$CB_PROJECT" --config=cloudbuild/rotate-credentials-cloudbuild.yaml --verbosity=info --format='value(id)' 2>&1 | tail -n1) || true
    set +o pipefail

    log "Triggered Cloud Build: ${build_id:-unknown}"

    # post comment to issue for audit (best-effort)
    if command -v gh >/dev/null 2>&1; then
      gh issue comment "$ISSUE_NUMBER" --repo kushin77/self-hosted-runner --body "Auto-trigger: Vault credentials detected in GSM. Started Cloud Build rotation (build id: ${build_id:-unknown}). I'll monitor and report results." || true
    fi

    log "Watcher exiting after triggering build"
    exit 0
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    log "Max attempts reached ($MAX_ATTEMPTS). Exiting watcher."
    exit 2
  fi

  sleep "$POLL_INTERVAL"
done
