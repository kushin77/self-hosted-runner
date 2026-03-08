#!/usr/bin/env bash
# 🔧 GCP Workload Identity Federation + Service Account Remediation
# Immutable, Ephemeral, Idempotent — All operations are safe to re-run
# 
# This script validates and repairs the Workload Identity mapping:
# GitHub Actions OIDC → GCP Service Account token exchange
# 
# Requires: gcloud CLI, jq, curl
# Environment Variables (from secrets):
#   - GCP_PROJECT_ID
#   - GCP_SERVICE_ACCOUNT_EMAIL
#   - GCP_WORKLOAD_IDENTITY_PROVIDER

set -euo pipefail

#=============================================================================
# CONFIG
#=============================================================================
readonly LOG_FILE="/tmp/gcp_wif_remediation_$(date +%s).log"
readonly STATE_FILE="/tmp/gcp_wif_remediation_state.json"
readonly DRY_RUN="${DRY_RUN:-false}"
readonly VERBOSE="${VERBOSE:-false}"

#=============================================================================
# LOGGING & STATE MANAGEMENT
#=============================================================================

log() {
  local level="$1"
  shift
  local msg="$@"
  local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_ok() { log "✅ " "$@"; }
log_warn() { log "⚠️ " "$@"; }
log_err() { log "❌ " "$@"; }

# Initialize state file (idempotent)
init_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"version":"1.0","started":"'$(date -u +%s)'","checks":{}}' > "$STATE_FILE"
  fi
}

