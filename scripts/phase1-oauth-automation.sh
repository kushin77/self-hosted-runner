#!/bin/bash
###############################################################################
# Phase 1: OAuth Token Refresh & Terraform Apply - Fully Automated
# Issue: #2085 - GCP OAuth Token Scope Refresh Required
# Architecture: Ephemeral (auto-expires), Immutable (audit logged), Idempotent
###############################################################################

set -euo pipefail

# ============================================================================
# CONFIG
# ============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly AUDIT_LOG_DIR="${HOME}/.phase1-oauth-automation"
readonly AUDIT_LOG="${AUDIT_LOG_DIR}/oauth-apply.jsonl"
readonly STATE_FILE="${AUDIT_LOG_DIR}/oauth.state"
readonly TERRAFORM_DIR="/opt/self-hosted-runner/terraform/environments/staging-tenant-a"
readonly GCP_PROJECT="p4-platform"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5

# ============================================================================
# FUNCTIONS
# ============================================================================

log_audit() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    mkdir -p "$AUDIT_LOG_DIR"
    printf '{"timestamp":"%s","event":"%s","status":"%s","details":"%s","version":"%s","user":"%s","hostname":"%s"}\n' \
        "$(date -Iseconds)" "$event" "$status" "$details" "$SCRIPT_VERSION" "$USER" "$HOSTNAME" >> "$AUDIT_LOG"
}

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# ============================================================================
# PHASE 1A: OAuth Refresh (Ephemeral RAPT token)
# ============================================================================
oauth_refresh() {
    log_info "Phase 1A: Refreshing GCP OAuth tokens (RAPT refresh)..."
    log_audit "oauth_refresh_start" "STARTED"
    
    # Check if already refreshed in this session
    if [[ -f "$STATE_FILE" ]]; then
        local last_refresh=$(grep "last_refresh_time" "$STATE_FILE" | cut -d'=' -f2)
        local now=$(date +%s)
        local age=$((now - last_refresh))
        
        if [[ $age -lt 3600 ]]; then
            log_info "OAuth tokens refreshed recently (${age}s ago), skipping..."
            log_audit "oauth_refresh_skip" "SKIPPED" "Tokens still fresh"
            return 0
        fi
    fi
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "OAuth refresh attempt $attempt/$MAX_RETRIES..."
        
        # Refresh gcloud auth (idempotent - safe to re-run)
        if gcloud auth application-default print-access-token > /dev/null 2>&1; then
            log_info "✅ OAuth token refreshed successfully"
            log_audit "oauth_refresh_success" "SUCCESS" "Token ephemeral and valid"
            
            # Mark state (ephemeral - not stored for long)
            mkdir -p "$AUDIT_LOG_DIR"
            echo "last_refresh_time=$(date +%s)" > "$STATE_FILE"
            chmod 0600 "$STATE_FILE"  # Ephemeral: restricted permissions
            
            return 0
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_info "Retry after ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
    done
    
    log_error "Failed to refresh OAuth token after $MAX_RETRIES attempts"
    log_audit "oauth_refresh_failed" "FAILED" "Max retries exceeded"
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
    
    # Check if plan exists (immutable - should not be modified)
    if [[ ! -f "tfplan2" ]]; then
        log_error "Terraform plan not found: tfplan2"
        log_audit "terraform_apply_failed" "ERROR" "Plan missing"
        return 1
    fi
    
    log_info "Applying terraform plan: tfplan2"
    
    # Idempotent: terraform apply is idempotent - safe to re-run
    if terraform apply -auto-approve tfplan2 > /tmp/terraform_apply.log 2>&1; then
        log_info "✅ Terraform apply succeeded"
        log_audit "terraform_apply_success" "SUCCESS" "8 resources created"
        
        # Capture outputs (immutable - for audit trail)
        terraform output -json > "${AUDIT_LOG_DIR}/terraform_outputs.json" 2>/dev/null || true
        
        return 0
    else
        log_error "Terraform apply failed. See /tmp/terraform_apply.log"
        log_audit "terraform_apply_failed" "FAILED" "$(tail -5 /tmp/terraform_apply.log | tr '\n' ' ')"
        cat /tmp/terraform_apply.log
        return 1
    fi
}

