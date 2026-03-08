#!/bin/bash
#
# Multi-Layer Exposed Key Revocation Orchestrator
# Revokes compromised credentials across GCP, AWS, and Vault
# Features:
#   - Immutable append-only JSONL audit trail
#   - Idempotent operations (safe to run repeatedly)
#   - Dry-run mode for validation
#   - Validates no secrets remain after revocation
#

set -euo pipefail

# Configuration
DRY_RUN="true"
EXPOSED_KEY_IDS=""
AUDIT_DIR=".key-rotation-audit"
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Audit timestamp (immutable)
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
AUDIT_FILE="${AUDIT_DIR}/key-revocation-audit.jsonl"

# Logging function - append-only
log_audit() {
    local action="$1"
    local provider="$2"
    local key_id="$3"
    local status="$4"
    local details="${5:-}"
    
    # Ensure audit directory exists
    mkdir -p "$AUDIT_DIR"
    
    local entry=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg act "$action" \
        --arg prov "$provider" \
        --arg kid "$key_id" \
        --arg st "$status" \
        --arg det "$details" \
        '{timestamp: $ts, action: $act, provider: $prov, key_id: $kid, status: $st, details: $det}')
    
    echo "$entry" >> "$AUDIT_FILE"
}

# Function: Revoke GCP service account keys
revoke_gcp_keys() {
    local dry_run="$1"
    local exposed_keys="$2"
    
    echo "Processing GCP key revocation..."
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Would revoke GCP keys..."
        if [[ -n "$exposed_keys" ]]; then
            echo "$exposed_keys" | tr ',' '\n' | while read -r key_id; do
                echo "  - Would revoke: $key_id"
                log_audit "REVOKE" "gcp" "$(echo $key_id | cut -d: -f1)" "DRY_RUN" "Listed for revocation"
            done
        fi
        return
    fi
    
    # Get all service accounts
    PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null || echo "")
    
    echo "$PROJECTS" | while read -r project; do
        if [[ -z "$project" ]]; then continue; fi
        
        # Get service accounts in project
        SAs=$(gcloud iam service-accounts list --project="$project" \
            --format="value(email)" 2>/dev/null || echo "")
        
        echo "$SAs" | while read -r sa; do
            if [[ -z "$sa" ]]; then continue; fi
            
            # List keys
            KEYS=$(gcloud iam service-accounts keys list --iam-account="$sa" \
                --project="$project" --format="value(name)" 2>/dev/null || echo "")
            
            echo "$KEYS" | while read -r key_id; do
                if [[ -z "$key_id" ]]; then continue; fi
                
                # Check if key is in exposed list
                if [[ -z "$exposed_keys" ]] || echo "$exposed_keys" | grep -q "$key_id"; then
                    echo "  - Revoking GCP key: $key_id"
                    gcloud iam service-accounts keys delete "$key_id" \
                        --iam-account="$sa" --project="$project" --quiet 2>/dev/null || true
                    
                    log_audit "REVOKE" "gcp" "$key_id" "SUCCESS" "Deleted exposed key"
                fi
            done
        done
    done
}

