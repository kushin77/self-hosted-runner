#!/usr/bin/env bash
# Monitor GSM for `vault-example-role-secret_id` versions and close Vault issues when found
set -euo pipefail

GSM_PROJECT="${GSM_PROJECT:-nexusshield-prod}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-2880}"
ISSUES=(2856 2857 2858)
LOGFILE="logs/monitor_vault.log"

mkdir -p "$(dirname "$LOGFILE")"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE" >&2; }

check_secret() {
  gcloud secrets versions list vault-example-role-secret_id --project="$GSM_PROJECT" --limit=1 --format='value(name)' 2>/dev/null || true
}

attempt=0
log "Starting Vault rotation monitor (project=$GSM_PROJECT), polling every ${POLL_INTERVAL}s"
while true; do
  attempt=$((attempt+1))
  log "Attempt $attempt/$MAX_ATTEMPTS: checking for vault-example-role-secret_id"
  ver=$(check_secret || true)
  if [[ -n "$ver" ]]; then
    log "Detected vault-example-role-secret_id version: $ver"
    # Comment and close issues
    if command -v gh >/dev/null 2>&1; then
      for i in "${ISSUES[@]}"; do
        gh issue comment "$i" --repo kushin77/self-hosted-runner --body "Automated: Vault AppRole secret_id created (version: $ver). Closing issue." || true
        gh issue close "$i" --repo kushin77/self-hosted-runner || true
      done
    fi
    log "Monitor exiting after closing issues"
    exit 0
  fi
  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    log "Max attempts reached ($MAX_ATTEMPTS). Exiting monitor."
    exit 2
  fi
  sleep "$POLL_INTERVAL"
done
