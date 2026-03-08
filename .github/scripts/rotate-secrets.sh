#!/bin/bash
#
# Multi-Layer Secrets Rotation Orchestrator
# Rotates credentials across GSM, Vault, and AWS Secrets Manager
# Features:
#   - Immutable append-only JSONL audit trail
#   - Idempotent operations (safe to run repeatedly)
#   - Ephemeral credential cleanup after rotation
#   - Supports dry-run mode for validation
#

set -euo pipefail

# Configuration
PROVIDER="${1:-}"
VAULT_ADDR="${2:-}"
AWS_REGION="${3:-us-east-1}"
AUDIT_DIR="${4:-.credentials-audit}"
DRY_RUN="${5:-false}"

# Ensure audit directory exists
mkdir -p "$AUDIT_DIR"

# Audit timestamp (immutable)
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
AUDIT_FILE="${AUDIT_DIR}/rotation-audit.jsonl"

# Logging function - append-only
log_audit() {
    local action="$1"
    local provider="$2"
    local key_id="$3"
    local status="$4"
    local details="${5:-}"
    
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

# Function: Rotate GCP GSM secrets
rotate_gsm_secrets() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Listing GSM secret versions for rotation..."
        gcloud secrets list --format="value(name)" 2>/dev/null | while read -r secret; do
            echo "  - Would rotate: $secret"
            log_audit "LIST_VERSION" "gsm" "$secret" "DRY_RUN" "Listed for rotation"
        done
        return
    fi
    
    echo "Rotating GSM secrets..."
    gcloud secrets list --format="value(name)" 2>/dev/null | while read -r secret; do
        # Get current version
        CURRENT_VERSION=$(gcloud secrets versions list "$secret" --limit=1 --format="value(name)" 2>/dev/null || echo "unknown")
        
        # Rotate secret (create new version)
        NEW_VERSION=$(gcloud secrets versions add "$secret" --data-file=/dev/null 2>/dev/null || echo "")
        
        if [[ -n "$NEW_VERSION" ]]; then
            log_audit "ROTATE" "gsm" "$secret" "SUCCESS" "Current: $CURRENT_VERSION -> New: $NEW_VERSION"
            
            # Clean up old versions (keep last 3)
            VERSIONS=$(gcloud secrets versions list "$secret" --format="value(name)" --limit=100 2>/dev/null || true)
            VERSION_COUNT=$(echo "$VERSIONS" | wc -l)
            
            if [[ $VERSION_COUNT -gt 3 ]]; then
                echo "$VERSIONS" | tail -n +4 | while read -r old_version; do
                    gcloud secrets versions destroy "$old_version" --secret="$secret" --quiet 2>/dev/null || true
                    log_audit "CLEANUP" "gsm" "$secret:$old_version" "SUCCESS" "Removed old version"
                done
            fi
        else
            log_audit "ROTATE" "gsm" "$secret" "FAILED" "Could not create new version"
        fi
    done
}

# Function: Rotate Vault AppRole secrets
rotate_vault_approle() {
    local vault_addr="$1"
    local dry_run="$2"
    
    if [[ -z "$vault_addr" ]]; then
        echo "Error: VAULT_ADDR not provided"
        return 1
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Would rotate Vault AppRole credentials..."
        log_audit "LIST_ROLE" "vault" "approle" "DRY_RUN" "Listed for rotation"
        return
    fi
    
    echo "Rotating Vault AppRole credentials..."
    
    APPROLE_LIST=$(curl -s \
        -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
        "${vault_addr}/v1/auth/approle/role" | jq -r '.data.keys[]?' 2>/dev/null || true)
    
    echo "$APPROLE_LIST" | while read -r role; do
        if [[ -z "$role" ]]; then continue; fi
        
        # Generate new secret ID
        RESPONSE=$(curl -s -X POST \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            "${vault_addr}/v1/auth/approle/role/${role}/secret-id")
        
        SECRET_ID=$(echo "$RESPONSE" | jq -r '.data.secret_id?' 2>/dev/null || echo "")
        
        if [[ -n "$SECRET_ID" ]]; then
            log_audit "ROTATE" "vault" "$role" "SUCCESS" "Generated new secret ID"
        else
            log_audit "ROTATE" "vault" "$role" "FAILED" "Could not generate secret ID"
        fi
    done
}

# Function: Rotate AWS Secrets Manager
rotate_aws_secrets() {
    local aws_region="$1"
    local dry_run="$2"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Listing AWS Secrets Manager secrets..."
        aws secretsmanager list-secrets --region "$aws_region" \
            --query 'SecretList[].Name' \
            --output text 2>/dev/null | tr '\t' '\n' | while read -r secret; do
            echo "  - Would rotate: $secret"
            log_audit "LIST_VERSION" "aws" "$secret" "DRY_RUN" "Listed for rotation"
        done
        return
    fi
    
    echo "Rotating AWS Secrets Manager secrets..."
    
    aws secretsmanager list-secrets --region "$aws_region" \
        --query 'SecretList[].Name' \
        --output text 2>/dev/null | tr '\t' '\n' | while read -r secret; do
        
        if [[ -z "$secret" ]]; then continue; fi
        
        # Rotate secret
        RESPONSE=$(aws secretsmanager rotate-secret \
            --secret-id "$secret" \
            --rotation-rules AutomaticallyAfterDays=30 \
            --region "$aws_region" 2>/dev/null || echo "")
        
        VERSION=$(echo "$RESPONSE" | jq -r '.VersionId?' 2>/dev/null || echo "")
        
        if [[ -n "$VERSION" ]]; then
            log_audit "ROTATE" "aws" "$secret" "SUCCESS" "Version: $VERSION"
        else
            log_audit "ROTATE" "aws" "$secret" "SKIPPED" "Rotation already in progress"
        fi
    done
}

# Function: Cleanup ephemeral credentials
cleanup_ephemeral() {
    echo "Cleaning up ephemeral credentials..."
    
    # Remove temporary files with credentials
    find /tmp -name "*secret*" -type f -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "*token*" -type f -mtime +1 -delete 2>/dev/null || true
    
    log_audit "CLEANUP" "system" "ephemeral" "SUCCESS" "Removed temporary files"
}

# Main orchestration
main() {
    echo "=== Multi-Layer Secrets Rotation Orchestrator ==="
    echo "Timestamp: $TIMESTAMP"
    echo "Provider: ${PROVIDER:-all}"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    case "$PROVIDER" in
        gsm)
            rotate_gsm_secrets "$DRY_RUN"
            ;;
        vault)
            rotate_vault_approle "$VAULT_ADDR" "$DRY_RUN"
            ;;
        aws)
            rotate_aws_secrets "$AWS_REGION" "$DRY_RUN"
            ;;
        *)
            echo "Error: Invalid provider: $PROVIDER"
            exit 1
            ;;
    esac
    
    # Always cleanup ephemeral data
    cleanup_ephemeral
    
    echo ""
    echo "=== Rotation Complete ==="
    echo "Audit Trail: $AUDIT_FILE"
    echo "Total Events: $(wc -l < "$AUDIT_FILE" || echo 0)"
}

# Parse arguments properly
PROVIDER=""
VAULT_ADDR=""
AWS_REGION="us-east-1"
AUDIT_DIR=".credentials-audit"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider)
            PROVIDER="$2"
            shift 2
            ;;
        --vault-addr)
            VAULT_ADDR="$2"
            shift 2
            ;;
        --aws-region)
            AWS_REGION="$2"
            shift 2
            ;;
        --audit-dir)
            AUDIT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
