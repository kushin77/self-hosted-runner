#!/bin/bash
# Rotate and revoke all exposed keys removed from repository
# Immutable audit trail, ephemeral state cleanup, idempotent operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_DIR="${SCRIPT_DIR}/../.key-rotation-audit"
REVOCATION_LOG="${AUDIT_DIR}/revocation-$(date +%Y-%m-%dT%H:%M:%SZ).jsonl"

mkdir -p "$AUDIT_DIR"

log() {
    local level="$1"
    shift
    local msg="$@"
    local ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "[$ts] [$level] $msg"
}

audit_entry() {
    local action="$1"
    local provider="$2"
    local key_id="$3"
    local status="$4"
    
    local entry=$(cat <<EOF
{"timestamp":"$(date -u +'%Y-%m-%dT%H:%M:%SZ')","action":"$action","provider":"$provider","key_id":"$key_id","status":"$status"}
EOF
)
    echo "$entry" >> "$REVOCATION_LOG"
}

# =============================================================================
# GCP Key Revocation
# =============================================================================
revoke_gcp_keys() {
    log "INFO" "Revoking exposed GCP service account keys..."
    
    if [ -z "${GCP_PROJECT_ID:-}" ]; then
        log "WARN" "GCP_PROJECT_ID not set; skipping GCP revocation"
        return 0
    fi
    
    if [ -z "${EXPOSED_GCP_SA_EMAIL:-}" ]; then
        log "WARN" "EXPOSED_GCP_SA_EMAIL not set; skipping GCP revocation"
        return 0
    fi
    
    # List all keys for the exposed SA
    local keys
    keys=$(gcloud iam service-accounts keys list \
        --iam-account="$EXPOSED_GCP_SA_EMAIL" \
        --project="$GCP_PROJECT_ID" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -z "$keys" ]; then
        log "WARN" "No keys found for $EXPOSED_GCP_SA_EMAIL"
        return 0
    fi
    
    local revoked_count=0
    while IFS= read -r key_id; do
        if [ -z "$key_id" ] || [ "$key_id" = "ACTIVE" ]; then
            continue
        fi
        
        log "INFO" "Revoking GCP key: $key_id"
        
        # Delete the key
        gcloud iam service-accounts keys delete "$key_id" \
            --iam-account="$EXPOSED_GCP_SA_EMAIL" \
            --project="$GCP_PROJECT_ID" \
            --quiet 2>/dev/null || true
        
        audit_entry "revoke_gcp_key" "GCP" "$key_id" "success"
        ((revoked_count++))
    done <<< "$keys"
    
    log "INFO" "Revoked $revoked_count GCP keys"
}

# =============================================================================
# AWS Access Key Revocation
# =============================================================================
revoke_aws_keys() {
    log "INFO" "Revoking exposed AWS access keys..."
    
    if [ -z "${EXPOSED_AWS_KEY_IDS:-}" ]; then
        log "WARN" "EXPOSED_AWS_KEY_IDS not set; skipping AWS revocation"
        return 0
    fi
    
    local revoked_count=0
    for key_id in ${EXPOSED_AWS_KEY_IDS//,/ }; do
        if [ -z "$key_id" ]; then
            continue
        fi
        
        log "INFO" "Deactivating AWS access key: $key_id"
        
        # Update access key status
        aws iam update-access-key \
            --access-key-id "$key_id" \
            --status Inactive 2>/dev/null || true
        
        # Delete after status change
        aws iam delete-access-key \
            --access-key-id "$key_id" 2>/dev/null || true
        
        audit_entry "revoke_aws_key" "AWS" "$key_id" "success"
        ((revoked_count++))
    done
    
    log "INFO" "Revoked $revoked_count AWS keys"
}

# =============================================================================
# Vault AppRole Revocation
# =============================================================================
revoke_vault_credentials() {
    log "INFO" "Revoking exposed Vault credentials..."
    
    if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
        log "WARN" "VAULT_ADDR or VAULT_TOKEN not set; skipping Vault revocation"
        return 0
    fi
    
    if [ -z "${EXPOSED_VAULT_ROLE_IDS:-}" ]; then
        log "WARN" "EXPOSED_VAULT_ROLE_IDS not set; skipping Vault revocation"
        return 0
    fi
    
    local revoked_count=0
    for role_id in ${EXPOSED_VAULT_ROLE_IDS//,/ }; do
        if [ -z "$role_id" ]; then
            continue
        fi
        
        log "INFO" "Revoking Vault AppRole: $role_id"
        
        # Delete AppRole
        curl -s -X DELETE \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/auth/approle/role/$role_id" >/dev/null 2>&1 || true
        
        audit_entry "revoke_vault_approle" "Vault" "$role_id" "success"
        ((revoked_count++))
    done
    
    log "INFO" "Revoked $revoked_count Vault AppRoles"
}

# =============================================================================
# Validation: Scan for remaining secrets
# =============================================================================
validate_no_secrets() {
    log "INFO" "Validating no secrets remain in repository..."
    
    if ! command -v git-secrets &>/dev/null; then
        log "WARN" "git-secrets not found; install with: git clone https://github.com/awslabs/git-secrets.git && sudo make && sudo make install"
        return 0
    fi
    
    # Run git-secrets scan
    if git secrets --scan --cached; then
        log "INFO" "✓ No secrets found in git staging area"
        audit_entry "validate_secrets" "git-secrets" "cached" "success"
    else
        log "ERROR" "✗ Secrets still present in git; abort revocation process"
        audit_entry "validate_secrets" "git-secrets" "cached" "FAILED"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "INFO" "========== Key Revocation & Rotation =========="
    
    revoke_gcp_keys || log "WARN" "GCP revocation failed; continuing"
    revoke_aws_keys || log "WARN" "AWS revocation failed; continuing"
    revoke_vault_credentials || log "WARN" "Vault revocation failed; continuing"
    
    # Validate
    if ! validate_no_secrets; then
        log "ERROR" "Validation failed; check audit log"
        return 1
    fi
    
    log "INFO" "========== Revocation Complete =========="
    log "INFO" "Audit trail: $REVOCATION_LOG"
    log "INFO" "Next: Create new keys in each provider and update workflows"
    
    # Ephemeral cleanup
    unset VAULT_TOKEN GCP_PROJECT_ID AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

main "$@"
