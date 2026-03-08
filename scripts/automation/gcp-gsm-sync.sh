#!/bin/bash
################################################################################
# GCP Secret Manager (GSM) Secrets Sync Automation
# 
# Purpose: Synchronize GitHub repository secrets <-> GCP Secret Manager
#          Enable multi-cloud credential management with audit trail
#
# Properties: Immutable (logic in Git) | Ephemeral (state resets) | 
#             Idempotent (safe to re-run) | No-Ops (scheduled automation)
#
# Triggers: GitHub Actions (every 15 minutes via workflow)
# Operator: Hands-off (requires only GCP credentials in secret: GCP_SERVICE_ACCOUNT_KEY)
#
################################################################################

set -euo pipefail

# === CONFIGURATION ===
readonly LOG_FILE="${LOG_FILE:-.github/workflows/logs/gcp-gsm-sync-$(date +%s).log}"
readonly SYNC_LABEL="gh-saas-sync"  # Label for synced secrets
readonly GSM_RETRY_ATTEMPTS=3
readonly GSM_RETRY_DELAY=2
readonly PROJECT_ID="${GCP_PROJECT_ID:-}"
readonly TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# === LOGGING ===
log() {
  echo "[${TIMESTAMP}] $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[${TIMESTAMP}] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
  echo "[${TIMESTAMP}] ✓ $*" | tee -a "$LOG_FILE"
}

# === VALIDATION ===
validate_environment() {
  log "Validating environment..."
  
  if [[ -z "$PROJECT_ID" ]]; then
    log_error "GCP_PROJECT_ID not set"
    return 1
  fi
  
  if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found"
    return 1
  fi
  
  if ! command -v gh &> /dev/null; then
    log_error "gh CLI not found"
    return 1
  fi
  
  # Verify GCP authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_error "Not authenticated to Google Cloud"
    return 1
  fi
  
  log_success "Environment validated"
  return 0
}

# === GCP GSM OPERATIONS ===

# Create or update a GSM secret (idempotent)
gsm_upsert_secret() {
  local secret_name="$1"
  local secret_value="$2"
  local max_attempts=$GSM_RETRY_ATTEMPTS
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))
    
    if gcloud secrets describe "$secret_name" \
      --project="$PROJECT_ID" \
      --format="value(name)" &>/dev/null; then
      # Secret exists - add new version
      log "GSM: Adding new version to secret '$secret_name' (attempt $attempt/$max_attempts)"
      
      if echo -n "$secret_value" | \
         gcloud secrets versions add "$secret_name" \
         --data-file=- \
         --project="$PROJECT_ID" 2>>"$LOG_FILE"; then
        log_success "GSM: Secret '$secret_name' version added"
        return 0
      fi
    else
      # Secret doesn't exist - create it
      log "GSM: Creating secret '$secret_name' (attempt $attempt/$max_attempts)"
      
      if echo -n "$secret_value" | \
         gcloud secrets create "$secret_name" \
         --replication-policy="automatic" \
         --data-file=- \
         --project="$PROJECT_ID" \
         --labels="$SYNC_LABEL=true,created-by=gh-actions" 2>>"$LOG_FILE"; then
        log_success "GSM: Secret '$secret_name' created"
        return 0
      fi
    fi
    
    if [[ $attempt -lt $max_attempts ]]; then
      log "GSM: Retry in ${GSM_RETRY_DELAY}s..."
      sleep $GSM_RETRY_DELAY
    fi
  done
  
  log_error "GSM: Failed to upsert secret '$secret_name' after $max_attempts attempts"
  return 1
}

# Get GSM secret value
gsm_get_secret() {
  local secret_name="$1"
  
  gcloud secrets versions access latest \
    --secret="$secret_name" \
    --project="$PROJECT_ID" 2>/dev/null || return 1
}

# List all GSM secrets synced from GitHub
gsm_list_synced_secrets() {
  gcloud secrets list \
    --filter="labels.$SYNC_LABEL:true" \
    --format="value(name)" \
    --project="$PROJECT_ID" 2>/dev/null || return 1
}

# Get GSM secret metadata
gsm_get_secret_metadata() {
  local secret_name="$1"
  
  gcloud secrets describe "$secret_name" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null || return 1
}

# === GITHUB SECRETS OPERATIONS ===

# Get all GitHub secrets for this repo
github_list_secrets() {
  gh secret list --json name,updatedAt --template='{{range .}}{{.name}}\t{{.updatedAt}}{{"\n"}}{{end}}'
}

# Get GitHub secret value
github_get_secret() {
  local secret_name="$1"
  
  # Note: gh CLI cannot retrieve secret values (security feature)
  # This function is for reference; real sync happens via workflow secrets
  echo "ERROR: Cannot retrieve GitHub secret values via gh CLI"
  return 1
}

# === SYNC OPERATIONS ===

