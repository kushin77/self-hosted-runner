#!/bin/bash

# wait-and-deploy.sh
# Polls for credential availability and triggers direct-deploy when found.
# Usage: ./wait-and-deploy.sh [gsm|vault|kms] [branch]

set -euo pipefail

CRED_SOURCE="${1:-gsm}"
TARGET_BRANCH="${2:-main}"
GITHUB_ISSUE_ID="${GITHUB_ISSUE_ID:-2072}"
REPO_ROOT="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

# Polling configuration
SLEEP_SECONDS="${SLEEP_SECONDS:-30}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-360}"  # default: 360 attempts -> 3 hours

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

check_gsm() {
  # Return 0 if secret exists
  if gcloud secrets list --filter="name:runner-ssh-key" --format=json | jq 'length > 0' 2>/dev/null | grep -q true; then
    return 0
  fi
  return 1
}

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
    if aws secretsmanager get-secret-value --secret-id runner/ssh-credentials --query SecretString >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

attempt_counter=0
log "Starting wait-and-deploy watcher (source=$CRED_SOURCE, branch=$TARGET_BRANCH)"

while true; do
  attempt_counter=$((attempt_counter+1))

  case "${CRED_SOURCE,,}" in
    gsm)
      if check_gsm; then
        log "GSM secret found. Triggering deploy..."
        GITHUB_ISSUE_ID="$GITHUB_ISSUE_ID" ./scripts/direct-deploy.sh gsm "$TARGET_BRANCH" && exit 0 || {
          log "Deploy failed; will retry after sleep"
        }
      fi
      ;;
    vault)
      if check_vault; then
        log "Vault secret found. Triggering deploy..."
        GITHUB_ISSUE_ID="$GITHUB_ISSUE_ID" ./scripts/direct-deploy.sh vault "$TARGET_BRANCH" && exit 0 || {
          log "Deploy failed; will retry after sleep"
        }
      fi
      ;;
    kms)
      if check_aws; then
        log "AWS secret found. Triggering deploy..."
        GITHUB_ISSUE_ID="$GITHUB_ISSUE_ID" ./scripts/direct-deploy.sh kms "$TARGET_BRANCH" && exit 0 || {
          log "Deploy failed; will retry after sleep"
        }
      fi
      ;;
    *)
      log "Unknown credential source: $CRED_SOURCE"; exit 2
      ;;
  esac

  if [[ "$MAX_ATTEMPTS" -ne 0 && $attempt_counter -ge $MAX_ATTEMPTS ]]; then
    log "Max attempts reached ($MAX_ATTEMPTS). Exiting watcher."; exit 3
  fi

  sleep "$SLEEP_SECONDS"
done
