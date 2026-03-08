#!/bin/bash

################################################################################
# Secret Management Integration - Vault, GSM, KMS
# P2 Safety Phase - Centralized secret management with multi-cloud support
# Auto-generated as part of 10X Enhancement Phase 2 deployment
# Idempotent: Safe to regenerate and re-source multiple times
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging
log_info() {
  echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] INFO: $*" >&2
}

log_error() {
  echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] ERROR: $*" >&2
}

################################################################################
# Vault Configuration
################################################################################
vault_init() {
  local vault_addr="${VAULT_ADDR:-https://vault.service.consul:8200}"
  local vault_namespace="${VAULT_NAMESPACE:-admin}"
  local auth_method="${VAULT_AUTH_METHOD:-kubernetes}"

  log_info "Initializing Vault connection: $vault_addr (namespace: $vault_namespace)"

  # Validate Vault connectivity
  if ! curl -sf "$vault_addr/v1/sys/health" > /dev/null 2>&1; then
    log_error "Vault server unreachable at $vault_addr"
    return 1
  fi

  # Export for child processes
  export VAULT_ADDR="$vault_addr"
  export VAULT_NAMESPACE="$vault_namespace"

  log_info "✓ Vault initialized successfully"
}

################################################################################
# Vault Secret Retrieval
################################################################################
vault_get_secret() {
  local secret_path="$1"
  local field="${2:-value}"

  if [[ -z "${VAULT_TOKEN:-}" ]] && [[ -z "${VAULT_JWT:-}" ]]; then
    log_error "No Vault authentication available (VAULT_TOKEN or VAULT_JWT required)"
    return 1
  fi

  local response
  if ! response=$(curl -sf \
    -H "X-Vault-Namespace: ${VAULT_NAMESPACE:-admin}" \
    -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
    "${VAULT_ADDR}/v1/${secret_path}"); then
    log_error "Failed to retrieve secret from Vault: $secret_path"
    return 1
  fi

  # Extract field from JSON response
  echo "$response" | jq -r ".data.data.${field} // .data.${field}" 2>/dev/null || return 1
}

################################################################################
# Vault Secret Rotation
################################################################################
vault_rotate_secret() {
  local secret_path="$1"
  local new_value="$2"
  local ttl="${3:-24h}"

  log_info "Rotating secret: $secret_path (TTL: $ttl)"

  if ! curl -sf -X POST \
    -H "X-Vault-Namespace: ${VAULT_NAMESPACE:-admin}" \
    -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
    -H "Content-Type: application/json" \
    -d "{\"data\": {\"value\": \"$new_value\", \"rotated_at\": \"$(date -u -Iseconds)\"}}" \
    "${VAULT_ADDR}/v1/${secret_path}"; then
    log_error "Failed to rotate secret: $secret_path"
    return 1
  fi

  log_info "✓ Secret rotated successfully: $secret_path"
}

################################################################################
# Google Secret Manager (GSM) Integration
################################################################################
gsm_get_secret() {
  local project_id="${1:-${GCP_PROJECT_ID}}"
  local secret_name="$2"
  local version="${3:-latest}"

  if [[ -z "$project_id" ]]; then
    log_error "GCP_PROJECT_ID not set"
    return 1
  fi

  log_info "Retrieving secret from GSM: projects/$project_id/secrets/$secret_name/versions/$version"

  if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not available"
    return 1
  fi

  gcloud secrets versions access "$version" \
    --secret="$secret_name" \
    --project="$project_id" 2>/dev/null || {
    log_error "Failed to retrieve GSM secret: $secret_name"
    return 1
  }
}

################################################################################
# AWS KMS Integration
################################################################################
kms_decrypt_secret() {
  local kms_key_id="${1:-${AWS_KMS_KEY_ID}}"
  local encrypted_data="$2"
  local region="${3:-${AWS_REGION:-us-east-1}}"

  if [[ -z "$kms_key_id" ]]; then
    log_error "AWS_KMS_KEY_ID not set"
    return 1
  fi

  log_info "Decrypting data with KMS key: $kms_key_id (region: $region)"

  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not available"
    return 1
  fi

  local decrypted
  if ! decrypted=$(aws kms decrypt \
    --key-id "$kms_key_id" \
    --ciphertext-blob "fileb://<(echo -n "$encrypted_data" | base64 -d)" \
    --query 'Plaintext' \
    --output text \
    --region "$region" 2>/dev/null); then
    log_error "Failed to decrypt data with KMS"
    return 1
  fi

  echo "$decrypted" | base64 -d || return 1
}

################################################################################
# Multi-Secret Backend Support
################################################################################
get_secret() {
  local secret_name="$1"
  local backend="${SECRET_BACKEND:-vault}"

  case "$backend" in
    vault)
      vault_get_secret "secret/kv/admin/$secret_name"
      ;;
    gsm)
      gsm_get_secret "${GCP_PROJECT_ID}" "$secret_name"
      ;;
    kms)
      log_error "Direct KMS retrieval not supported. Use encrypted_get_secret for KMS."
      return 1
      ;;
    *)
      log_error "Unknown secret backend: $backend"
      return 1
      ;;
  esac
}

################################################################################
# Health Checks
################################################################################
check_secret_backend() {
  local backend="${SECRET_BACKEND:-vault}"

  case "$backend" in
    vault)
      log_info "Checking Vault connectivity..."
      vault_init
      ;;
    gsm)
      log_info "Checking GCP credentials..."
      if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" &>/dev/null; then
        log_error "GCP authentication failed"
        return 1
      fi
      ;;
    kms)
      log_info "Checking AWS credentials..."
      if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS authentication failed"
        return 1
      fi
      ;;
  esac

  log_info "✓ Secret backend health check passed: $backend"
}

################################################################################
# Initialization on source
################################################################################
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Script is being sourced
  log_info "Secret management integration loaded"
  export -f vault_get_secret
  export -f vault_rotate_secret
  export -f gsm_get_secret
  export -f kms_decrypt_secret
  export -f get_secret
  export -f check_secret_backend
  export -f vault_init
else
  # Script is being executed directly
  log_error "This script should be sourced, not executed directly"
  log_info "Usage: source $0"
  exit 1
fi