# Sync GitHub secrets to GSM
sync_github_to_gsm() {
  log "Starting GitHub → GSM sync..."
  
  local synced_count=0
  local failed_count=0
  
  # List of critical secrets to sync (configurable)
  local secrets_to_sync=(
    "GCP_SERVICE_ACCOUNT_KEY:gcp-service-account"
    "GCP_PROJECT_ID:gcp-project-id"
    "GCP_WORKLOAD_IDENTITY_PROVIDER:gcp-workload-identity-provider"
    "GCP_SERVICE_ACCOUNT_EMAIL:gcp-service-account-email"
    "AWS_OIDC_ROLE_ARN:aws-oidc-role-arn"
    "AWS_ROLE_TO_ASSUME:aws-role-to-assume"
    "SLACK_BOT_TOKEN:slack-bot-token"
    "VAULT_ADDR:vault-address"
    "VAULT_TOKEN:vault-token"
  )
  
  for secret_mapping in "${secrets_to_sync[@]}"; do
    IFS=':' read -r github_secret_name gsm_secret_name <<< "$secret_mapping"
    
    # GitHub secrets are passed via environment during workflow execution
    # Check if environment variable exists (set by workflow)
    if [[ -n "${!github_secret_name:-}" ]]; then
      local secret_value="${!github_secret_name}"
      
      if gsm_upsert_secret "$gsm_secret_name" "$secret_value"; then
        synced_count=$((synced_count + 1))
        log "✓ Synced: $github_secret_name → GSM:$gsm_secret_name"
      else
        failed_count=$((failed_count + 1))
        log_error "✗ Failed: $github_secret_name → GSM:$gsm_secret_name"
      fi
    else
      log "SKIP: $github_secret_name not available in current context"
    fi
  done
  
  log "GitHub → GSM sync complete: $synced_count synced, $failed_count failed"
  return $([[ $failed_count -eq 0 ]] && echo 0 || echo 1)
}

# Sync GSM secrets back to GitHub (read-only verification)
sync_gsm_to_github_verify() {
  log "Verifying GSM → GitHub state..."
  
  local verified_count=0
  
  # This is verification-only (GitHub secrets can't be written back via CLI)
  for secret_name in $(gsm_list_synced_secrets); do
    if gsm_get_secret "$secret_name" >/dev/null 2>&1; then
      verified_count=$((verified_count + 1))
      log "✓ Verified in GSM: $secret_name"
    else
      log_error "✗ Missing in GSM: $secret_name"
    fi
  done
  
  log "GSM verification complete: $verified_count secrets verified"
  return 0
}

# === AUDIT & COMPLIANCE ===

# Generate sync audit report
generate_audit_report() {
  log "Generating sync audit report..."
  
  local report_file="$LOG_FILE.audit"
  {
    echo "=== GCP GSM Sync Audit Report ==="
    echo "Timestamp: $TIMESTAMP"
    echo "Project: $PROJECT_ID"
    echo ""
    echo "=== Synced Secrets in GSM ==="
    gsm_list_synced_secrets | while read -r secret_name; do
      local metadata
      metadata=$(gsm_get_secret_metadata "$secret_name" 2>/dev/null || echo "{}")
      echo "  - $secret_name"
      echo "    Metadata: $metadata" | head -n 5
    done
    echo ""
    echo "=== Recent Sync Events ==="
    tail -20 "$LOG_FILE"
  } > "$report_file"
  
  log_success "Audit report generated: $report_file"
  return 0
}

# Verify sync consistency
verify_sync_consistency() {
  log "Verifying sync consistency..."
  
  local consistency_check=0
  
  # Verify all expected secrets exist in GSM
  gsm_list_synced_secrets | while read -r secret_name; do
    if ! gsm_get_secret_metadata "$secret_name" >/dev/null 2>&1; then
      log_error "Consistency check failed: $secret_name metadata unreadable"
      consistency_check=1
    fi
  done
  
  if [[ $consistency_check -eq 0 ]]; then
    log_success "Sync consistency verified"
  fi
  
  return $consistency_check
}

# === MAIN EXECUTION ===

main() {
  log "=== GCP GSM Sync Started ==="
  log "Project: $PROJECT_ID"
  
  if ! validate_environment; then
    log_error "Environment validation failed"
    exit 1
  fi
  
  if ! sync_github_to_gsm; then
    log_error "GitHub → GSM sync failed"
    # Don't exit on sync failure - continue with verification
  fi
  
  if ! sync_gsm_to_github_verify; then
    log_error "GSM verification failed"
  fi
  
  if ! verify_sync_consistency; then
    log_error "Consistency verification failed"
  fi
  
  generate_audit_report
  
  log "=== GCP GSM Sync Completed ==="
  log "Details: $LOG_FILE"
  
  return 0
}

# Execute main function
main "$@"
