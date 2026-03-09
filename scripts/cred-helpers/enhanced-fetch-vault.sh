#!/usr/bin/env bash
# Enhanced Vault Credential Retrieval with OIDC & AppRole
# Supports: JWT (OIDC), AppRole, fallback to static token

set -euo pipefail

SECRET_PATH="${1:-}"
CACHE_TTL="${CACHE_TTL:-300}"
CACHE_DIR="${CACHE_DIR:-.credentials-cache}"

if [ -z "$SECRET_PATH" ]; then
    echo "Usage: $0 <secret-path>"
    exit 1
fi

if [ -z "${VAULT_ADDR:-}" ]; then
    echo "❌ VAULT_ADDR not set" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR"

get_cached_credential() {
    local cache_file="$CACHE_DIR/vault_$(echo "$SECRET_PATH" | md5sum | cut -d' ' -f1)"
    if [ -f "$cache_file" ]; then
        local age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null)))
        if [ "$age" -lt "$CACHE_TTL" ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

get_vault_token() {
    local token=""
    
    # Try OIDC/JWT first (ephemeral)
    if [ -n "${VAULT_ROLE:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
        local jwt_token=$(curl -s -H "Authorization: bearer $GITHUB_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r '.token' 2>/dev/null) || true
        
        if [ -n "$jwt_token" ] && [ "$jwt_token" != "null" ]; then
            token=$(curl -s -X POST \
                "${VAULT_ADDR}/v1/auth/jwt/login" \
                -d "{\"role\": \"${VAULT_ROLE}\", \"jwt\": \"${jwt_token}\"}" | jq -r '.auth.client_token' 2>/dev/null) || true
            
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi
    
    # Try AppRole (if configured)
    if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
        token=$(curl -s -X POST \
            "${VAULT_ADDR}/v1/auth/approle/login" \
            -d "{\"role_id\": \"${VAULT_ROLE_ID}\", \"secret_id\": \"${VAULT_SECRET_ID}\"}" | jq -r '.auth.client_token' 2>/dev/null) || true
        
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi
    
    # Fallback to static token (for emergency only)
    if [ -n "${VAULT_TOKEN:-}" ]; then
        echo "${VAULT_TOKEN}"
        return 0
    fi
    
    return 1
}

fetch_secret() {
    local token="$1"
    curl -s -H "X-Vault-Token: $token" \
        "${VAULT_ADDR}/v1/${SECRET_PATH}" | jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"'
}

main() {
    # Try cache first
    if get_cached_credential; then
        return 0
    fi
    
    # Get token
    if token=$(get_vault_token); then
        # Fetch secret
        if credential=$(fetch_secret "$token"); then
            # Cache it
            echo "$credential" > "$CACHE_DIR/vault_$(echo "$SECRET_PATH" | md5sum | cut -d' ' -f1)"
            chmod 600 "$CACHE_DIR/vault_$(echo "$SECRET_PATH" | md5sum | cut -d' ' -f1)"
            echo "$credential"
        else
            echo "❌ Failed to fetch secret: $SECRET_PATH" >&2
            exit 1
        fi
    else
        echo "❌ Failed to authenticate to Vault" >&2
        exit 1
    fi
}

main "$@"
