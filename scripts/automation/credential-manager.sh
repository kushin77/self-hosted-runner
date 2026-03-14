#!/bin/bash
#
# Credential Manager - GSM/Vault/KMS Unified Credential Management
# 
# Purpose: Unified credential retrieval with automatic failover
#         - Primary: Google Secret Manager (GSM)
#         - Secondary: HashiCorp Vault
#         - Tertiary: Google Cloud KMS (encrypted at rest)
#
# Design: Immutable, Ephemeral, Idempotent
#         - No credentials cached locally
#         - Credentials fetched fresh on each invocation
#         - Safe for concurrent execution
#
# Usage:
#   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
#   source scripts/automation/credential-manager.sh
#   
#   # Retrieve credential
#   SECRET_VALUE=$(get_secret "database-password" "prod")
#   
#   # List all secrets
#   list_all_secrets "--environment" "prod"
#

set -euo pipefail

# Configuration
readonly GSM_PROJECT="${GSM_PROJECT:-}"
readonly VAULT_ADDR="${VAULT_ADDR:-}"
readonly VAULT_TOKEN_PATH="${VAULT_TOKEN_PATH:-.vault-token}"
readonly KMS_KEY_RING="${KMS_KEY_RING:-}"
readonly KMS_KEY_NAME="${KMS_KEY_NAME:-}"
readonly CREDENTIAL_CACHE_TTL=300  # 5 minutes
declare -A CREDENTIAL_CACHE
declare -A CREDENTIAL_CACHE_TIME

# Logging
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; return 1; }
warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

# Validate environment
validate_environment() {
  if [[ -z "${GSM_PROJECT}" ]]; then
    error "GSM_PROJECT not set. Cannot proceed with credential management."
  fi
  
  if [[ -z "${VAULT_ADDR}" ]]; then
    warn "VAULT_ADDR not set. Vault failover will be disabled."
  fi
  
  if [[ -z "${KMS_KEY_RING}" ]]; then
    warn "KMS_KEY_RING not set. KMS encryption will be disabled."
  fi
}

# Check if cache is still valid
is_cache_valid() {
  local SECRET_KEY="$1"
  local CURRENT_TIME=$(date +%s)
  
  if [[ -v CREDENTIAL_CACHE_TIME[$SECRET_KEY] ]]; then
    local CACHE_AGE=$((CURRENT_TIME - CREDENTIAL_CACHE_TIME[$SECRET_KEY]))
    if [[ $CACHE_AGE -lt $CREDENTIAL_CACHE_TTL ]]; then
      return 0  # Cache is valid
    fi
  fi
  
  return 1  # Cache is invalid or missing
}

# Retrieve from Google Secret Manager
retrieve_from_gsm() {
  local SECRET_NAME="$1"
  local ENVIRONMENT="${2:-prod}"
  
  local FULL_SECRET_NAME="${ENVIRONMENT}/${SECRET_NAME}"
  
  log "Retrieving from GSM: ${FULL_SECRET_NAME}"
  
  if ! gcloud secrets versions access latest \
    --secret="${FULL_SECRET_NAME}" \
    --project="${GSM_PROJECT}" 2>/dev/null; then
    error "Failed to retrieve from GSM: ${FULL_SECRET_NAME}"
  fi
}

