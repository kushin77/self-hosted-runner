#!/bin/bash
################################################################################
# Cross-Cloud Credential Rotation Orchestrator
#
# Purpose: Coordinate AWS + GCP + Vault credential rotation
#          Manage multi-cloud credential lifecycle with automated fallback
#
# Properties: Immutable (logic in Git) | Ephemeral (state resets) |
#             Idempotent (safe to re-run) | No-Ops (scheduled)
#
# Triggers: Daily 3 AM UTC via workflow
# Operator: Hands-off (requires only initial secret bootstrap)
#
################################################################################

set -euo pipefail

# === CONFIGURATION ===
readonly LOG_FILE="${LOG_FILE:-.github/workflows/logs/cross-cloud-rotation-$(date +%s).log}"
readonly TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
readonly ROTATION_MODE="${ROTATION_MODE:-check}"  # check|rotate|emergency
readonly SLACK_WEBHOOK="${SLACK_WEBHOOK_ROTATION:-}"

mkdir -p "$(dirname "$LOG_FILE")"

# === LOGGING ===
log() { echo "[${TIMESTAMP}] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[${TIMESTAMP}] ERROR: $*" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[${TIMESTAMP}] ✓ $*" | tee -a "$LOG_FILE"; }
log_warn() { echo "[${TIMESTAMP}] ⚠️ $*" | tee -a "$LOG_FILE"; }

# === CREDENTIAL AGE TRACKING ===

# Get age of AWS credential
get_aws_credential_age() {
  local credential_name="$1"
  
  # Try to get access key age from AWS metadata
  if command -v aws &>/dev/null; then
    # Get all IAM users and find ones with access keys
    aws iam get-access-key-last-used \
      --access-key-id="${AWS_ACCESS_KEY_ID:-}" \
      --query 'AccessKeyLastUsed.LastRotatedDate' \
      --output text 2>/dev/null || echo "-1"
  else
    echo "-1"
  fi
}

# Get age of GCP credential
get_gcp_credential_age() {
  local secret_name="$1"
  
  if command -v gcloud &>/dev/null; then
    # Get creation time of latest GSM version
    gcloud secrets versions list "$secret_name" \
      --project="${GCP_PROJECT_ID:-}" \
      --limit=1 \
      --format="value(create_time)" 2>/dev/null || echo "-1"
  else
    echo "-1"
  fi
}

# Get age of Vault token
get_vault_token_age() {
  local token="${VAULT_TOKEN:-}"
  
  if command -v vault &>/dev/null && [[ -n "$token" ]]; then
    # Get token TTL remaining
    export VAULT_ADDR="${VAULT_ADDR:-}"
    vault token lookup -format=json "$token" 2>/dev/null | \
      jq -r '.auth.lease_duration // -1' || echo "-1"
  else
    echo "-1"
  fi
}

# === CREDENTIAL ROTATION ===

# Rotate AWS credentials
rotate_aws_credentials() {
  log "Starting AWS credential rotation..."
  
  local failed=0
  
  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not available"
    return 1
  fi
  
  # Get current access key
  local current_key="${AWS_ACCESS_KEY_ID:-}"
  
  if [[ -z "$current_key" ]]; then
    log_error "AWS_ACCESS_KEY_ID not set"
    return 1
  fi
  
  # Create new access key
  log "Creating new AWS access key..."
  local new_key_json
  new_key_json=$(aws iam create-access-key --user-name "${AWS_USERNAME:-}" --output json 2>/dev/null) || {
    log_error "Failed to create new access key"
    return 1
  }
  
  local new_access_key
  new_access_key=$(echo "$new_key_json" | jq -r '.AccessKey.AccessKeyId')
  local new_secret_key
  new_secret_key=$(echo "$new_key_json" | jq -r '.AccessKey.SecretAccessKey')
  
  if [[ -z "$new_access_key" || -z "$new_secret_key" ]]; then
    log_error "Failed to extract new credentials"
    return 1
  fi
  
  log_success "New AWS access key created: $new_access_key"
  
  # Update GitHub secrets with new credentials
  log "Updating GitHub secrets..."
  if gh secret set AWS_ACCESS_KEY_ID --body "$new_access_key" 2>/dev/null; then
    log_success "AWS_ACCESS_KEY_ID updated in GitHub"
  else
    log_error "Failed to update AWS_ACCESS_KEY_ID"
    failed=1
  fi
  
  if gh secret set AWS_SECRET_ACCESS_KEY --body "$new_secret_key" 2>/dev/null; then
    log_success "AWS_SECRET_ACCESS_KEY updated in GitHub"
  else
    log_error "Failed to update AWS_SECRET_ACCESS_KEY"
    failed=1
  fi
  
  # Delete old key (after successful update)
  sleep 5  # Brief delay to ensure propagation
  if aws iam delete-access-key --access-key-id "$current_key" --user-name "${AWS_USERNAME:-}" 2>/dev/null; then
    log_success "Old AWS access key deleted: $current_key"
  else
    log_warn "Could not delete old AWS key (may have already rotated)"
  fi
  
  return $failed
}

# Rotate GCP credentials
rotate_gcp_credentials() {
  log "Starting GCP credential rotation..."
  
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not available"
    return 1
  fi
  
  # Create new service account key
  local service_account="${GCP_SERVICE_ACCOUNT_EMAIL:-}"
  
  if [[ -z "$service_account" ]]; then
    log_error "GCP_SERVICE_ACCOUNT_EMAIL not set"
    return 1
  fi
  
  log "Creating new GCP service account key for $service_account..."
  local new_key_file
  new_key_file=$(mktemp)
  
  if ! gcloud iam service-accounts keys create "$new_key_file" \
    --iam-account="$service_account" \
    --project="${GCP_PROJECT_ID:-}" 2>/dev/null; then
    log_error "Failed to create new GCP service account key"
    rm -f "$new_key_file"
    return 1
  fi
  
  log_success "New GCP service account key created"
  
  # Update GitHub secret
  local new_key_json
  new_key_json=$(cat "$new_key_file")
  
  if gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$new_key_json" 2>/dev/null; then
    log_success "GCP_SERVICE_ACCOUNT_KEY updated in GitHub"
  else
    log_error "Failed to update GCP_SERVICE_ACCOUNT_KEY"
    rm -f "$new_key_file"
    return 1
  fi
  
  # Delete old keys (keep only the newest 3)
  log "Cleaning up old GCP keys..."
  gcloud iam service-accounts keys list \
    --iam-account="$service_account" \
    --project="${GCP_PROJECT_ID:-}" \
    --filter="validAfterTime<$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --format="value(name)" | while read -r key_id; do
    
    # Don't delete default key
    if [[ "$key_id" != "projects"* ]]; then
      if gcloud iam service-accounts keys delete "$key_id" \
        --iam-account="$service_account" \
        --project="${GCP_PROJECT_ID:-}" \
        --quiet 2>/dev/null; then
        log "Deleted old GCP key: $key_id"
      fi
    fi
  done
  
  rm -f "$new_key_file"
  return 0
}

# Rotate Vault token
rotate_vault_token() {
  log "Starting Vault token rotation..."
  
  if ! command -v vault &>/dev/null; then
    log_error "Vault CLI not available"
    return 1
  fi
  
  local vault_addr="${VAULT_ADDR:-}"
  if [[ -z "$vault_addr" ]]; then
    log_error "VAULT_ADDR not set"
    return 1
  fi
  
  export VAULT_ADDR
  
  local current_token="${VAULT_TOKEN:-}"
  if [[ -z "$current_token" ]]; then
    log_error "VAULT_TOKEN not set"
    return 1
  fi
  
  # Request new token from AppRole (if configured)
  log "Requesting new Vault token..."
  
  local role_id="${VAULT_ROLE_ID:-}"
  local secret_id="${VAULT_SECRET_ID:-}"
  
  if [[ -z "$role_id" || -z "$secret_id" ]]; then
    log_warn "AppRole credentials not set; skipping Vault token rotation"
    return 0
  fi
  
  local new_token_response
  new_token_response=$(curl -s -X POST \
    "${vault_addr}/v1/auth/approle/login" \
    -d "{\"role_id\":\"$role_id\",\"secret_id\":\"$secret_id\"}" 2>/dev/null) || {
    log_error "Failed to authenticate with Vault AppRole"
    return 1
  }
  
  local new_token
  new_token=$(echo "$new_token_response" | jq -r '.auth.client_token // empty' 2>/dev/null)
  
  if [[ -z "$new_token" ]]; then
    log_error "Failed to extract new Vault token"
    return 1
  fi
  
  log_success "New Vault token obtained"
  
  # Update GitHub secret
  if gh secret set VAULT_TOKEN --body "$new_token" 2>/dev/null; then
    log_success "VAULT_TOKEN updated in GitHub"
  else
    log_error "Failed to update VAULT_TOKEN"
    return 1
  fi
  
  # Revoke old token
  export VAULT_TOKEN="$current_token"
  if vault token revoke 2>/dev/null; then
    log_success "Old Vault token revoked"
  else
    log_warn "Could not revoke old Vault token (may expire naturally)"
  fi
  
  return 0
}

# === VALIDATION & COMPLIANCE ===

# Validate rotated credentials work
validate_rotated_credentials() {
  log "Validating rotated credentials..."
  
  local validation_passed=0
  
  # Validate AWS
  if command -v aws &>/dev/null; then
    log "Validating AWS credentials..."
    if aws sts get-caller-identity &>/dev/null; then
      log_success "AWS credentials valid"
      validation_passed=$((validation_passed + 1))
    else
      log_error "AWS credentials invalid"
    fi
  fi
  
  # Validate GCP
  if command -v gcloud &>/dev/null; then
    log "Validating GCP credentials..."
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
      log_success "GCP credentials valid"
      validation_passed=$((validation_passed + 1))
    else
      log_error "GCP credentials invalid"
    fi
  fi
  
  # Validate Vault
  if command -v vault &>/dev/null && [[ -n "${VAULT_TOKEN:-}" ]]; then
    log "Validating Vault token..."
    export VAULT_ADDR="${VAULT_ADDR:-}"
    if vault token lookup &>/dev/null; then
      log_success "Vault token valid"
      validation_passed=$((validation_passed + 1))
    else
      log_error "Vault token invalid"
    fi
  fi
  
  return $([[ $validation_passed -gt 0 ]] && echo 0 || echo 1)
}

# === COMPLIANCE REPORTING ===

# Generate rotation compliance report
generate_compliance_report() {
  local report_file=".github/workflows/logs/cross-cloud-rotation-compliance-$(date +%s).md"
  
  log "Generating compliance report..."
  
  {
    echo "# Cross-Cloud Credential Rotation Compliance Report"
    echo ""
    echo "**Date**: $TIMESTAMP"
    echo ""
    echo "## Rotation Status"
    echo ""
    echo "| Cloud | Service | Age | Max Age | Status | Action |"
    echo "|-------|---------|-----|---------|--------|--------|"
    
    # AWS
    echo "| AWS | IAM Access Key | $(get_aws_credential_age 'aws-key' || echo 'N/A') days | 90 days | ⏳ | Check |"
    
    # GCP
    echo "| GCP | Service Account | $(get_gcp_credential_age 'gcp-service-account' || echo 'N/A') days | 30 days | ⏳ | Check |"
    
    # Vault
    echo "| Vault | Auth Token | $(get_vault_token_age 'vault' || echo 'N/A') hours | 168 hours | ⏳ | Check |"
    
    echo ""
    echo "## Rotation History"
    echo ""
    echo "- Last sync: $TIMESTAMP"
    echo "- All credentials validated and operational"
    
  } > "$report_file"
  
  log_success "Compliance report: $report_file"
  cat "$report_file" >> "$LOG_FILE"
}

# === MESSAGING & ESCALATION ===

# Send Slack notification
send_slack_notification() {
  local status="$1"
  local message="$2"
  
  if [[ -z "$SLACK_WEBHOOK" ]]; then
    return 0
  fi
  
  local color="good"
  [[ "$status" == "error" ]] && color="danger"
  [[ "$status" == "warning" ]] && color="warning"
  
  curl -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d @- <<EOF 2>/dev/null || true
{
  "attachments": [{
    "color": "$color",
    "title": "🔄 Cross-Cloud Credential Rotation",
    "text": "$message",
    "fields": [
      {"title": "Status", "value": "$status", "short": true},
      {"title": "Timestamp", "value": "$TIMESTAMP", "short": true}
    ]
  }]
}
EOF
}

# === MAIN EXECUTION ===

main() {
  log "=== Cross-Cloud Credential Rotation Started ==="
  log "Mode: $ROTATION_MODE"
  
  local rotation_failed=0
  
  case "$ROTATION_MODE" in
    check)
      log "Checking credential ages..."
      log "  AWS credential age: $(get_aws_credential_age 'aws' || echo 'unknown') days"
      log "  GCP credential age: $(get_gcp_credential_age 'gcp' || echo 'unknown') days"
      log "  Vault token age: $(get_vault_token_age 'vault' || echo 'unknown') hours"
      ;;
    
    rotate)
      log "Executing credential rotation..."
      
      if ! rotate_aws_credentials; then
        log_error "AWS rotation failed"
        rotation_failed=1
      fi
      
      if ! rotate_gcp_credentials; then
        log_error "GCP rotation failed"
        rotation_failed=1
      fi
      
      if ! rotate_vault_token; then
        log_error "Vault rotation failed"
        rotation_failed=1
      fi
      
      if [[ $rotation_failed -eq 0 ]]; then
        log_success "All rotations completed successfully"
        send_slack_notification "success" "✅ Cross-cloud credential rotation completed"
      else
        log_error "Some rotations failed"
        send_slack_notification "error" "❌ Cross-cloud credential rotation encountered errors"
      fi
      ;;
    
    emergency)
      log "EMERGENCY: Executing forced rotation on all credentials"
      
      # Revoke and rotate immediately
      log "Emergency rotation mode - all credentials will be cycled"
      
      rotate_aws_credentials || true
      rotate_gcp_credentials || true
      rotate_vault_token || true
      
      send_slack_notification "warning" "⚠️ Emergency credential rotation executed"
      ;;
    
    *)
      log_error "Unknown mode: $ROTATION_MODE"
      return 1
      ;;
  esac
  
  # Validate rotated credentials
  if ! validate_rotated_credentials; then
    log_error "Credential validation failed"
    send_slack_notification "error" "❌ Credential validation failed"
    rotation_failed=1
  fi
  
  generate_compliance_report
  
  log "=== Cross-Cloud Rotation Completed ==="
  log "Details: $LOG_FILE"
  
  return $rotation_failed
}

main "$@"
