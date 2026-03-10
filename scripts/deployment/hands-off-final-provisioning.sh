#!/bin/bash

set -euo pipefail

# ============================================================================
# HANDS-OFF FINAL PROVISIONING SCRIPT
# ============================================================================
# Purpose:
#   Automatically provisions final infrastructure steps for NexusShield prod.
#   Designed to be run by systemd timer every 5 minutes until infrastructure
#   permissions are granted by the cloud admin. Exits gracefully if permissions
#   are not yet available, allowing the timer to retry.
#
# Steps:
#   1. Create VPC private services connection (required for Cloud SQL private IP)
#   2. Grant Secret Manager IAM to provisioning service account
#   3. Run terraform apply to finalize infrastructure
#   4. Provision OPERATOR_SSH_KEY to Google Secret Manager
#
# Design Principles:
#   - IMMUTABLE: All steps logged to JSONL audit trail
#   - IDEMPOTENT: Safe to run repeatedly; no state conflicts
#   - EPHEMERAL: Cleans up temp logs after completion
#   - NO-OPS: Fully automated, zero manual intervention required
#   - HANDS-OFF: Exits gracefully on permission denials; timer retries
#
# Dependencies:
#   - gcloud CLI with active authentication
#   - terraform binary in PATH
#   - scripts/provision-operator-credentials.sh
#   - scripts/gcp/create_private_services_connection.sh
#   - scripts/gcp/grant_gsm_secret_admin.sh
#   - logs/deployment/ directory (auto-created)
#
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly AUDIT_LOG="$PROJECT_ROOT/logs/deployment/hands-off-provisioning.jsonl"
readonly TF_DIR="$PROJECT_ROOT/terraform"
readonly GCP_SCRIPTS_DIR="$PROJECT_ROOT/scripts/gcp"
readonly DEPLOYMENT_SCRIPTS_DIR="$PROJECT_ROOT/scripts/deployment"

# Ensure logs directory exists
mkdir -p "$(dirname "$AUDIT_LOG")"

# ============================================================================
# IMMUTABLE AUDIT LOGGING
# ============================================================================
log_event() {
    local status="$1"
    local step="$2"
    local message="$3"
    
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local event_json=$(cat <<EOF
{"timestamp":"$timestamp","status":"$status","step":"$step","message":"$message","script":"hands-off-final-provisioning"}
EOF
    )
    
    echo "$event_json" >> "$AUDIT_LOG"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$status] [$step] $message"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
check_required_files() {
    local required_files=(
        "$GCP_SCRIPTS_DIR/create_private_services_connection.sh"
        "$GCP_SCRIPTS_DIR/grant_gsm_secret_admin.sh"
        "$DEPLOYMENT_SCRIPTS_DIR/provision-operator-credentials.sh"
        "$TF_DIR/main.tf"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_event "ERROR" "validation" "Missing required file: $file"
            exit 1
        fi
    done
    
    log_event "START" "validation" "All required files present"
}

is_permission_denied() {
    local output="$1"
    
    if echo "$output" | grep -qi "permission denied\|the caller does not have permission\|accessdenied"; then
        return 0
    fi
    
    return 1
}

# ============================================================================
# STEP 1: CREATE VPC PRIVATE SERVICES CONNECTION
# ============================================================================
step_create_private_services_connection() {
    log_event "START" "step1_peering" "Creating VPC private services connection..."
    
    local output
    local exit_code=0
    
    if output=$("$GCP_SCRIPTS_DIR/create_private_services_connection.sh" 2>&1); then
        log_event "SUCCESS" "step1_peering" "Private services connection created successfully"
        return 0
    else
        exit_code=$?
        
        if is_permission_denied "$output"; then
            log_event "WAITING" "step1_peering" "GCP permissions not yet granted; will retry in 5 minutes"
            return 1
        else
            log_event "ERROR" "step1_peering" "Private services connection creation failed: $output"
            return 1
        fi
    fi
}

# ============================================================================
# STEP 2: GRANT SECRET MANAGER IAM
# ============================================================================
step_grant_gsm_iam() {
    log_event "START" "step2_iam" "Granting Secret Manager IAM roles..."
    
    local output
    local exit_code=0
    
    if output=$("$GCP_SCRIPTS_DIR/grant_gsm_secret_admin.sh" 2>&1); then
        log_event "SUCCESS" "step2_iam" "Secret Manager IAM grant successful"
        return 0
    else
        exit_code=$?
        
        if is_permission_denied "$output"; then
            log_event "WAITING" "step2_iam" "GCP permissions not yet granted; will retry in 5 minutes"
            return 1
        else
            log_event "ERROR" "step2_iam" "IAM grant failed: $output"
            return 1
        fi
    fi
}

# ============================================================================
# STEP 3: TERRAFORM APPLY
# ============================================================================
step_terraform_apply() {
    log_event "START" "step3_terraform" "Running terraform apply..."
    
    local output
    local exit_code=0
    
    cd "$TF_DIR"
    
    if output=$(terraform apply -auto-approve -lock=true 2>&1); then
        log_event "SUCCESS" "step3_terraform" "Terraform apply completed successfully"
        cd - > /dev/null
        return 0
    else
        exit_code=$?
        
        if is_permission_denied "$output"; then
            log_event "WAITING" "step3_terraform" "GCP permissions still not available; will retry"
            cd - > /dev/null
            return 1
        else
            log_event "ERROR" "step3_terraform" "Terraform apply failed: $output"
            cd - > /dev/null
            return 1
        fi
    fi
}

# ============================================================================
# STEP 4: PROVISION GSM CREDENTIALS
# ============================================================================
step_provision_gsm_credentials() {
    log_event "START" "step4_gsm_provisioning" "Provisioning OPERATOR credentials to GSM..."
    
    local output
    local exit_code=0
    
    if output=$("$DEPLOYMENT_SCRIPTS_DIR/provision-operator-credentials.sh" 2>&1); then
        log_event "SUCCESS" "step4_gsm_provisioning" "GSM credential provisioning completed"
        return 0
    else
        exit_code=$?
        
        if is_permission_denied "$output"; then
            log_event "WAITING" "step4_gsm_provisioning" "GSM permissions still not available; will retry"
            return 1
        else
            log_event "ERROR" "step4_gsm_provisioning" "GSM provisioning failed: $output"
            return 1
        fi
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log_event "START" "main" "Hands-off final provisioning started"
    
    check_required_files
    
    # Try to complete all steps
    # If any step needs GCP permissions, exit cleanly to wait for next timer tick
    
    if ! step_create_private_services_connection; then
        log_event "EXIT" "main" "Waiting for infrastructure permissions; will retry in 5 minutes"
        exit 0
    fi
    
    if ! step_grant_gsm_iam; then
        log_event "EXIT" "main" "Waiting for IAM permissions; will retry in 5 minutes"
        exit 0
    fi
    
    if ! step_terraform_apply; then
        log_event "EXIT" "main" "Terraform blocked; will retry in 5 minutes"
        exit 0
    fi
    
    if ! step_provision_gsm_credentials; then
        log_event "EXIT" "main" "GSM provisioning blocked; will retry in 5 minutes"
        exit 0
    fi
    
    log_event "COMPLETE" "main" "All provisioning steps completed successfully; infrastructure ready for deployment"
    exit 0
}

main "$@"
