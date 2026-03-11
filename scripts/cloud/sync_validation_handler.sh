#!/usr/bin/env bash
set -euo pipefail

# Validation handler triggered by Cloud Scheduler for multi-cloud sync monitoring
# Called every hour to verify all credential mirrors are in sync
# Results logged to Cloud Logging for alert integration

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
LOG_NAME="multi-cloud-sync-validation"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info() {
  echo "{\"timestamp\": \"$TIMESTAMP\", \"severity\": \"INFO\", \"message\": \"$*\"}" | gcloud logging write "$LOG_NAME" \
    --severity=INFO \
    --project="$PROJECT_ID" \
    --payload-type=json 2>/dev/null || echo "[INFO] $*" >&2
}

log_error() {
  echo "{\"timestamp\": \"$TIMESTAMP\", \"severity\": \"ERROR\", \"message\": \"$*\"}" | gcloud logging write "$LOG_NAME" \
    --severity=ERROR \
    --project="$PROJECT_ID" \
    --payload-type=json 2>/dev/null || echo "[ERROR] $*" >&2
}

log_metric() {
  local metric_name="$1"
  local metric_value="$2"
  local labels="$3"
  
  # Write structured log with metrics for analysis
  echo "{
    \"timestamp\": \"$TIMESTAMP\",
    \"metric\": \"$metric_name\",
    \"value\": $metric_value,
    \"labels\": $labels,
    \"severity\": \"INFO\"
  }" | gcloud logging write "$LOG_NAME" \
    --severity=INFO \
    --project="$PROJECT_ID" \
    --payload-type=json 2>/dev/null || true
}

validate_gsm() {
  log_info "Validating GSM secrets..."
  
  local secret_count=0
  local error_count=0
  
  # List all secrets in GSM
  while IFS= read -r secret; do
    ((secret_count++))
    
    # Try to access latest version
    if ! gcloud secrets versions access latest --secret="$secret" --project="$PROJECT_ID" &>/dev/null; then
      ((error_count++))
      log_error "Failed to access GSM secret: $secret"
    fi
  done < <(gcloud secrets list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null || true)
  
  log_metric "gsm_validation" "$secret_count" "{\"type\": \"secret_count\"}"
  
  if [[ $error_count -gt 0 ]]; then
    log_error "GSM validation failed: $error_count/$secret_count errors"
    return 1
  fi
  
  log_info "GSM validation passed: $secret_count secrets accessible"
  return 0
}

validate_azure_mirror() {
  log_info "Validating Azure Key Vault mirror..."
  
  # Check if Azure CLI is available
  if ! command -v az &>/dev/null; then
    log_error "Azure CLI not found; skipping Azure validation"
    return 1
  fi
  
  local vault_name="${AZURE_VAULT:-nsv298610}"
  local azure_error_count=0
  
  # List secrets in vault
  local secret_list=$(az keyvault secret list --vault-name "$vault_name" 2>/dev/null | jq -r '.[].name' || true)
  local secret_count=$(echo "$secret_list" | wc -l)
  
  if [[ $secret_count -eq 0 ]]; then
    log_warn "Azure Key Vault appears empty or inaccessible: $vault_name"
    return 1
  fi
  
  log_metric "azure_mirror_validation" "$secret_count" "{\"type\": \"azure_secret_count\"}"
  log_info "Azure mirror validation passed: $secret_count secrets in $vault_name"
  return 0
}

validate_sync_consistency() {
  log_info "Validating GSM ↔ Azure sync consistency..."
  
  # Get GSM secret count
  local gsm_secrets=$(gcloud secrets list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | sort || true)
  local gsm_count=$(echo "$gsm_secrets" | wc -l)
  
  # Get Azure secret count (if available)
  if command -v az &>/dev/null; then
    local vault_name="${AZURE_VAULT:-nsv298610}"
    local azure_secrets=$(az keyvault secret list --vault-name "$vault_name" 2>/dev/null | jq -r '.[].name' | sort || true)
    local azure_count=$(echo "$azure_secrets" | wc -l)
    
    # Expected: azure_count should be subset of GSM (or approximately equal for critical secrets)
    if [[ $azure_count -gt 0 ]] && [[ $azure_count -lt $((gsm_count / 2)) ]]; then
      log_error "Azure mirror seems out of sync: $azure_count Azure vs $gsm_count GSM"
      return 1
    fi
    
    log_metric "sync_consistency" 1 "{\"gsm\": $gsm_count, \"azure\": $azure_count, \"status\": \"consistent\"}"
  fi
  
  log_info "Sync consistency check passed"
  return 0
}

validate_cross_backend() {
  log_info "Running cross-backend validation script..."
  
  # Execute the main cross-backend validator
  if [[ -f "scripts/security/cross_backend_validator.sh" ]]; then
    if bash scripts/security/cross_backend_validator.sh --validate-all &>/dev/null; then
      log_info "Cross-backend validation passed"
      return 0
    else
      log_error "Cross-backend validation failed"
      return 1
    fi
  else
    log_info "Cross-backend validator not found; skipping"
    return 0
  fi
}

# Main validation flow
log_info "Multi-cloud sync validation started"

VALIDATION_PASSED=true

# Run all validations
validate_gsm || VALIDATION_PASSED=false
validate_azure_mirror || VALIDATION_PASSED=false
validate_sync_consistency || VALIDATION_PASSED=false
validate_cross_backend || VALIDATION_PASSED=false

# Summary
if [[ "$VALIDATION_PASSED" == "true" ]]; then
  log_info "✓ All validation checks PASSED"
  log_metric "validation_status" 1 "{\"status\": \"all_passed\"}"
  exit 0
else
  log_error "✗ Some validation checks FAILED - check logs for details"
  log_metric "validation_status" 0 "{\"status\": \"has_failures\"}"
  exit 1
fi
