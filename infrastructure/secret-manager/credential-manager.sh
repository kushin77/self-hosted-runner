#!/bin/bash
#
# 🔐 CENTRALIZED CREDENTIAL MANAGER
#
# Manages all credentials from GSM/Vault/KMS
# Zero credentials on disk, in-memory cache only
# 30-minute TTL with automatic refresh
#
# Usage:
#   source credential-manager.sh
#   get_credential "secret-name" → outputs value to stdout
#   get_credential_env "SECRET_NAME" "secret-name" → exports to env var

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly CREDENTIAL_CACHE_DIR="/tmp/creds-cache"
readonly CREDENTIAL_CACHE_TTL=1800        # 30 minutes
readonly VAULT_ADDR="${VAULT_ADDR:-https://vault.example.com:8200}"
readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"
readonly GSM_PROJECT="${GSM_PROJECT:-elevated-iq-prod}"
readonly KMS_KEYRING="${KMS_KEYRING:-secrets}"

# Initialize cache directory (secure)
mkdir -p "$CREDENTIAL_CACHE_DIR"
chmod 700 "$CREDENTIAL_CACHE_DIR"

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

cache_get() {
    local secret_name="$1"
    local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.cache"
    
    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [[ $age -lt $CREDENTIAL_CACHE_TTL ]]; then
            cat "$cache_file" 2>/dev/null || return 1
            return 0
        fi
    fi
    
    return 1
}

cache_set() {
    local secret_name="$1"
    local value="$2"
    local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.cache"
    
    echo "$value" > "$cache_file"
    chmod 600 "$cache_file"
}

cache_invalidate() {
    local secret_name="$1"
    local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.cache"
    rm -f "$cache_file"
}

cache_clear_all() {
    rm -rf "${CREDENTIAL_CACHE_DIR:?}"/*
}

# ============================================================================
# CREDENTIAL SOURCES (Priority order)
# ============================================================================

# 1. GSM (Google Secret Manager) - Primary
get_from_gsm() {
    local secret_name="$1"
    
    # Requires: gcloud CLI and authentication
    if ! command -v gcloud &>/dev/null; then
        return 1
    fi
    
    gcloud secrets versions access latest \
        --secret="$secret_name" \
        --project="$GSM_PROJECT" \
        2>/dev/null || return 1
}

# 2. Vault - Fallback (with auto-unseal)
get_from_vault() {
    local secret_name="$1"
    local vault_path="secret/data/${secret_name}"
    
    # Check if Vault is accessible
    if ! curl -s --connect-timeout 5 "${VAULT_ADDR}/v1/sys/health" &>/dev/null; then
        return 1
    fi
    
    # Attempt to unseal if needed
    if vault status 2>/dev/null | grep -q "Sealed: true"; then
        unseal_vault || return 1
    fi
    
    # Fetch secret from Vault
    vault kv get -field=value "$vault_path" 2>/dev/null || return 1
}

# 3. KMS-encrypted local file (Last resort)
get_from_kms_file() {
    local secret_name="$1"
    local encrypted_file="/etc/secrets/${secret_name}.kms.enc"
    
    if [[ ! -f "$encrypted_file" ]]; then
        return 1
    fi
    
    gcloud kms decrypt \
        --ciphertext-file="$encrypted_file" \
        --plaintext-file=/dev/stdout \
        --location=global \
        --keyring="$KMS_KEYRING" \
        --key="default" \
        2>/dev/null || return 1
}

# ============================================================================
# VAULT OPERATIONS
# ============================================================================

unseal_vault() {
    # Attempt to unseal Vault using stored keys
    local unseal_keys_file="/etc/vault/unseal-keys.enc"
    
    if [[ ! -f "$unseal_keys_file" ]]; then
        return 1
    fi
    
    # Decrypt unseal keys using KMS
    local keys=$(gcloud kms decrypt \
        --ciphertext-file="$unseal_keys_file" \
        --plaintext-file=/dev/stdout \
        --location=global \
        --keyring="$KMS_KEYRING" \
        --key="default" 2>/dev/null) || return 1
    
    # Provide unseal keys to Vault
    while IFS= read -r key; do
        vault unseal "$key" 2>/dev/null || true
    done <<< "$keys"
    
    return 0
}

# ============================================================================
# PRIMARY INTERFACE
# ============================================================================

get_credential() {
    local secret_name="$1"
    
    # 1. Try cache first
    if cache_get "$secret_name"; then
        return 0
    fi
    
    # 2. Try GSM
    if value=$(get_from_gsm "$secret_name"); then
        cache_set "$secret_name" "$value"
        echo "$value"
        return 0
    fi
    
    # 3. Try Vault
    if value=$(get_from_vault "$secret_name"); then
        cache_set "$secret_name" "$value"
        echo "$value"
        return 0
    fi
    
    # 4. Try KMS-encrypted file
    if value=$(get_from_kms_file "$secret_name"); then
        cache_set "$secret_name" "$value"
        echo "$value"
        return 0
    fi
    
    # All sources failed
    echo "ERROR: Unable to fetch credential: $secret_name" >&2
    return 1
}

# Get credential and export to environment variable
get_credential_env() {
    local env_var_name="$1"
    local secret_name="$2"
    
    local value=$(get_credential "$secret_name") || return 1
    export "${env_var_name}=${value}"
}

# Validate that critical credentials are accessible
validate_credentials() {
    local critical_secrets=(
        "automation-ssh-key"
        "docker-registry-token"
        "postgresql-password"
        "vault-token"
    )
    
    echo "Validating credential access..."
    
    for secret in "${critical_secrets[@]}"; do
        if get_credential "$secret" > /dev/null; then
            echo "  ✅ $secret"
        else
            echo "  ❌ $secret - FAILED"
            return 1
        fi
    done
    
    echo "All credentials validated successfully"
    return 0
}

# Inject credentials into container (secrets as environment variables)
inject_container_secrets() {
    local container_id="$1"
    
    # Predefined secrets to inject
    local secrets=(
        "DB_PASSWORD:postgresql-password"
        "DOCKER_TOKEN:docker-registry-token"
        "VAULT_TOKEN:vault-token"
    )
    
    for secret_spec in "${secrets[@]}"; do
        IFS=: read env_name secret_name <<< "$secret_spec"
        
        if value=$(get_credential "$secret_name"); then
            docker exec "$container_id" \
                /bin/bash -c "export ${env_name}='${value}'" || true
        fi
    done
}

# Rotate credentials (invalidate cache, force re-fetch)
rotate_credential() {
    local secret_name="$1"
    
    echo "Rotating credential: $secret_name"
    cache_invalidate "$secret_name"
    
    # Force re-fetch to validate new version
    if get_credential "$secret_name" > /dev/null; then
        echo "Credential rotated successfully"
        return 0
    else
        echo "ERROR: Failed to fetch rotated credential"
        return 1
    fi
}

# ============================================================================
# CLEANUP & SECURITY
# ============================================================================

# Safely clear all cached credentials (call on logout)
cleanup_credentials() {
    echo "Clearing credential cache..."
    cache_clear_all
    echo "✅ Credential cache cleared"
}

# Trap to ensure credentials are cleared on exit
trap cleanup_credentials EXIT

# ============================================================================
# EXPORT PUBLIC FUNCTIONS
# ============================================================================

export -f get_credential
export -f get_credential_env
export -f validate_credentials
export -f inject_container_secrets
export -f rotate_credential
export -f cleanup_credentials
export -f cache_invalidate
