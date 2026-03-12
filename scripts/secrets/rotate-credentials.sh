#!/usr/bin/env bash
# Credential rotation helper (safe, idempotent, dry-run by default)
# Usage: rotate-credentials.sh [status|github|vault|aws|gcp|all] [--apply]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=true

if [[ "${1-}" == "--apply" || "${2-}" == "--apply" ]]; then
  DRY_RUN=false
fi

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <command> [--apply]

Commands:
  status   - Show what would be rotated (dry-run summary)
  github   - Store/rotate GitHub PAT into GSM (requires GITHUB_PAT env or stdin)
  vault    - Rotate Vault AppRole secret_id (requires VAULT_ADDR + VAULT_TOKEN)
  aws      - Upload AWS access key/secret to GSM (requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)
  gcp      - Create new GSM secret versions for provided values (helper)
  all      - Run the above in sequence

By default runs in dry-run mode. Pass `--apply` to perform changes.
EOF
}

log() { echo "[${SCRIPT_NAME}] $*" >&2; }
err() { echo "[${SCRIPT_NAME}] ERROR: $*" >&2; exit 1; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
  fi
}

gcloud_check() {
  if ! command -v gcloud >/dev/null 2>&1; then
    err "gcloud CLI is required to write to Google Secret Manager (install gcloud or run locally where it's available)"
  fi
}

# GSM helper: create secret if missing, then add a version from stdin
# args: secret_name
gsm_put_secret_version() {
  local secret_name="$1"
  if [[ -z "${GSM_PROJECT-}" ]]; then
    err "GSM_PROJECT env var must be set to the GCP project id for storing secrets"
  fi
  gcloud_check
  if ! gcloud secrets describe "$secret_name" --project="$GSM_PROJECT" >/dev/null 2>&1; then
    log "creating secret $secret_name in project $GSM_PROJECT"
    if $DRY_RUN; then
      log "DRY-RUN: gcloud secrets create $secret_name --project=$GSM_PROJECT --replication-policy=automatic"
    else
      gcloud secrets create "$secret_name" --project="$GSM_PROJECT" --replication-policy=automatic
    fi
  fi
  if $DRY_RUN; then
    log "DRY-RUN: gcloud secrets versions add $secret_name --data-file=- --project=$GSM_PROJECT (from stdin)"
  else
    log "Adding new version to GSM secret $secret_name"
    gcloud secrets versions add "$secret_name" --data-file=- --project="$GSM_PROJECT"
  fi
}

rotate_github() {
  log "Preparing GitHub PAT rotation"
  local secret_name="github-token"
  if [[ -z "${GITHUB_PAT-}" ]]; then
    log "GITHUB_PAT env not set; reading from stdin (EOF to end)"
    if $DRY_RUN; then
      log "DRY-RUN: would read PAT from stdin"
      return 0
    else
      # read from stdin
      read -r -d '' pat || true
      if [[ -z "$pat" ]]; then
        err "No GitHub PAT provided via GITHUB_PAT or stdin"
      fi
      printf "%s" "$pat" | gsm_put_secret_version "$secret_name"
    fi
  else
    if $DRY_RUN; then
      log "DRY-RUN: would store GITHUB_PAT into GSM secret $secret_name"
    else
      printf "%s" "$GITHUB_PAT" | gsm_put_secret_version "$secret_name"
    fi
  fi
}

rotate_vault() {
  log "Preparing Vault AppRole rotation"
  if [[ -z "${VAULT_ADDR-}" || -z "${VAULT_TOKEN-}" ]]; then
    log "VAULT_ADDR or VAULT_TOKEN not set; skipping Vault rotation"
    return 0
  fi
  require_cmd curl
  require_cmd jq
  
  # Validate Vault endpoint is not a placeholder
  if [[ "$VAULT_ADDR" =~ PLACEHOLDER|example|your- ]]; then
    log "VAULT_ADDR contains placeholder; skipping Vault rotation"
    return 0
  fi
  if [[ "$VAULT_TOKEN" =~ PLACEHOLDER|REDACTED|your_ ]]; then
    log "VAULT_TOKEN contains placeholder; skipping Vault rotation"
    return 0
  fi
  
  local approle_role="nexusshield-deployer"
  local secret_id_path="auth/approle/role/${approle_role}/secret-id"
  
  if $DRY_RUN; then
    log "DRY-RUN: Would call Vault API to generate new secret_id for AppRole '$approle_role' and store in GSM"
  else
    log "Requesting new AppRole secret_id from Vault at $VAULT_ADDR"
    
    # Health check first
    if ! curl -sfS --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
      log "WARNING: Vault health check failed; ensuring connectivity..."
    fi
    
    # Generate new secret_id via POST (not GET)
    local new_secret_id
    new_secret_id=$(curl -sS --request POST \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      "$VAULT_ADDR/v1/$secret_id_path" | jq -r '.data.secret_id' 2>/dev/null || true)
    
    if [[ -z "$new_secret_id" || "$new_secret_id" == "null" ]]; then
      log "WARNING: Failed to obtain new AppRole secret_id from Vault API. Check VAULT_ADDR and VAULT_TOKEN — skipping Vault rotation for now"
      return 0
    fi

    log "Successfully obtained new secret_id from Vault"
    printf "%s" "$new_secret_id" | gsm_put_secret_version "vault-example-role-secret_id"
  fi
}

rotate_aws() {
  log "Preparing AWS key rotation"
  if [[ -z "${AWS_ACCESS_KEY_ID-}" || -z "${AWS_SECRET_ACCESS_KEY-}" ]]; then
    log "AWS credentials not provided via env; skipping AWS rotation"
    return 0
  fi
  if $DRY_RUN; then
    log "DRY-RUN: Would store AWS credentials into GSM as aws-access-key-id and aws-secret-access-key"
  else
    printf "%s" "$AWS_ACCESS_KEY_ID" | gsm_put_secret_version "aws-access-key-id"
    printf "%s" "$AWS_SECRET_ACCESS_KEY" | gsm_put_secret_version "aws-secret-access-key"
  fi
}

cmd="${1-}"
case "$cmd" in
  -h|--help|help|"")
    usage
    exit 0
    ;;
  status)
    log "Dry-run: $DRY_RUN"
    log "GSM project: ${GSM_PROJECT-<not-set>}"
    log "Github PAT: ${GITHUB_PAT:+provided via env}"
    log "Vault: ${VAULT_ADDR-<not-set>}"
    log "AWS: ${AWS_ACCESS_KEY_ID:+provided via env}"
    exit 0
    ;;
  github)
    rotate_github
    ;;
  vault)
    rotate_vault
    ;;
  aws)
    rotate_aws
    ;;
  gcp)
    log "gcp subcommand is an alias for github/aws/vault storage steps"
    rotate_github
    rotate_vault
    rotate_aws
    ;;
  all)
    rotate_github
    rotate_vault
    rotate_aws
    ;;
  *)
    err "Unknown command: $cmd"
    ;;
esac

log "Completed (dry-run=$DRY_RUN). Review logs and run with --apply to perform changes."