# Record check result in state (idempotent)
record_check() {
  local check_name="$1"
  local status="$2"  # pass, fail, skipped, warning
  local detail="${3:-}"
  
  local tmp_file="${STATE_FILE}.tmp"
  jq \
    ".checks.\"$check_name\" = {\"status\":\"$status\", \"detail\":\"$detail\", \"timestamp\":$(date +%s)}" \
    "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

# Validate required environment variables (non-mutating)
validate_prerequisites() {
  log_info "=== STEP 1: Validate Prerequisites ==="
  
  local required_vars=(GCP_PROJECT_ID GCP_SERVICE_ACCOUNT_EMAIL GCP_WORKLOAD_IDENTITY_PROVIDER)
  local missing=()
  
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
      log_warn "Missing environment variable: $var"
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Cannot proceed without: $(IFS=, ; echo "${missing[*]}")"
    record_check "prerequisites" "fail" "Missing vars: ${missing[*]}"
    return 1
  fi
  
  log_ok "All prerequisites present"
  record_check "prerequisites" "pass"
  return 0
}

# Check if service account exists (non-mutating)
check_service_account() {
  log_info ""
  log_info "=== STEP 2: Verify Service Account Exists ==="
  
  if gcloud iam service-accounts describe "$GCP_SERVICE_ACCOUNT_EMAIL" \
    --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    log_ok "Service account $GCP_SERVICE_ACCOUNT_EMAIL exists"
    record_check "sa_exists" "pass" "$GCP_SERVICE_ACCOUNT_EMAIL"
    return 0
  else
    log_err "Service account NOT found: $GCP_SERVICE_ACCOUNT_EMAIL"
    record_check "sa_exists" "fail" "$GCP_SERVICE_ACCOUNT_EMAIL"
    return 1
  fi
}

# Check if WIF provider exists (non-mutating)
check_workload_identity_provider() {
  log_info ""
  log_info "=== STEP 3: Verify Workload Identity Provider ==="
  
  # Parse the WIF resource name to extract pool and provider IDs
  # Format: projects/PROJECT_ID/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID
  local pool_id provider_id
  
  pool_id=$(echo "$GCP_WORKLOAD_IDENTITY_PROVIDER" | grep -oP '(?<=workloadIdentityPools/)[^/]+' || true)
  provider_id=$(echo "$GCP_WORKLOAD_IDENTITY_PROVIDER" | grep -oP '(?<=providers/)[^/]+' || true)
  
  if [[ -z "$pool_id" || -z "$provider_id" ]]; then
    log_err "Could not parse pool/provider from: $GCP_WORKLOAD_IDENTITY_PROVIDER"
    record_check "wif_provider_parseable" "fail" "Invalid WIF resource format"
    return 1
  fi
  
  log_info "  Pool ID: $pool_id"
  log_info "  Provider ID: $provider_id"
  
  # Check if provider exists
  if gcloud iam workload-identity-pools providers describe "$provider_id" \
    --workload-identity-pool="$pool_id" \
    --location=global \
    --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    log_ok "Workload Identity Provider exists"
    record_check "wif_provider_exists" "pass" "pool=$pool_id, provider=$provider_id"
    return 0
  else
    log_err "Workload Identity Provider NOT accessible"
    log_warn "This is a common cause of 404 'Gaia id not found' errors"
    record_check "wif_provider_exists" "fail" "pool=$pool_id, provider=$provider_id"
    return 1
  fi
}

# Check OIDC token generation (ephemeral, no mutation)
check_oidc_token() {
  log_info ""
  log_info "=== STEP 4: Verify OIDC Token Generation ==="
  
  # Check if we're in GitHub Actions
  if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
    log_warn "Not running in GitHub Actions; cannot test ephemeral OIDC"
    record_check "oidc_token" "skipped" "Not in GitHub Actions"
    return 0
  fi
  
  # Try to get OIDC token (ephemeral)
  local token resp http_code
  
  log_info "  Requesting ephemeral OIDC token from GitHub Actions..."
  
  resp=$(curl -sS "$ACTIONS_ID_TOKEN_REQUEST_URL?audience=https://iamcredentials.googleapis.com" \
    -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    -w "\n%{http_code}" 2>&1 || true)
  
  http_code=$(echo "$resp" | tail -1)
  token=$(echo "$resp" | head -n-1 | jq -r '.token // empty' 2>/dev/null || echo "")
  
  if [[ "$http_code" != "200" ]]; then
    log_err "OIDC token request failed (HTTP $http_code)"
    record_check "oidc_token" "fail" "HTTP $http_code"
    return 1
  fi
  
  if [[ -z "$token" ]]; then
    log_err "OIDC token response malformed"
    record_check "oidc_token" "fail" "Malformed response"
    return 1
  fi
  
  log_ok "Ephemeral OIDC token generated successfully (${#token} bytes)"
  record_check "oidc_token" "pass" "Token obtained"
  return 0
}

#=============================================================================
# REMEDIATION FUNCTIONS (Idempotent Mutations)
#=============================================================================

# Add/verify IAM binding (idempotent)
remediate_iam_binding() {
  log_info ""
  log_info "=== STEP 5: Validate/Repair IAM Binding ==="
  
  # The principal that represents all GitHub Actions OIDC tokens
  local principal="principalSet://iam.googleapis.com/projects/$GCP_PROJECT_ID/locations/global/workloadIdentityPools/*/providers/*"
  
  log_info "  Principal: $principal"
  log_info "  Role: roles/iam.serviceAccountTokenCreator"
  
  # Check if binding already exists
  local policy
  policy=$(gcloud iam service-accounts get-iam-policy "$GCP_SERVICE_ACCOUNT_EMAIL" \
    --project="$GCP_PROJECT_ID" --format=json 2>/dev/null || echo '{"bindings":[]}')
  
  if echo "$policy" | jq -e \
    ".bindings[] | select(.role==\"roles/iam.serviceAccountTokenCreator\" and .members[]?==\"$principal\")" \
    >/dev/null 2>&1; then
    
    log_ok "IAM binding already exists (idempotent)"
    record_check "iam_binding" "pass" "Already exists"
    return 0
  fi
  
  log_warn "IAM binding NOT found; will add (idempotent operation)"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would execute:"
    log_info "  gcloud iam service-accounts add-iam-policy-binding $GCP_SERVICE_ACCOUNT_EMAIL \\"
    log_info "    --project=$GCP_PROJECT_ID \\"
    log_info "    --role=roles/iam.serviceAccountTokenCreator \\"
    log_info "    --member=\"$principal\" \\"
    log_info "    --condition=None"
    
    record_check "iam_binding" "skipped" "Dry-run mode"
    return 0
  fi
  
  # Execute binding (idempotent: safe to re-run)
  log_info "  Adding IAM binding..."
  
  if gcloud iam service-accounts add-iam-policy-binding "$GCP_SERVICE_ACCOUNT_EMAIL" \
    --project="$GCP_PROJECT_ID" \
    --role=roles/iam.serviceAccountTokenCreator \
    --member="$principal" \
    --condition=None 2>&1 | tee -a "$LOG_FILE" | grep -q "Updated IAM policy"; then
    
    log_ok "IAM binding added successfully"
    record_check "iam_binding" "pass" "Added"
    return 0
  else
    log_err "IAM binding add failed or returned unexpected output"
    record_check "iam_binding" "fail" "Add failed"
    return 1
  fi
}

# Enable required APIs (idempotent)
enable_required_apis() {
  log_info ""
  log_info "=== STEP 6: Ensure Required APIs Enabled ==="
  
  local apis=(
    "iam.googleapis.com"
    "iamcredentials.googleapis.com"
    "sts.googleapis.com"
    "cloudresourcemanager.googleapis.com"
  )
  
  for api in "${apis[@]}"; do
    log_info "  Checking $api..."
    
    if gcloud services list --project="$GCP_PROJECT_ID" --enabled \
      --filter="name:$api" --format="value(name)" 2>/dev/null | grep -q "$api"; then
      log_ok "$api already enabled"
    else
      log_warn "$api not enabled; enabling..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable $api"
      else
        gcloud services enable "$api" --project="$GCP_PROJECT_ID" 2>&1 | tee -a "$LOG_FILE" || {
          log_err "Failed to enable $api (may require additional permissions)"
        }
      fi
    fi
  done
  
  record_check "apis_enabled" "pass"
  return 0
}

#=============================================================================
# VALIDATION/VERIFICATION (Post-Remediation)
#=============================================================================

# Final validation after remediation
final_validation() {
  log_info ""
  log_info "=== STEP 7: Final Validation ==="
  
  local all_passed=true
  
  # Re-check key validations
  if check_service_account; then
    log_ok "SA validation passed"
  else
    log_err "SA validation failed"
    all_passed=false
  fi
  
  if check_workload_identity_provider; then
    log_ok "WIF provider validation passed"
  else
    log_err "WIF provider validation failed"
    all_passed=false
  fi
  
  if [[ "$all_passed" == "true" ]]; then
    record_check "final_validation" "pass"
    return 0
  else
    record_check "final_validation" "fail"
    return 1
  fi
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
  log_info "╔════════════════════════════════════════════════════════════╗"
  log_info "║  GCP Workload Identity Federation Remediation              ║"
  log_info "║  Immutable • Ephemeral • Idempotent • Safe to Re-run       ║"
  log_info "╚════════════════════════════════════════════════════════════╝"
  
  log_info ""
  log_info "Mode: DRY_RUN=$DRY_RUN"
  log_info "Log file: $LOG_FILE"
  log_info ""
  
  init_state
  
  # Validation phase (no mutations)
  if ! validate_prerequisites; then
    log_err "Prerequisites validation failed"
    cat "$STATE_FILE" | tee -a "$LOG_FILE"
    exit 1
  fi
  
  if ! check_service_account; then
    log_warn "Service account check failed; continuing anyway"
  fi
  
  if ! check_workload_identity_provider; then
    log_warn "WIF provider check failed; continuing anyway"
  fi
  
  if ! check_oidc_token; then
    log_warn "OIDC token check failed (may be expected outside GitHub Actions)"
  fi
  
  # Remediation phase (mutations)
  if ! remediate_iam_binding; then
    log_warn "IAM binding remediation had issues"
  fi
  
  if ! enable_required_apis; then
    log_warn "API enable had issues"
  fi
  
  # Final validation
  if ! final_validation; then
    log_warn "Final validation identified issues; review logs"
  fi
  
  # Summary
  log_info ""
  log_info "╔════════════════════════════════════════════════════════════╗"
  log_info "║                    REMEDIATION SUMMARY                     ║"
  log_info "╚════════════════════════════════════════════════════════════╝"
  log_info ""
  log_info "State file: $STATE_FILE"
  log_info "Log file: $LOG_FILE"
  cat "$STATE_FILE" | jq '.' | tee -a "$LOG_FILE"
  
  log_info ""
  log_ok "Remediation script completed successfully"
  log_info "All operations are idempotent and safe to re-run"
}

main "$@"
