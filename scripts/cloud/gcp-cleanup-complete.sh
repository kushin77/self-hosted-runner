#!/usr/bin/env bash
set -euo pipefail

# GCP cleanup: stop/scale down active resources in an idempotent way.
# Respects DRY_RUN env var: if set to "true" no state-changing action is executed.

DRY_RUN=${DRY_RUN:-true}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
LOGFILE="${LOGFILE:-${REPO_ROOT}/logs/cleanup/cleanup-audit.jsonl}"
ERROR_FILE="${ERROR_FILE:-${REPO_ROOT}/logs/cleanup/cleanup-errors.jsonl}"

mkdir -p "$(dirname "$LOGFILE")"

log(){
  command -v jq >/dev/null 2>&1 || true
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$1" '{timestamp:$ts,cloud:"gcp",message:$m}' >> "$LOGFILE"
  else
    echo "$1" >> "$LOGFILE"
  fi
}

log_error(){
  local m="$1"
  log "ERROR: $m"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$m" '{timestamp:$ts,cloud:"gcp",error:$m}' >> "$ERROR_FILE"
  else
    echo "ERROR: $m" >> "$ERROR_FILE"
  fi
}

run_mutation(){
  local description="$1"
  shift
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: ${description}"
    log "dry_run ${description}"
    return 0
  fi

  if "$@"; then
    log "success ${description}"
  else
    log_error "failed ${description}"
  fi
}

echo "GCP cleanup invoked (dry-run=$DRY_RUN)"
log "gcp_cleanup_invoked dry_run=$DRY_RUN project=${PROJECT_ID:-unset}"

if ! command -v gcloud >/dev/null 2>&1; then
  log "gcloud not installed; skipping GCP cleanup"
  exit 0
fi

if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

if [ -z "$PROJECT_ID" ]; then
  log_error "GCP project not set (GCP_PROJECT_ID/GOOGLE_CLOUD_PROJECT)"
  exit 1
fi

list_resources(){
  echo "Listing active GCP resources for project ${PROJECT_ID}"
  gcloud compute instances list --project "$PROJECT_ID" --filter='status=RUNNING' --format='table(name,zone,status)' 2>/dev/null || true
  gcloud run services list --project "$PROJECT_ID" --format='table(metadata.name,status.url,spec.template.spec.containerConcurrency)' 2>/dev/null || true
  gcloud functions list --project "$PROJECT_ID" --format='table(name,status,environment)' 2>/dev/null || true
  gcloud scheduler jobs list --project "$PROJECT_ID" --format='table(name,state,schedule)' 2>/dev/null || true
}

stop_compute_instances(){
  local rows
  rows=$(gcloud compute instances list --project "$PROJECT_ID" --filter='status=RUNNING' --format='value(name,zone)' 2>/dev/null || true)
  [ -z "$rows" ] && return 0
  while IFS=' ' read -r name zone; do
    [ -z "$name" ] && continue
    run_mutation "gcp stop instance ${name} (${zone})" gcloud compute instances stop "$name" --zone "$zone" --project "$PROJECT_ID" --quiet
  done <<< "$rows"
}

scale_cloud_run_to_zero(){
  local services
  services=$(gcloud run services list --project "$PROJECT_ID" --format='value(metadata.name)' 2>/dev/null || true)
  [ -z "$services" ] && return 0
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    local region
    region=$(gcloud run services describe "$svc" --project "$PROJECT_ID" --format='value(metadata.labels.cloud.googleapis.com/location)' 2>/dev/null || true)
    [ -z "$region" ] && region="us-central1"
    run_mutation "gcp scale cloud run ${svc} max=0" gcloud run services update "$svc" --region "$region" --project "$PROJECT_ID" --max-instances=0 --quiet
  done <<< "$services"
}

pause_scheduler_jobs(){
  local jobs
  jobs=$(gcloud scheduler jobs list --project "$PROJECT_ID" --format='value(name)' 2>/dev/null || true)
  [ -z "$jobs" ] && return 0
  while IFS= read -r job; do
    [ -z "$job" ] && continue
    run_mutation "gcp pause scheduler job ${job}" gcloud scheduler jobs pause "$job" --project "$PROJECT_ID" --quiet
  done <<< "$jobs"
}

if [ "$DRY_RUN" = "true" ]; then
  list_resources
  log "gcp_dry_run_listed_resources"
  exit 0
fi

echo "Performing GCP cleanup..."
log "gcp_cleanup_started"

stop_compute_instances
scale_cloud_run_to_zero
pause_scheduler_jobs

log "gcp_cleanup_completed"
echo "GCP cleanup completed"
