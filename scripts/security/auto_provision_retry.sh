#!/usr/bin/env bash
set -euo pipefail

# Auto provision retry loop for secrets infra
# Attempts KMS, SSH, GSM provisioning in order with exponential backoff
# Appends immutable JSONL audit entries to ./logs/secrets-deployment/auto-provision.jsonl

LOG_DIR="./logs/secrets-deployment"
LOG_FILE="$LOG_DIR/auto-provision.jsonl"

DRY_RUN=false
MAX_RETRIES=6
INITIAL_DELAY=30

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true; shift;;
    --max-retries)
      MAX_RETRIES="$2"; shift 2;;
    --help)
      echo "Usage: $0 [--dry-run] [--max-retries N]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

mkdir -p "$LOG_DIR"

log_json() {
  local status="$1"; shift
  local msg="$*"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","status":"%s","msg":"%s"}\n' "$ts" "$status" "$msg" >> "$LOG_FILE"
}

run_step() {
  local cmd=("$@")
  if [[ "$DRY_RUN" == "true" ]]; then
    log_json "dry-run" "Would run: ${cmd[*]}"
    return 0
  fi
  if "${cmd[@]}"; then
    log_json "success" "Ran: ${cmd[*]}"
    return 0
  else
    local rc=$?
    log_json "error" "Failed: ${cmd[*]} (rc=$rc)"
    return $rc
  fi
}

steps=(
  "bash scripts/security/provision_kms_key.sh --grant-perms"
  "bash scripts/ops/provision_ssh_key.sh"
  "bash scripts/security/backup_secrets_to_gsm.sh --push-file"
  "bash scripts/cloud/provision_scheduler_job.sh"
)

attempt=0
delay=$INITIAL_DELAY

while [[ $attempt -lt $MAX_RETRIES ]]; do
  attempt=$((attempt+1))
  log_json "info" "Attempt $attempt of $MAX_RETRIES"

  all_ok=true
  for step_cmd in "${steps[@]}"; do
    # shellcheck disable=SC2206
    IFS=' ' read -r -a parts <<< "$step_cmd"
    if ! run_step "${parts[@]}"; then
      all_ok=false
      break
    fi
  done

  if [[ "$all_ok" == "true" ]]; then
    log_json "complete" "All provisioning steps succeeded on attempt $attempt"
    exit 0
  fi

  if [[ "$attempt" -ge $MAX_RETRIES ]]; then
    log_json "failed" "Max retries reached ($MAX_RETRIES). Giving up."
    exit 2
  fi

  log_json "retry" "Sleeping $delay seconds before next attempt"
  sleep "$delay"
  delay=$((delay * 2))
done

exit 1
