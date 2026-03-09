#!/bin/bash

# wait-and-deploy.sh
# Polls for credential availability and triggers direct-deploy when found.
# 
# Supports auto-detection of credential providers in order of preference:
#   1. Vault (VAULT_ADDR + VAULT_TOKEN)
#   2. AWS Secrets Manager (AWS credentials)
#   3. Google Secret Manager (gcloud auth + GCLOUD_PROJECT)
# 
# Usage:
#   ./wait-and-deploy.sh                              # Auto-detect provider
#   ./wait-and-deploy.sh [gsm|vault|aws] [branch]     # Explicit provider

set -euo pipefail

# Configuration
CRED_SOURCE="${1:-auto}"
TARGET_BRANCH="${2:-main}"
GITHUB_ISSUE_ID="${GITHUB_ISSUE_ID:-2072}"
REPO_ROOT="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

# Polling configuration
SLEEP_SECONDS="${SLEEP_SECONDS:-30}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-360}"  # default: 360 attempts -> 3 hours

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

check_vault() {
  if command -v vault >/dev/null 2>&1; then
    if vault kv get -format=json secret/runner-deploy >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

check_aws() {
  if command -v aws >/dev/null 2>&1; then
    if aws secretsmanager get-secret-value --secret-id runner/ssh-credentials --region "${AWS_REGION:-us-east-1}" --query SecretString >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

check_gsm() {
  # Return 0 if secret exists
  local project="${GCLOUD_PROJECT:-elevatediq-runner}"
  if gcloud secrets list --project="$project" --filter="name:runner-ssh-key" --format=json | jq 'length > 0' 2>/dev/null | grep -q true; then
    return 0
  fi
  return 1
}

# Auto-detect credential provider if not explicitly specified
auto_detect_provider() {
  log "Auto-detecting credential provider..."
  
  # Try in order of preference: Vault > AWS > GSM
  if [[ -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" ]]; then
    if check_vault 2>/dev/null; then
      echo "vault"
      return 0
    fi
  fi
  
  if command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1; then
    if check_aws 2>/dev/null; then
      echo "aws"
      return 0
    fi
  fi
  
  if command -v gcloud >/dev/null 2>&1; then
    if check_gsm 2>/dev/null; then
      echo "gsm"
      return 0
    fi
  fi
  
  # No provider ready yet; return empty
  return 1
}

# Resolve credential source
if [[ "${CRED_SOURCE,,}" == "auto" ]]; then
  DETECTED_PROVIDER=$(auto_detect_provider 2>/dev/null || true)
  if [[ -n "$DETECTED_PROVIDER" ]]; then
    log "Selected credential provider: $DETECTED_PROVIDER"
    CRED_SOURCE="$DETECTED_PROVIDER"
  else
    log "No credential provider available yet; will auto-detect on each poll"
    CRED_SOURCE="auto"
  fi
fi


attempt_counter=0
log "Starting wait-and-deploy watcher (source=$CRED_SOURCE, branch=$TARGET_BRANCH)"

while true; do
  attempt_counter=$((attempt_counter+1))

  # If auto mode, detect provider on each attempt
  CURRENT_SOURCE="$CRED_SOURCE"
  if [[ "${CRED_SOURCE,,}" == "auto" ]]; then
    DETECTED=$(auto_detect_provider 2>/dev/null || true)
    if [[ -z "$DETECTED" ]]; then
      CURRENT_SOURCE="waiting"
    else
      CURRENT_SOURCE="$DETECTED"
    fi
  fi

  case "${CURRENT_SOURCE,,}" in
    vault)
      if check_vault 2>/dev/null; then
        log "Vault secret found. Triggering deploy..."
        GITHUB_ISSUE_ID="$GITHUB_ISSUE_ID" ./scripts/direct-deploy.sh vault "$TARGET_BRANCH" && exit 0 || {
          log "Deploy failed; will retry after sleep"
        }
      fi
      ;;
    aws)
      if check_aws 2>/dev/null; then
        log "AWS secret found. Triggering deploy..."
        GITHUB_ISSUE_ID="$GITHUB_ISSUE_ID" ./scripts/direct-deploy.sh aws "$TARGET_BRANCH" && exit 0 || {
          log "Deploy failed; will retry after sleep"
        }
      fi
      ;;
    gsm)
      if check_gsm 2>/dev/null; then
        log "GSM secret found. Triggering deploy..."
        GITHUB_ISSUE_ID="$GITHUB_ISSUE_ID" ./scripts/direct-deploy.sh gsm "$TARGET_BRANCH" && exit 0 || {
          log "Deploy failed; will retry after sleep"
        }
      fi
      ;;
    waiting)
      log "Waiting for credentials (attempt $attempt_counter/$MAX_ATTEMPTS)..."
      ;;
    *)
      log "Unknown credential source: $CURRENT_SOURCE"; exit 2
      ;;
  esac

  if [[ "$MAX_ATTEMPTS" -ne 0 && $attempt_counter -ge $MAX_ATTEMPTS ]]; then
    log "Max attempts reached ($MAX_ATTEMPTS). Exiting watcher."; exit 3
  fi

  sleep "$SLEEP_SECONDS"
done
