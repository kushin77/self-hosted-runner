#!/bin/bash
set -u

# Retrieve secrets with multi-tier fallback (GCP → AWS → GitHub → Local)
# Usage: ./scripts/get-secret-with-fallback.sh <secret-name> [tier-order]
# Example: ./scripts/get-secret-with-fallback.sh docker-hub-pat "gcp,aws,github,local"

SECRET_NAME="${1:?Secret name required}"
TIER_ORDER="${2:-gcp,aws,github,local}"

log() { echo "[SECRET] $(date +'%H:%M:%S') $*" >&2; }

get_secret_from_gcp() {
  log "Trying GCP Secret Manager..."
  
  if ! command -v gcloud &>/dev/null; then
    return 1
  fi
  
  local secret
  if secret=$(gcloud secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null); then
    if [[ -n "$secret" ]]; then
      echo "$secret"
      return 0
    fi
  fi
  
  return 1
}

get_secret_from_aws() {
  log "Trying AWS Secrets Manager..."
  
  if ! command -v aws &>/dev/null; then
    return 1
  fi
  
  local secret
  if secret=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region us-east-1 \
    --query 'SecretString' \
    --output text 2>/dev/null); then
    
    if [[ -n "$secret" ]] && [[ "$secret" != "None" ]]; then
      echo "$secret"
      return 0
    fi
  fi
  
  return 1
}

get_secret_from_github() {
  log "Trying GitHub environment..."
  
  # Convert secret name to env var format (uppercase, hyphens to underscores)
  local env_var="${SECRET_NAME^^}"
  env_var="${env_var//-/_}"
  
  if [[ -n "${!env_var:-}" ]]; then
    echo "${!env_var}"
    return 0
  fi
  
  return 1
}

get_secret_from_local() {
  log "Trying local encrypted backup..."
  
  local backup_file=".secret-backup/${SECRET_NAME}.encrypted"
  
  if [[ ! -f "$backup_file" ]]; then
    return 1
  fi
  
  if [[ -z "${BACKUP_ENCRYPTION_KEY:-}" ]]; then
    return 1
  fi
  
  local secret
  if secret=$(openssl enc -aes-256-cbc -d \
    -pass pass:"$BACKUP_ENCRYPTION_KEY" \
    -in "$backup_file" 2>/dev/null); then
    
    if [[ -n "$secret" ]]; then
      echo "$secret"
      return 0
    fi
  fi
  
  return 1
}

# Main retrieval with fallback
main() {
  log "Retrieving: $SECRET_NAME (tiers: $TIER_ORDER)"
  
  IFS=',' read -ra TIERS <<< "$TIER_ORDER"
  
  for tier in "${TIERS[@]}"; do
    tier="${tier// /}"  # Remove whitespace
    
    case "$tier" in
      gcp)
        if result=$(get_secret_from_gcp); then
          log "✓ Retrieved from GCP"
          echo "$result"
          return 0
        fi
        ;;
      aws)
        if result=$(get_secret_from_aws); then
          log "✓ Retrieved from AWS"
          echo "$result"
          return 0
        fi
        ;;
      github)
        if result=$(get_secret_from_github); then
          log "✓ Retrieved from GitHub"
          echo "$result"
          return 0
        fi
        ;;
      local)
        if result=$(get_secret_from_local); then
          log "✓ Retrieved from local backup"
          echo "$result"
          return 0
        fi
        ;;
    esac
  done
  
  log "ERROR: Could not retrieve secret from any tier"
  return 1
}

main "$@"
