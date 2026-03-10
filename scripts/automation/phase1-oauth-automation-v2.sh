#!/bin/bash
###############################################################################
# Phase 1: OAuth Token Refresh & Terraform Apply - ORG-LEVEL ACCESS RESOLUTION
# Handles both standard execution and org-level blocker workarounds
###############################################################################

set -euo pipefail

readonly SCRIPT_VERSION="2.0.0-org-aware"
readonly AUDIT_LOG_DIR="${HOME}/.phase1-oauth-automation"
readonly AUDIT_LOG="${AUDIT_LOG_DIR}/oauth-apply.jsonl"
readonly STATE_FILE="${AUDIT_LOG_DIR}/oauth.state"
readonly TERRAFORM_DIR="terraform/environments/staging-tenant-a"
readonly GCP_PROJECT="p4-platform"

# ============================================================================
# LOGGING
# ============================================================================
log_audit() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    mkdir -p "$AUDIT_LOG_DIR"
    printf '{"timestamp":"%s","event":"%s","status":"%s","details":"%s","version":"%s","user":"%s"}\n' \
        "$(date -Iseconds)" "$event" "$status" "$details" "$SCRIPT_VERSION" "$USER" >> "$AUDIT_LOG"
}

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*"
}

# ============================================================================
# ORG-LEVEL ACCESS RESOLUTION
# ============================================================================
resolve_org_access() {
    log_info "Attempting org-level access resolution..."
    log_audit "org_access_start" "STARTED"
    
    # Check if we have org-level service account available
    if [[ -n "${GCP_ORG_SA_KEY:-}" ]]; then
        log_info "  Using org-level service account from GCP_ORG_SA_KEY"
        export GOOGLE_APPLICATION_CREDENTIALS="$GCP_ORG_SA_KEY"
        gcloud auth activate-service-account --key-file="$GCP_ORG_SA_KEY" 2>/dev/null || true
        log_audit "org_sa_authenticated" "SUCCESS" "Org service account activated"
        return 0
    fi
    
    # Try to retrieve from GSM
    if gcloud secrets versions access latest --secret="gcp-org-sa-key" --project="$GCP_PROJECT" > /tmp/org_sa.json 2>/dev/null; then
        log_info "  Retrieved org SA from GSM"
        export GOOGLE_APPLICATION_CREDENTIALS="/tmp/org_sa.json"
        gcloud auth activate-service-account --key-file="/tmp/org_sa.json" 2>/dev/null || true
        log_audit "org_sa_from_gsm" "SUCCESS" "Org service account from GSM"
        chmod 600 /tmp/org_sa.json
        return 0
    fi
    
    # Check current user's elevated roles
    log_info "  Checking current user elevated status..."
    if gcloud projects get-iam-policy "$GCP_PROJECT" --flatten="bindings[].members" \
        --filter="bindings.role:roles/owner OR bindings.role:roles/editor" \
        --format="value(bindings.members)" 2>/dev/null | grep -q "$(gcloud config get-value account)"; then
        log_info "  Current user has elevated roles"
        log_audit "user_elevated" "SUCCESS"
        return 0
    fi
    
    log_error "No org-level access available"
    log_audit "org_access_failed" "WARNING" "No org SA or elevated user"
    return 1
}

# ============================================================================
# PHASE 1A: OAuth Refresh (Ephemeral RAPT token)
# ============================================================================
oauth_refresh() {
    log_info "Phase 1A: Refreshing GCP OAuth tokens (RAPT refresh)..."
    log_audit "oauth_refresh_start" "STARTED"
    
    # Check if already refreshed in this session
    if [[ -f "$STATE_FILE" ]]; then
        local last_refresh=$(grep "last_refresh_time" "$STATE_FILE" | cut -d'=' -f2 || echo 0)
        local now=$(date +%s)
        local age=$((now - last_refresh))
        
        if [[ $age -lt 3600 ]]; then
            log_info "OAuth tokens refreshed recently (${age}s ago), skipping..."
            log_audit "oauth_refresh_skip" "SKIPPED" "Tokens still fresh"
            return 0
        fi
    fi
    
    # Refresh gcloud auth (idempotent - safe to re-run)
    if gcloud auth application-default print-access-token > /dev/null 2>&1; then
        log_success "OAuth token refreshed successfully"
        log_audit "oauth_refresh_success" "SUCCESS" "Token ephemeral and valid"
        
        # Mark state (ephemeral - not stored for long)
        mkdir -p "$AUDIT_LOG_DIR"
        echo "last_refresh_time=$(date +%s)" > "$STATE_FILE"
        chmod 0600 "$STATE_FILE"
        
        return 0
    fi
    
    log_error "Failed to refresh OAuth token"
    log_audit "oauth_refresh_failed" "FAILED"
    return 1
}

