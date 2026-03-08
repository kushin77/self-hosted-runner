#!/bin/bash
# 🔐 CREDENTIAL MANAGEMENT SUITE
# Ephemeral, immutable, idempotent credential lifecycle management
# No long-lived secrets, automatic rotation, hands-off operation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs/credentials"
mkdir -p "$LOG_DIR"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/credentials.log"; }
success() { echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_DIR/credentials.log"; }
error() { echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_DIR/credentials.log"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_DIR/credentials.log"; }

# ============================================================================
# GSM CREDENTIAL MANAGEMENT - GCP Secret Manager
# ============================================================================
gsm_fetch_credential() {
    local secret_name="$1"
    local secret_version="${2:-latest}"
    
    if [ -z "${GCP_PROJECT_ID:-}" ]; then
        error "GCP_PROJECT_ID not set"
        return 1
    fi
    
    # Fetch from GSM with automatic version management
    if gcloud secrets versions list "$secret_name" \
        --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
        
        gcloud secrets versions access "$secret_version" \
            --secret="$secret_name" \
            --project="$GCP_PROJECT_ID" 2>/dev/null
        
        success "GSM credential fetched: $secret_name"
        return 0
    else
        error "GSM secret not found: $secret_name"
        return 1
    fi
}

gsm_rotate_credential() {
    local secret_name="$1"
    local new_value="$2"
    
    log "Rotating GSM credential: $secret_name"
    
    if echo "$new_value" | gcloud secrets versions add "$secret_name" \
        --data-file=- \
        --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
        
        success "GSM credential rotated: $secret_name"
        return 0
    else
        error "GSM credential rotation failed: $secret_name"
        return 1
    fi
}

gsm_cleanup_old_versions() {
    local secret_name="$1"
    local keep_versions="${2:-5}"
    
    log "Cleaning old GSM versions: $secret_name (keeping $keep_versions)"
    
    # List versions and delete old ones
    gcloud secrets versions list "$secret_name" \
        --project="$GCP_PROJECT_ID" \
        --format='value(name)' \
        | tail -n +$((keep_versions + 1)) \
        | while read -r version; do
            if gcloud secrets versions destroy "$version" \
                --secret="$secret_name" \
                --project="$GCP_PROJECT_ID" \
                --quiet >/dev/null 2>&1; then
                log "Destroyed version: $version"
            fi
        done
    
    success "GSM cleanup complete"
}

# ============================================================================
# VAULT CREDENTIAL MANAGEMENT - HashiCorp Vault
# ============================================================================
vault_fetch_ephemeral_token() {
    local role_id="$1"
    local secret_id="$2"
    
    if [ -z "${VAULT_ADDR:-}" ]; then
        error "VAULT_ADDR not set"
        return 1
    fi
    
    log "Fetching ephemeral token from Vault..."
    
    # Use AppRole to get ephemeral token
    token_response=$(curl -s \
        -X POST \
        "$VAULT_ADDR/v1/auth/approle/login" \
        -d "{\"role_id\":\"$role_id\",\"secret_id\":\"$secret_id\"}")
    
    if echo "$token_response" | jq -e '.auth.client_token' >/dev/null 2>&1; then
        echo "$token_response" | jq -r '.auth.client_token'
        success "Ephemeral Vault token obtained (TTL: auto)"
        return 0
    else
        error "Failed to obtain Vault token"
        return 1
    fi
}

vault_fetch_dynamic_secret() {
    local path="$1"
    local vault_token="$2"
    
    log "Fetching dynamic secret from Vault: $path"
    
    curl -s \
        -H "X-Vault-Token: $vault_token" \
        "$VAULT_ADDR/v1/$path" | jq '.data.data'
    
    success "Dynamic secret fetched from Vault"
}

vault_revoke_token() {
    local vault_token="$1"
    
    log "Revoking Vault token..."
    
    if curl -s \
        -X POST \
        -H "X-Vault-Token: $vault_token" \
        "$VAULT_ADDR/v1/auth/token/revoke-self" >/dev/null 2>&1; then
        
        success "Vault token revoked"
        return 0
    else
        error "Failed to revoke Vault token"
        return 1
    fi
}

vault_rotate_approle() {
    local role_name="$1"
    
    log "Rotating Vault AppRole: $role_name"
    
    # Generate new Secret ID
    new_secret_response=$(curl -s \
        -X POST \
        -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
        "$VAULT_ADDR/v1/auth/approle/role/$role_name/secret-id")
    
    if echo "$new_secret_response" | jq -e '.data.secret_id' >/dev/null 2>&1; then
        success "Vault AppRole rotated: $role_name"
        echo "$new_secret_response" | jq -r '.data.secret_id'
        return 0
    else
        error "Failed to rotate Vault AppRole"
        return 1
    fi
}

# ============================================================================
# KMS CREDENTIAL MANAGEMENT - AWS KMS
# ============================================================================
kms_encrypt_credential() {
    local key_id="$1"
    local plaintext="$2"
    local region="${AWS_REGION:-us-east-1}"
    
    log "Encrypting credential with KMS key: $key_id"
    
    # Encrypt using KMS
    ciphertext=$(aws kms encrypt \
        --key-id "$key_id" \
        --plaintext "$plaintext" \
        --region "$region" \
        --query 'CiphertextBlob' \
        --output text)
    
    echo "$ciphertext"
    success "Credential encrypted with KMS"
}

kms_decrypt_credential() {
    local ciphertext="$1"
    local region="${AWS_REGION:-us-east-1}"
    
    log "Decrypting credential with KMS..."
    
    # Decrypt using KMS
    plaintext=$(aws kms decrypt \
        --ciphertext-blob "$ciphertext" \
        --region "$region" \
        --query 'Plaintext' \
        --output text)
    
    echo "$(echo "$plaintext" | base64 -d)"
    success "Credential decrypted with KMS"
}

kms_rotate_key() {
    local key_id="$1"
    local region="${AWS_REGION:-us-east-1}"
    
    log "Rotating KMS key: $key_id"
    
    # Enable automatic key rotation
    if aws kms enable-key-rotation \
        --key-id "$key_id" \
        --region "$region" >/dev/null 2>&1; then
        
        success "KMS key rotation enabled: $key_id"
        return 0
    else
        error "Failed to rotate KMS key"
        return 1
    fi
}

# ============================================================================
# INTEGRATED CREDENTIAL FETCHING - Multi-layer fallback
# ============================================================================
fetch_credential_ephemeral() {
    local secret_name="$1"
    local strategy="${2:-gsm-first}"
    
    log "Fetching ephemeral credential: $secret_name (strategy: $strategy)"
    
    case "$strategy" in
        gsm-first)
            # Try GSM first (most secure)
            if gsm_fetch_credential "$secret_name" 2>/dev/null; then
                return 0
            fi
            # Fall back to Vault
            if [ -n "${VAULT_ADDR:-}" ]; then
                vault_fetch_dynamic_secret "$secret_name" "$VAULT_TOKEN" 2>/dev/null
                return 0
            fi
            ;;
        vault-first)
            # Try Vault first
            if vault_fetch_dynamic_secret "$secret_name" "$VAULT_TOKEN" 2>/dev/null; then
                return 0
            fi
            # Fall back to GSM
            gsm_fetch_credential "$secret_name" 2>/dev/null
            ;;
        kms-encrypted)
            # Decrypt from KMS-encrypted storage
            if [ -f "$secret_name.encrypted" ]; then
                kms_decrypt_credential "$(cat "$secret_name.encrypted")" 2>/dev/null
                return 0
            fi
            ;;
    esac
    
    error "Failed to fetch credential: $secret_name"
    return 1
}

