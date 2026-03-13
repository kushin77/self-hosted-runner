#!/usr/bin/env bash
set -euo pipefail

# Azure cleanup: stop active resources in an idempotent way.
# Respects DRY_RUN env var: if set to "true" no state-changing action is executed.

DRY_RUN=${DRY_RUN:-true}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGFILE="${LOGFILE:-${REPO_ROOT}/logs/cleanup/cleanup-audit.jsonl}"
ERROR_FILE="${ERROR_FILE:-${REPO_ROOT}/logs/cleanup/cleanup-errors.jsonl}"

mkdir -p "$(dirname "$LOGFILE")"

log(){
  command -v jq >/dev/null 2>&1 || true
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$1" '{timestamp:$ts,cloud:"azure",message:$m}' >> "$LOGFILE"
  else
    echo "$1" >> "$LOGFILE"
  fi
}

log_error(){
  local m="$1"
  log "ERROR: $m"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$m" '{timestamp:$ts,cloud:"azure",error:$m}' >> "$ERROR_FILE"
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

echo "Azure cleanup invoked (dry-run=$DRY_RUN)"
log "azure_cleanup_invoked dry_run=$DRY_RUN"

if ! command -v az >/dev/null 2>&1; then
  log "az CLI not installed; skipping Azure cleanup"
  exit 0
fi

list_resources(){
  echo "Listing active Azure resources"
  az vm list -d --query '[].{name:name,resourceGroup:resourceGroup,power:powerState}' -o table 2>/dev/null || true
  az webapp list --query '[].{name:name,resourceGroup:resourceGroup,state:state}' -o table 2>/dev/null || true
  az functionapp list --query '[].{name:name,resourceGroup:resourceGroup,state:state}' -o table 2>/dev/null || true
}

stop_vms(){
  local rows
  rows=$(az vm list -d --query '[?powerState==`VM running`].[resourceGroup,name]' -o tsv 2>/dev/null || true)
  [ -z "$rows" ] && return 0
  while IFS=$'\t' read -r rg name; do
    [ -z "$name" ] && continue
    run_mutation "az vm deallocate ${rg}/${name}" az vm deallocate --resource-group "$rg" --name "$name" --no-wait
  done <<< "$rows"
}

stop_app_services(){
  local rows
  rows=$(az webapp list --query '[?state==`Running`].[resourceGroup,name]' -o tsv 2>/dev/null || true)
  [ -z "$rows" ] && return 0
  while IFS=$'\t' read -r rg name; do
    [ -z "$name" ] && continue
    run_mutation "az webapp stop ${rg}/${name}" az webapp stop --resource-group "$rg" --name "$name"
  done <<< "$rows"
}

stop_function_apps(){
  local rows
  rows=$(az functionapp list --query '[?state==`Running`].[resourceGroup,name]' -o tsv 2>/dev/null || true)
  [ -z "$rows" ] && return 0
  while IFS=$'\t' read -r rg name; do
    [ -z "$name" ] && continue
    run_mutation "az functionapp stop ${rg}/${name}" az functionapp stop --resource-group "$rg" --name "$name"
  done <<< "$rows"
}

if [ "$DRY_RUN" = "true" ]; then
  list_resources
  log "azure_dry_run_listed_resources"
  exit 0
fi

echo "Performing Azure cleanup..."
log "azure_cleanup_started"

stop_vms
stop_app_services
stop_function_apps

log "azure_cleanup_completed"
echo "Azure cleanup completed"