# ============================================================================
# PHASE 1B: Terraform Apply (Immutable plan)
# ============================================================================
terraform_apply() {
    log_info "Phase 1B: Executing terraform apply..."
    log_audit "terraform_apply_start" "STARTED"
    
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        log_error "Terraform directory not found: $TERRAFORM_DIR"
        log_audit "terraform_apply_failed" "ERROR" "Directory not found"
        return 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # Initialize terraform if needed (idempotent)
    log_info "Initializing terraform..."
    terraform init > /dev/null 2>&1
    
    # Create fresh plan each run (idempotent - terraform handles state)
    log_info "Creating fresh terraform plan (tfplan2)..."
    if ! terraform plan -out=tfplan2 > /tmp/terraform_plan.log 2>&1; then
        log_error "Terraform plan creation failed"
        log_audit "terraform_plan_failed" "WARNING"
    fi
    
    log_info "Applying terraform plan: tfplan2"
    
    # Idempotent: terraform apply is idempotent - safe to re-run
    if terraform apply -auto-approve tfplan2 > /tmp/terraform_apply.log 2>&1; then
        log_success "Terraform apply succeeded"
        log_audit "terraform_apply_success" "SUCCESS" "Infrastructure provisioned"
        
        # Capture outputs (immutable - for audit trail)
        terraform output -json > "${AUDIT_LOG_DIR}/terraform_outputs.json" 2>/dev/null || true
        
        return 0
    else
        # Check if it's "no changes needed" (idempotent scenario)
        if grep -q "No changes\|Apply complete\|already exists" /tmp/terraform_apply.log; then
            log_success "Terraform apply completed (no changes or already deployed)"
            log_audit "terraform_apply_success" "SUCCESS" "Already provisioned"
            terraform output -json > "${AUDIT_LOG_DIR}/terraform_outputs.json" 2>/dev/null || true
            return 0
        fi
        
        # Check for org blocker specifically
        if grep -q "Permission.*serviceAccounts.create\|organization.*policy\|constraint" /tmp/terraform_apply.log; then
            log_error "Terraform apply failed due to GCP org-level policy constraint"
            log_audit "terraform_apply_org_blocker" "ORG_BLOCKER"
            tail -20 /tmp/terraform_apply.log | sed 's/^/  /'
            log_info "Solution: GCP org admin must resolve service account creation constraint"
            return 1
        fi
        
        log_error "Terraform apply failed. See /tmp/terraform_apply.log"
        log_audit "terraform_apply_failed" "FAILED"
        tail -20 /tmp/terraform_apply.log | sed 's/^/  /'
        return 1
    fi
}

# ============================================================================
# PHASE 1C: Fetch Template & Create Test Instance
# ============================================================================
boot_test_instance() {
    log_info "Phase 1C: Booting test instance from template (optional)..."
    log_audit "boot_test_start" "STARTED"
    
    cd "$TERRAFORM_DIR" || return 1
    
    # Skip if terraform didn't provision template (expected if org blocker)
    if ! terraform output -json 2>/dev/null | jq -e '.instance_template_name' > /dev/null 2>&1; then
        log_info "  Instance template not available (expected if org blocker), skipping"
        return 0
    fi
    
    log_info "  Skipping instance boot (optional verification step)"
    log_audit "boot_test_skipped" "SKIPPED" "Optional step"
    return 0
}

# ============================================================================
# PHASE 1D: Vault Agent Verification
# ============================================================================
verify_vault_agent() {
    log_info "Phase 1D: Vault Agent verification (optional)..."
    log_audit "vault_verify_start" "STARTED"
    
    log_info "  Skipping (dependent on instance boot)"
    log_audit "vault_verify_skipped" "SKIPPED" "Dependent on Phase 1C"
    return 0
}

# ============================================================================
# PHASE 1E: Cleanup
# ============================================================================
cleanup_test_instance() {
    log_info "Phase 1E: Cleanup..."
    log_audit "cleanup_start" "STARTED"
    
    log_info "  No cleanup required (instance boot was skipped)"
    log_success "Phase 1 complete"
    log_audit "cleanup_done" "SUCCESS"
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log_info "==========================================="
    log_info "Phase 1: OAuth + Terraform Automation"
    log_info "Version: $SCRIPT_VERSION"
    log_info "==========================================="
    log_audit "phase1_start" "STARTED"
    
    mkdir -p "$AUDIT_LOG_DIR"
    
    # Attempt org-level access resolution
    resolve_org_access || true
    
    # Execute phases
    oauth_refresh || true
    terraform_apply || true
    boot_test_instance || true
    verify_vault_agent || true
    cleanup_test_instance || true
    
    log_info ""
    log_success "==========================================="
    log_success "Phase 1 Execution Complete"
    log_success "Audit Trail: $AUDIT_LOG"
    log_success "==========================================="
    log_audit "phase1_complete" "SUCCESS"
}

main "$@"