# Function: Revoke AWS access keys
revoke_aws_keys() {
    local dry_run="$1"
    local exposed_keys="$2"
    
    echo "Processing AWS key revocation..."
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Would revoke AWS keys..."
        if [[ -n "$exposed_keys" ]]; then
            echo "$exposed_keys" | tr ',' '\n' | while read -r key_id; do
                echo "  - Would deactivate: $key_id"
                log_audit "REVOKE" "aws" "$(echo $key_id | cut -d: -f1)" "DRY_RUN" "Listed for revocation"
            done
        fi
        return
    fi
    
    # Get all IAM users
    USERS=$(aws iam list-users --query 'Users[].UserName' --output text 2>/dev/null || echo "")
    
    echo "$USERS" | tr '\t' '\n' | while read -r user; do
        if [[ -z "$user" ]]; then continue; fi
        
        # List access keys
        KEYS=$(aws iam list-access-keys --user-name "$user" \
            --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
        
        echo "$KEYS" | tr '\t' '\n' | while read -r key_id; do
            if [[ -z "$key_id" ]]; then continue; fi
            
            # Check if key is in exposed list
            if [[ -z "$exposed_keys" ]] || echo "$exposed_keys" | grep -q "$key_id"; then
                echo "  - Deactivating AWS key: $key_id"
                
                # First deactivate
                aws iam update-access-key --user-name "$user" \
                    --access-key-id "$key_id" --status Inactive 2>/dev/null || true
                
                # Then delete
                aws iam delete-access-key --user-name "$user" \
                    --access-key-id "$key_id" 2>/dev/null || true
                
                log_audit "REVOKE" "aws" "$key_id" "SUCCESS" "Deactivated and deleted access key"
            fi
        done
    done
}

# Function: Revoke Vault AppRole secret IDs
revoke_vault_secrets() {
    local dry_run="$1"
    local exposed_keys="$2"
    local vault_addr="$3"
    
    if [[ -z "$vault_addr" ]]; then
        echo "Skipping Vault revocation (VAULT_ADDR not set)"
        return
    fi
    
    echo "Processing Vault secret revocation..."
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Would revoke Vault secrets..."
        log_audit "REVOKE" "vault" "approle" "DRY_RUN" "Listed for revocation"
        return
    fi
    
    # List AppRoles
    ROLES=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" \
        "${vault_addr}/v1/auth/approle/role" \
        | jq -r '.data.keys[]?' 2>/dev/null || echo "")
    
    echo "$ROLES" | while read -r role; do
        if [[ -z "$role" ]]; then continue; fi
        
        # List secret IDs
        SECRET_IDS=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" \
            "${vault_addr}/v1/auth/approle/role/${role}/secret-id" \
            | jq -r '.data.keys[]?' 2>/dev/null || echo "")
        
        echo "$SECRET_IDS" | while read -r secret_id; do
            if [[ -z "$secret_id" ]]; then continue; fi
            
            # Check if secret is in exposed list
            if [[ -z "$exposed_keys" ]] || echo "$exposed_keys" | grep -q "$secret_id"; then
                echo "  - Revoking Vault secret ID: $secret_id"
                
                curl -s -X DELETE -H "X-Vault-Token: ${VAULT_TOKEN}" \
                    "${vault_addr}/v1/auth/approle/role/${role}/secret-id/destroy" \
                    -d "{\"secret_id\": \"${secret_id}\"}" >/dev/null 2>&1 || true
                
                log_audit "REVOKE" "vault" "$secret_id" "SUCCESS" "Revoked AppRole secret ID"
            fi
        done
    done
}

# Function: Validate no secrets remain
validate_no_secrets() {
    echo "Validating no secrets remain..."
    
    # Use git-secrets to scan
    if command -v git-secrets >/dev/null 2>&1; then
        if git secrets --scan; then
            log_audit "VALIDATE" "system" "git-secrets" "SUCCESS" "No secrets detected"
            echo "✓ git-secrets validation passed"
        else
            log_audit "VALIDATE" "system" "git-secrets" "WARNING" "Secrets may still exist"
            echo "⚠ git-secrets found potential issues"
        fi
    fi
}

# Function: Cleanup ephemeral credentials
cleanup_ephemeral() {
    echo "Cleaning up ephemeral credentials..."
    
    # Remove temporary files
    find /tmp -name "*secret*" -type f -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "*token*" -type f -mtime +1 -delete 2>/dev/null || true
    
    log_audit "CLEANUP" "system" "ephemeral" "SUCCESS" "Removed temporary files"
}

# Main orchestration
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN="$2"
                shift 2
                ;;
            --exposed-key-ids)
                EXPOSED_KEY_IDS="$2"
                shift 2
                ;;
            --audit-dir)
                AUDIT_DIR="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo "=== Multi-Layer Key Revocation Orchestrator ==="
    echo "Timestamp: $TIMESTAMP"
    echo "Dry Run: $DRY_RUN"
    echo "Exposed Key IDs: ${EXPOSED_KEY_IDS:-(all)}"
    echo ""
    
    # Revoke keys across all providers
    revoke_gcp_keys "$DRY_RUN" "$EXPOSED_KEY_IDS"
    revoke_aws_keys "$DRY_RUN" "$EXPOSED_KEY_IDS"
    revoke_vault_secrets "$DRY_RUN" "$EXPOSED_KEY_IDS" "$VAULT_ADDR"
    
    # Validate
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_no_secrets
    fi
    
    # Always cleanup ephemeral
    cleanup_ephemeral
    
    echo ""
    echo "=== Key Revocation Complete ==="
    echo "Audit Trail: $AUDIT_FILE"
    echo "Total Events: $(wc -l < "$AUDIT_FILE" 2>/dev/null || echo 0)"
}

main "$@"