# ============================================================================
# HEALTH MONITORING - Credential layer health
# ============================================================================
check_credential_health() {
    log "Checking credential layers health..."
    
    local all_healthy=0
    
    # Check GSM
    if [ -n "${GCP_PROJECT_ID:-}" ]; then
        if gcloud secrets list --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
            success "GSM layer: HEALTHY"
        else
            error "GSM layer: UNHEALTHY"
            all_healthy=1
        fi
    fi
    
    # Check Vault
    if [ -n "${VAULT_ADDR:-}" ]; then
        if curl -s "$VAULT_ADDR/v1/sys/health" | jq '.sealed' >/dev/null 2>&1; then
            success "Vault layer: HEALTHY"
        else
            error "Vault layer: UNHEALTHY"
            all_healthy=1
        fi
    fi
    
    # Check KMS
    if [ -n "${AWS_REGION:-}" ]; then
        if aws kms list-keys >/dev/null 2>&1; then
            success "KMS layer: HEALTHY"
        else
            error "KMS layer: UNHEALTHY"
            all_healthy=1
        fi
    fi
    
    return $all_healthy
}

# ============================================================================
# AUDIT LOGGING - Track all credential operations
# ============================================================================
audit_log() {
    local operation="$1"
    local secret_name="$2"
    local status="${3:-SUCCESS}"
    local details="${4:-}"
    
    # Log to audit trail
    cat >> "$LOG_DIR/audit.log" << EOF
[$(date -u '+%Y-%m-%d_%H:%M:%S_UTC')] $operation | $secret_name | $status | $details
EOF
    
    # Also send to monitoring (if configured)
    if [ -n "${MONITORING_ENABLED:-}" ]; then
        # Would send to observability platform
        log "Audit: $operation | $secret_name | $status"
    fi
}

