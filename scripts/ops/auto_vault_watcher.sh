#!/usr/bin/env bash
# Poll GSM for real VAULT_ADDR and VAULT_TOKEN; trigger Cloud Build rotation when present.
# Usage: PROJECT_ID=nexusshield-prod ./auto_vault_watcher.sh &

set -euo pipefail
PROJECT_ID=${PROJECT_ID:-nexusshield-prod}
GSM_PROJECT=${GSM_PROJECT:-$PROJECT_ID}
POLL_INTERVAL=${POLL_INTERVAL:-60}  # seconds
MAX_ATTEMPTS=${MAX_ATTEMPTS:-0}     # 0 = infinite
LOGFILE=${LOGFILE:-/tmp/auto_vault_watcher.log}

echo "[auto_vault_watcher] starting, project=$PROJECT_ID, poll_interval=$POLL_INTERVALs" | tee -a "$LOGFILE"

attempt=0
while :; do
  attempt=$((attempt+1))
  VAULT_ADDR=$(gcloud secrets versions access latest --secret=VAULT_ADDR --project="$GSM_PROJECT" 2>/dev/null || true)
  VAULT_TOKEN=$(gcloud secrets versions access latest --secret=VAULT_TOKEN --project="$GSM_PROJECT" 2>/dev/null || true)

  valid_addr=true
  valid_token=true
  if [[ -z "$VAULT_ADDR" || "$VAULT_ADDR" =~ PLACEHOLDER|example|your-|REDACTED ]]; then
    valid_addr=false
  fi
  if [[ -z "$VAULT_TOKEN" || "$VAULT_TOKEN" =~ PLACEHOLDER|REDACTED|your_ ]]; then
    valid_token=false
  fi

  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] attempt=$attempt: VAULT_ADDR_present=$([[ -n "$VAULT_ADDR" ]] && echo yes || echo no) VAULT_TOKEN_present=$([[ -n "$VAULT_TOKEN" ]] && echo yes || echo no)" | tee -a "$LOGFILE"

  if $valid_addr && $valid_token; then
    echo "[auto_vault_watcher] Valid Vault credentials detected — triggering Cloud Build rotation now" | tee -a "$LOGFILE"
    BUILD_ID=$(gcloud builds submit --project="$PROJECT_ID" --config=cloudbuild/rotate-credentials-cloudbuild.yaml --verbosity=info --format='value(id)' 2>>"$LOGFILE" | tail -n1 || true)
    if [[ -n "$BUILD_ID" ]]; then
      echo "[auto_vault_watcher] Build triggered: $BUILD_ID" | tee -a "$LOGFILE"
      gh issue comment 2856 --repo=kushin77/self-hosted-runner --body "Auto-watcher: Detected real Vault credentials in GSM; triggered rotation build: $BUILD_ID. I will monitor and post results." || echo "[auto_vault_watcher] gh comment failed" | tee -a "$LOGFILE"
    else
      echo "[auto_vault_watcher] Build trigger failed; check logs" | tee -a "$LOGFILE"
    fi
    # exit after triggering to avoid duplicate triggers; Cloud Scheduler will continue daily as fallback
    exit 0
  fi

  if [[ $MAX_ATTEMPTS -ne 0 && $attempt -ge $MAX_ATTEMPTS ]]; then
    echo "[auto_vault_watcher] max attempts reached ($MAX_ATTEMPTS); exiting" | tee -a "$LOGFILE"
    exit 2
  fi

  sleep "$POLL_INTERVAL"
done
