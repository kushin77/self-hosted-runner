#!/usr/bin/env bash
set -euo pipefail

# Wait-and-trigger helper for Vault AppRole rotation
# - Polls GSM for real VAULT_ADDR and VAULT_TOKEN
# - When valid values are found, triggers Cloud Build rotation (async)
# - Idempotent: exits 0 if rotation already triggered or completed

PROJECT=${1:-nexusshield-prod}
INTERVAL=${2:-30}         # seconds between checks
MAX_ATTEMPTS=${3:-120}    # default 1 hour (120 * 30s)
DRY_RUN=${DRY_RUN:-false}

log(){ printf "[%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
err(){ log "ERROR: $*"; exit 1; }

is_placeholder(){
  local v="$1"
  [[ -z "$v" ]] && return 0
  if [[ "$v" =~ example|PLACEHOLDER|placeholder|your-|REDACTED ]]; then
    return 0
  fi
  return 1
}

check_secret(){
  local name="$1"
  if gcloud secrets versions access latest --secret="$name" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud secrets versions access latest --secret="$name" --project="$PROJECT" 2>/dev/null || true
    return 0
  else
    return 1
  fi
}

trigger_build(){
  log "Triggering Cloud Build rotation (async)"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: would run gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml"
    return 0
  fi
  local build_id
  build_id=$(gcloud builds submit --project="$PROJECT" \
    --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
    --substitutions=PROJECT_ID="$PROJECT",_REPO_OWNER=kushin77,_REPO_NAME=self-hosted-runner,_BRANCH=main \
    --async --format='value(id)') || build_id="unknown"
  log "Build triggered: ${build_id:-unknown}"
  # notify issue thread
  gh issue comment 2856 --repo kushin77/self-hosted-runner --body "Vault rotation triggered by automation. Build ID: ${build_id:-unknown}" || true
}

main(){
  log "Starting wait-and-trigger: project=$PROJECT interval=${INTERVAL}s max_attempts=$MAX_ATTEMPTS"

  for ((i=1;i<=MAX_ATTEMPTS;i++)); do
    log "Attempt $i/$MAX_ATTEMPTS: checking GSM for VAULT_ADDR and VAULT_TOKEN"
    if ! gcloud secrets versions access latest --secret=VAULT_ADDR --project="$PROJECT" >/dev/null 2>&1; then
      log "VAULT_ADDR missing"
      sleep "$INTERVAL"
      continue
    fi
    if ! gcloud secrets versions access latest --secret=VAULT_TOKEN --project="$PROJECT" >/dev/null 2>&1; then
      log "VAULT_TOKEN missing"
      sleep "$INTERVAL"
      continue
    fi

    VAULT_ADDR_VAL=$(gcloud secrets versions access latest --secret=VAULT_ADDR --project="$PROJECT" 2>/dev/null || echo "")
    VAULT_TOKEN_VAL=$(gcloud secrets versions access latest --secret=VAULT_TOKEN --project="$PROJECT" 2>/dev/null || echo "")

    if is_placeholder "$VAULT_ADDR_VAL"; then
      log "VAULT_ADDR looks like a placeholder; value='$VAULT_ADDR_VAL'"
      sleep "$INTERVAL"
      continue
    fi
    if is_placeholder "$VAULT_TOKEN_VAL"; then
      log "VAULT_TOKEN looks like a placeholder; value contains placeholder pattern"
      sleep "$INTERVAL"
      continue
    fi

    log "Real Vault credentials detected. Triggering rotation."
    trigger_build
    log "Done. Exiting."
    return 0
  done

  log "Max attempts reached without finding valid Vault credentials. Exiting with code 2."
  return 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