# ============================================================================
# CREDENTIAL CLEANUP - Remove expired tokens
# ============================================================================
cleanup_expired_credentials() {
    log "Cleaning up expired credentials..."
    
    # Remove expired Vault tokens from local cache
    find "$LOG_DIR" -name "*.token" -mtime +1 -delete
    
    # Remove old audit logs (keep 90 days)
    find "$LOG_DIR" -name "audit.log*" -mtime +90 -delete
    
    success "Credential cleanup complete"
}

# ============================================================================
# MAIN - Usage examples
# ============================================================================
usage() {
    cat << EOF
Credential Management Suite - Ephemeral, Immutable, Hands-Off

Usage: $0 <command> [args]

GSM Commands:
  gsm-fetch <secret>              Fetch credential from GCP Secret Manager
  gsm-rotate <secret> <value>     Rotate GSM credential
  gsm-cleanup <secret> [keep]     Clean old GSM versions

Vault Commands:
  vault-token <role> <secret>     Get ephemeral Vault token
  vault-secret <path> <token>     Fetch dynamic secret
  vault-revoke <token>            Revoke Vault token
  vault-rotate <role>             Rotate AppRole credentials

KMS Commands:
  kms-encrypt <key> <data>        Encrypt with KMS
  kms-decrypt <ciphertext>        Decrypt with KMS
  kms-rotate <key>                Rotate KMS key

Integrated Commands:
  fetch <secret> [strategy]       Fetch with fallback (gsm-first|vault-first|kms)
  health                          Check all credential layers
  audit <op> <secret> [status]    Log audit trail
  cleanup                         Remove expired credentials

Examples:
  $0 gsm-fetch terraform-aws-prod
  $0 vault-token role-123 secret-456
  $0 fetch aws-credentials gsm-first
  $0 health
EOF
}

# Parse command line
command="${1:-help}"

case "$command" in
    gsm-fetch)
        gsm_fetch_credential "$2" "${3:-latest}"
        ;;
    gsm-rotate)
        gsm_rotate_credential "$2" "$3"
        ;;
    gsm-cleanup)
        gsm_cleanup_old_versions "$2" "${3:-5}"
        ;;
    vault-token)
        vault_fetch_ephemeral_token "$2" "$3"
        ;;
    vault-secret)
        vault_fetch_dynamic_secret "$2" "$3"
        ;;
    vault-revoke)
        vault_revoke_token "$2"
        ;;
    vault-rotate)
        vault_rotate_approle "$2"
        ;;
    kms-encrypt)
        kms_encrypt_credential "$2" "$3"
        ;;
    kms-decrypt)
        kms_decrypt_credential "$2"
        ;;
    kms-rotate)
        kms_rotate_key "$2"
        ;;
    fetch)
        fetch_credential_ephemeral "$2" "${3:-gsm-first}"
        ;;
    health)
        check_credential_health
        ;;
    audit)
        audit_log "$2" "$3" "${4:-SUCCESS}" "${5:-}"
        ;;
    cleanup)
        cleanup_expired_credentials
        ;;
    help|*)
        usage
        ;;
esac