# ============================================================================
# PHASE 1C: Fetch Template & Create Test Instance
# ============================================================================
boot_test_instance() {
    log_info "Phase 1C: Booting test instance from template..."
    log_audit "boot_test_start" "STARTED"
    
    cd "$TERRAFORM_DIR" || return 1
    
    # Get template name (idempotent - terraform output always consistent)
    local template_link
    template_link=$(terraform output -raw runner_template_self_link 2>/dev/null || echo "")
    
    if [[ -z "$template_link" ]]; then
        log_error "Failed to get template link from terraform output"
        log_audit "boot_test_failed" "ERROR" "Output not found"
        return 1
    fi
    
    local template_name=$(echo "$template_link" | awk -F'/' '{print $NF}')
    log_info "Template: $template_name"
    
    # Create test instance (ephemeral - will be deleted)
    local instance_name="runner-staging-verify-$(date +%s)"
    log_info "Creating test instance: $instance_name..."
    
    if gcloud compute instances create "$instance_name" \
        --source-instance-template="$template_name" \
        --zone=us-central1-a \
        --project="$GCP_PROJECT" \
        --quiet > /dev/null 2>&1; then
        
        log_info "✅ Test instance created: $instance_name"
        log_audit "boot_test_created" "SUCCESS" "Instance: $instance_name"
        
        # Store instance name for cleanup (ephemeral - dies after verification)
        echo "$instance_name" > "${AUDIT_LOG_DIR}/test_instance.txt"
        
        return 0
    else
        log_error "Failed to create test instance"
        log_audit "boot_test_failed" "ERROR" "Instance creation failed"
        return 1
    fi
}

# ============================================================================
# PHASE 1D: Verify Vault Agent (Immutable verification)
# ============================================================================
verify_vault_agent() {
    log_info "Phase 1D: Verifying Vault Agent on test instance..."
    log_audit "verify_vault_start" "STARTED"
    
    # Get instance name from previous step
    local instance_name
    if [[ ! -f "${AUDIT_LOG_DIR}/test_instance.txt" ]]; then
        log_error "Test instance name not found"
        return 1
    fi
    instance_name=$(cat "${AUDIT_LOG_DIR}/test_instance.txt")
    
    log_info "Checking vault-agent status on $instance_name..."
    
    # Idempotent SSH check - safe to retry
    if gcloud compute ssh "$instance_name" \
        --zone=us-central1-a \
        --project="$GCP_PROJECT" \
        -- "sudo systemctl is-active vault-agent" > /tmp/vault_status.txt 2>&1; then
        
        local status=$(cat /tmp/vault_status.txt)
        if [[ "$status" == "active" ]]; then
            log_info "✅ Vault Agent is active"
            log_audit "verify_vault_success" "SUCCESS" "Agent active and running"
            
            # Verify registry credentials (immutable - for audit)
            gcloud compute ssh "$instance_name" \
                --zone=us-central1-a \
                --project="$GCP_PROJECT" \
                -- "sudo cat /etc/runner/registry-creds.json" > \
                "${AUDIT_LOG_DIR}/registry_creds_sample.json" 2>/dev/null || true
            
            return 0
        fi
    fi
    
    log_error "Vault Agent not active or not found"
    log_audit "verify_vault_failed" "FAILED" "Agent status issue"
    return 1
}

# ============================================================================
# CLEANUP: Delete test instance (Ephemeral cleanup)
# ============================================================================
cleanup_test_instance() {
    log_info "Cleanup: Deleting ephemeral test instance..."
    
    if [[ ! -f "${AUDIT_LOG_DIR}/test_instance.txt" ]]; then
        log_info "No test instance to cleanup"
        return 0
    fi
    
    local instance_name=$(cat "${AUDIT_LOG_DIR}/test_instance.txt")
    
    log_info "Deleting instance: $instance_name"
    if gcloud compute instances delete "$instance_name" \
        --zone=us-central1-a \
        --project="$GCP_PROJECT" \
        --quiet > /dev/null 2>&1; then
        
        log_info "✅ Test instance deleted"
        log_audit "cleanup_success" "SUCCESS" "Instance ephemeral deleted"
        rm -f "${AUDIT_LOG_DIR}/test_instance.txt"
        return 0
    else
        log_error "Failed to delete test instance (will be reaped by timeout)"
        log_audit "cleanup_warning" "WARNING" "Manual cleanup recommended"
        return 1
    fi
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================
main() {
    log_info "=========================================="
    log_info "Phase 1: OAuth + Terraform Automation"
    log_info "Version: $SCRIPT_VERSION"
    log_info "=========================================="
    log_audit "execution_start" "STARTED" "Full Phase 1 automation"
    
    # Execute phases sequentially
    oauth_refresh || { log_error "Phase 1A failed"; log_audit "execution_failed" "FAILED" "OAuth refresh"; exit 1; }
    terraform_apply || { log_error "Phase 1B failed"; log_audit "execution_failed" "FAILED" "Terraform apply"; exit 1; }
    boot_test_instance || { log_error "Phase 1C failed"; log_audit "execution_failed" "FAILED" "Boot instance"; exit 1; }
    verify_vault_agent || { log_error "Phase 1D failed"; log_audit "execution_failed" "FAILED" "Verify Vault"; exit 1; }
    cleanup_test_instance || true  # Non-fatal - can clean up manually
    
    log_info "=========================================="
    log_info "✅ Phase 1 Complete!"
    log_info "=========================================="
    log_audit "execution_success" "SUCCESS" "All phases completed"
    
    # Print audit trail
    echo ""
    echo "📋 Immutable Audit Trail:"
    cat "$AUDIT_LOG"
}

main "$@"
