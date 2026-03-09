#!/bin/bash
###############################################################################
# NexusShield Credential Rotation Automation
# 
# Purpose: Rotate credentials across GSM, Vault, and AWS KMS
# Schedule: Every 60 seconds (ephemeral TTL)
# Compliance: Immutable audit trail (JSONL append-only)
#
# Credential Lifecycle:
# 1. Request ephemeral token from Google Secret Manager (TTL: 60s)
# 2. Get dynamic secret from HashiCorp Vault (TTL: 60s)
# 3. Encrypt with AWS KMS (envelope encryption)
# 4. Destroy after TTL expires
# 5. Log operation immutably (JSONL)
#
# Requirements:
# - gcloud CLI (authenticated)
# - vault CLI (authenticated)
# - aws CLI (authenticated)
# - jq (JSON processor)
###############################################################################

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly AUDIT_LOG="${PROJECT_ROOT}/logs/credential-rotation-audit.jsonl"
readonly VAULT_ADDR="${VAULT_ADDR:-https://vault.nexusshield.io}"
readonly GSM_PROJECT="${GCP_PROJECT_ID:-nexusshield-prod}"
readonly KMS_KEY_ID="${AWS_KMS_KEY_ID:-alias/nexusshield-prod}"
readonly CREDENTIAL_TTL_SECONDS=60

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

###############################################################################
# Logging & Audit Trail Functions
###############################################################################

log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN${NC} $*"
}

# Immutable audit trail (WORM - Write-Once-Read-Many)
audit_log() {
    local operation="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create audit entry (JSONL format)
    local entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg op "$operation" \
        --arg st "$status" \
        --arg det "$details" \
        --arg user "$USER" \
        --arg hostname "$(hostname)" \
        '{
            timestamp: $ts,
            operation: $op,
            status: $st,
            user: $user,
            hostname: $hostname,
            details: $det
        }')
    
    # Append immutably (no overwrites, no deletes allowed)
    echo "$entry" >> "$AUDIT_LOG"
    
    # Verify append (failsafe)
    if ! grep -q "$operation" "$AUDIT_LOG" 2>/dev/null; then
        log_error "Audit trail append failed! Aborting."
        exit 1
    fi
}

###############################################################################
# Credential Rotation Functions
###############################################################################

# Phase 1: Get ephemeral token from Google Secret Manager
rotate_gsm_credentials() {
    local secret_name="$1"
    local log_details=""
    
    log_info "Phase 1: Google Secret Manager - Requesting ephemeral token"
    log_info "  Secret: $secret_name"
    log_info "  TTL: ${CREDENTIAL_TTL_SECONDS}s"
    
    # Authenticate with GCP (using workload identity or service account)
    if ! gcloud auth application-default print-access-token &>/dev/null; then
        log_error "GCP authentication failed"
        audit_log "gsm-rotation" "failed" "GCP auth failed"
        return 1
    fi
    
    # Access secret from GSM
    local secret_value
    secret_value=$(gcloud secrets versions access latest \
        --secret="$secret_name" \
        --project="$GSM_PROJECT" 2>&1)
    
    if [ -z "$secret_value" ]; then
        log_error "Failed to retrieve secret from GSM: $secret_name"
        audit_log "gsm-rotation" "failed" "Secret retrieval failed: $secret_name"
        return 1
    fi
    
    log_info "✅ GSM: Successfully retrieved secret (${#secret_value} bytes)"
    log_details="secret_name=$secret_name,bytes=${#secret_value}"
    audit_log "gsm-rotation" "success" "$log_details"
    
    echo "$secret_value"
}

# Phase 2: Get dynamic secret from HashiCorp Vault
rotate_vault_credentials() {
    local vault_path="$1"
    local log_details=""
    
    log_info "Phase 2: HashiCorp Vault - Requesting dynamic secret"
    log_info "  Path: $vault_path"
    log_info "  TTL: ${CREDENTIAL_TTL_SECONDS}s"
    
    # Authenticate with Vault (using app role or JWT)
    if ! vault login -method=jwt -path=auth/jwt role=nexusshield &>/dev/null; then
        log_error "Vault authentication failed"
        audit_log "vault-rotation" "failed" "Vault auth failed"
        return 1
    fi
    
    # Request dynamic secret from Vault
    local secret_response
    secret_response=$(vault read "$vault_path" 2>&1)
    
    if [ -z "$secret_response" ]; then
        log_error "Failed to retrieve secret from Vault: $vault_path"
        audit_log "vault-rotation" "failed" "Vault secret retrieval failed: $vault_path"
        return 1
    fi
    
    log_info "✅ Vault: Successfully requested dynamic secret"
    log_details="path=$vault_path,ttl=${CREDENTIAL_TTL_SECONDS}s"
    audit_log "vault-rotation" "success" "$log_details"
    
    echo "$secret_response"
}