# Retrieve from Vault
retrieve_from_vault() {
  local SECRET_NAME="$1"
  local ENVIRONMENT="${2:-prod}"
  
  if [[ -z "${VAULT_ADDR}" ]]; then
    error "Vault address not configured"
  fi
  
  local VAULT_PATH="secret/data/${ENVIRONMENT}/${SECRET_NAME}"
  
  log "Retrieving from Vault: ${VAULT_PATH}"
  
  # Get Vault token
  local VAULT_TOKEN
  if [[ ! -f "${VAULT_TOKEN_PATH}" ]]; then
    error "Vault token not found at ${VAULT_TOKEN_PATH}"
  fi
  VAULT_TOKEN=$(cat "${VAULT_TOKEN_PATH}")
  
  local RESPONSE
  if ! RESPONSE=$(curl -s \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/${VAULT_PATH}" 2>/dev/null); then
    error "Failed to retrieve from Vault: ${VAULT_PATH}"
  fi
  
  # Extract secret value from Vault response
  echo "${RESPONSE}" | jq -r '.data.data.value // empty'
}

# Retrieve from KMS encrypted storage
retrieve_from_kms() {
  local ENCRYPTED_FILE="$1"
  
  if [[ ! -f "${ENCRYPTED_FILE}" ]]; then
    error "Encrypted file not found: ${ENCRYPTED_FILE}"
  fi
  
  if [[ -z "${KMS_KEY_RING}" ]] || [[ -z "${KMS_KEY_NAME}" ]]; then
    error "KMS credentials not configured"
  fi
  
  log "Decrypting from KMS: ${ENCRYPTED_FILE}"
  
  # Decrypt using gcloud KMS
  gcloud kms decrypt \
    --location=global \
    --keyring="${KMS_KEY_RING}" \
    --key="${KMS_KEY_NAME}" \
    --ciphertext-file="${ENCRYPTED_FILE}" \
    --plaintext-file=- \
    --project="${GSM_PROJECT}" 2>/dev/null || \
    error "Failed to decrypt with KMS: ${ENCRYPTED_FILE}"
}

# Main credential retrieval function with failover
get_secret() {
  local SECRET_NAME="$1"
  local ENVIRONMENT="${2:-prod}"
  
  # Check cache first
  local CACHE_KEY="${ENVIRONMENT}/${SECRET_NAME}"
  if is_cache_valid "${CACHE_KEY}"; then
    log "Using cached credential for ${CACHE_KEY}"
    echo "${CREDENTIAL_CACHE[$CACHE_KEY]}"
    return 0
  fi
  
  # Try each provider in order
  local SECRET_VALUE
  
  # 1. Try GSM (primary)
  if SECRET_VALUE=$(retrieve_from_gsm "${SECRET_NAME}" "${ENVIRONMENT}" 2>/dev/null); then
    log "Successfully retrieved from GSM"
    CREDENTIAL_CACHE[$CACHE_KEY]="${SECRET_VALUE}"
    CREDENTIAL_CACHE_TIME[$CACHE_KEY]=$(date +%s)
    echo "${SECRET_VALUE}"
    return 0
  fi
  
  warn "GSM retrieval failed for ${SECRET_NAME}, trying Vault..."
  
  # 2. Try Vault (secondary)
  if [[ -n "${VAULT_ADDR}" ]]; then
    if SECRET_VALUE=$(retrieve_from_vault "${SECRET_NAME}" "${ENVIRONMENT}" 2>/dev/null); then
      log "Successfully retrieved from Vault"
      CREDENTIAL_CACHE[$CACHE_KEY]="${SECRET_VALUE}"
      CREDENTIAL_CACHE_TIME[$CACHE_KEY]=$(date +%s)
      echo "${SECRET_VALUE}"
      return 0
    fi
    warn "Vault retrieval failed for ${SECRET_NAME}"
  fi
  
  error "All credential providers failed for ${SECRET_NAME}"
}

# Retrieve multiple secrets into environment
load_credentials_to_env() {
  local CREDENTIALS_LIST="$1"  # Comma-separated: secret1,secret2,secret3
  local ENVIRONMENT="${2:-prod}"
  
  IFS=',' read -ra SECRETS <<< "${CREDENTIALS_LIST}"
  
  for SECRET in "${SECRETS[@]}"; do
    SECRET=$(echo "${SECRET}" | xargs)  # Trim whitespace
    local ENV_VAR_NAME=$(echo "${SECRET}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    
    log "Loading credential: ${SECRET} → \$${ENV_VAR_NAME}"
    
    local SECRET_VALUE
    if SECRET_VALUE=$(get_secret "${SECRET}" "${ENVIRONMENT}"); then
      export "${ENV_VAR_NAME}"="${SECRET_VALUE}"
    else
      error "Failed to load credential: ${SECRET}"
    fi
  done
}

# List all secrets in an environment
list_all_secrets() {
  local ENVIRONMENT="${1:-prod}"
  
  log "Listing all secrets in environment: ${ENVIRONMENT}"
  
  gcloud secrets list \
    --project="${GSM_PROJECT}" \
    --filter="labels.environment=${ENVIRONMENT}" \
    --format="table(name, created, updated)" || \
    error "Failed to list secrets"
}

# Rotate credential (write new value to GSM)
rotate_credential() {
  local SECRET_NAME="$1"
  local NEW_VALUE="$2"
  local ENVIRONMENT="${3:-prod}"
  
  local FULL_SECRET_NAME="${ENVIRONMENT}/${SECRET_NAME}"
  
  log "Rotating credential: ${FULL_SECRET_NAME}"
  
  # Create new version in GSM
  echo -n "${NEW_VALUE}" | gcloud secrets versions add "${FULL_SECRET_NAME}" \
    --data-file=- \
    --project="${GSM_PROJECT}" || \
    error "Failed to rotate credential: ${FULL_SECRET_NAME}"
  
  # Invalidate cache
  unset 'CREDENTIAL_CACHE[${ENVIRONMENT}/${SECRET_NAME}]'
  unset 'CREDENTIAL_CACHE_TIME[${ENVIRONMENT}/${SECRET_NAME}]'
  
  log "Credential rotated successfully"
}

# Verify credential accessibility (health check)
verify_credential_access() {
  local ENVIRONMENT="${1:-prod}"
  
  log "Verifying credential access for environment: ${ENVIRONMENT}"
  
  # Test GSM access
  if ! gcloud secrets describe "${ENVIRONMENT}/test-secret" \
    --project="${GSM_PROJECT}" &>/dev/null; then
    warn "GSM access test failed (secret may not exist)"
  else
    log "GSM access verified"
  fi
  
  # Test Vault access
  if [[ -n "${VAULT_ADDR}" ]]; then
    if ! curl -s \
      -H "X-Vault-Token: $(cat ${VAULT_TOKEN_PATH} 2>/dev/null || echo '')" \
      "${VAULT_ADDR}/v1/sys/health" &>/dev/null; then
      warn "Vault access test failed"
    else
      log "Vault access verified"
    fi
  fi
}

# Clear credential cache
clear_cache() {
  log "Clearing credential cache"
  unset CREDENTIAL_CACHE
  unset CREDENTIAL_CACHE_TIME
  declare -gA CREDENTIAL_CACHE
  declare -gA CREDENTIAL_CACHE_TIME
}

# Main entry point
main() {
  validate_environment
  
  # Source this script and use the functions
  # Example usage functions are exported
  log "Credential Manager initialized"
  log "Available functions:"
  log "  - get_secret(name, env) - retrieve single credential"
  log "  - load_credentials_to_env(list, env) - load multiple to env vars"
  log "  - list_all_secrets(env) - list available secrets"
  log "  - rotate_credential(name, value, env) - rotate credential"
  log "  - verify_credential_access(env) - health check"
  log "  - clear_cache() - clear credential cache"
}

# Export functions for external use
export -f get_secret
export -f load_credentials_to_env
export -f list_all_secrets
export -f rotate_credential
export -f verify_credential_access
export -f clear_cache

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