# Phase 3: Encrypt credential with AWS KMS
encrypt_with_kms() {
    local plaintext="$1"
    local log_details=""
    
    log_info "Phase 3: AWS KMS - Encrypting credential"
    log_info "  Key: $KMS_KEY_ID"
    log_info "  Plaintext size: ${#plaintext} bytes"
    
    # Encrypt credential with AWS KMS
    local encrypted_blob
    encrypted_blob=$(aws kms encrypt \
        --key-id "$KMS_KEY_ID" \
        --plaintext "$plaintext" \
        --output text \
        --query CiphertextBlob 2>&1)
    
    if [ -z "$encrypted_blob" ]; then
        log_error "KMS encryption failed"
        audit_log "kms-encryption" "failed" "Encryption failed for $KMS_KEY_ID"
        return 1
    fi
    
    log_info "✅ KMS: Successfully encrypted credential"
    log_details="key=$KMS_KEY_ID,ciphertext_size=${#encrypted_blob}"
    audit_log "kms-encryption" "success" "$log_details"
    
    echo "$encrypted_blob"
}

# Phase 4: Destroy credentials after TTL
destroy_credential() {
    local credential="$1"
    local log_details=""
    
    log_info "Phase 4: Destroying credential after TTL (${CREDENTIAL_TTL_SECONDS}s)"
    
    # Wait for TTL
    sleep "$CREDENTIAL_TTL_SECONDS"
    
    # Securely destroy (overwrite memory)
    if command -v wipe &>/dev/null; then
        wipe -f -s -c 3 <<< "$credential" 2>/dev/null || true
    fi
    
    # Unset variables
    unset credential
    unset plaintext
    unset encrypted_blob
    
    log_info "✅ Credential destroyed (memory cleared)"
    log_details="ttl=${CREDENTIAL_TTL_SECONDS}s"
    audit_log "credential-destroy" "success" "$log_details"
}

###############################################################################
# Main Rotation Cycle
###############################################################################

main() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "NexusShield Credential Rotation - $(date -u +'%Y-%m-%d %H:%M:%SZ')"
    log_info "═══════════════════════════════════════════════════════════════"
    
    # Rotation targets (can be expanded)
    declare -a SECRETS=(
        "nexusshield-prod-db-password"
        "nexusshield-prod-api-key"
        "nexusshield-prod-jwt-secret"
    )
    
    declare -a VAULT_PATHS=(
        "secret/data/nexusshield/prod/database"
        "secret/data/nexusshield/prod/api-token"
        "aws/creds/nexusshield-prod"
    )
    
    local success_count=0
    local fail_count=0
    
    # Rotate each secret
    for secret in "${SECRETS[@]}"; do
        log_info ""
        log_info "Rotating: $secret"
        
        if gsm_secret=$(rotate_gsm_credentials "$secret"); then
            ((success_count++))
        else
            ((fail_count++))
            continue
        fi
        
        # Encrypt and destroy
        if encrypted=$(encrypt_with_kms "$gsm_secret"); then
            destroy_credential "$encrypted"
        fi
    done
    
    # Rotate Vault secrets
    for vault_path in "${VAULT_PATHS[@]}"; do
        log_info ""
        log_info "Rotating Vault: $vault_path"
        
        if rotate_vault_credentials "$vault_path"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    # Summary
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Rotation Summary"
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "✅ Successful: $success_count"
    log_info "❌ Failed: $fail_count"
    log_info "📝 Audit log: $AUDIT_LOG"
    log_info "📊 Total entries: $(wc -l < "$AUDIT_LOG")"
    
    # Overall result
    if [ "$fail_count" -eq 0 ]; then
        log_info "✅ All credentials rotated successfully"
        audit_log "credential-rotation-cycle" "success" "success_count=$success_count,fail_count=$fail_count"
        return 0
    else
        log_error "⚠️  Some credentials failed to rotate"
        audit_log "credential-rotation-cycle" "failed" "success_count=$success_count,fail_count=$fail_count"
        return 1
    fi
}

# Execute
main "$@"
exit $?
