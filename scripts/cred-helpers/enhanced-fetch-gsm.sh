#!/usr/bin/env bash
# Enhanced GSM Credential Retrieval with Caching & OIDC
# Supports: Workload Identity Federation (WIF/OIDC)

set -euo pipefail

PROJECT_ID="${1:-}"
SECRET_NAME="${2:-}"
CACHE_TTL="${CACHE_TTL:-300}"  # 5 minutes default
CACHE_DIR="${CACHE_DIR:-.credentials-cache}"

if [ -z "$PROJECT_ID" ] || [ -z "$SECRET_NAME" ]; then
    echo "Usage: $0 <project-id> <secret-name>"
    exit 1
fi

mkdir -p "$CACHE_DIR"

get_cached_credential() {
    local cache_file="$CACHE_DIR/${PROJECT_ID}_${SECRET_NAME}"
    if [ -f "$cache_file" ]; then
        local age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null)))
        if [ "$age" -lt "$CACHE_TTL" ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

fetch_from_gsm() {
    # Try OIDC/WIF first (ephemeral)
    if [ -n "${GCP_WORKLOAD_IDENTITY_PROVIDER:-}" ] && [ -n "${GCP_SERVICE_ACCOUNT:-}" ]; then
        # Get OIDC token from GitHub Actions
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            local oidc_token=$(curl -s -H "Authorization: bearer $GITHUB_TOKEN" \
                "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r '.token')
            
            if [ -n "$oidc_token" ] && [ "$oidc_token" != "null" ]; then
                # Exchange OIDC token for GCP access token
                local access_token=$(curl -s -X POST \
                    "https://sts.googleapis.com/v1/token" \
                    -H "Content-Type: application/x-www-form-urlencoded" \
                    -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
                    -d "audience=//iam.googleapis.com/projects/${PROJECT_ID}/locations/global/workloadIdentityPools/github/providers/github" \
                    -d "requested_token_type=urn:ietf:params:oauth:token-type:access_token" \
                    -d "subject_token=${oidc_token}" \
                    -d "subject_token_type=urn:ietf:params:oauth:token-type:jwt" | jq -r '.access_token')
                
                if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
                    # Use access token to get secret from GSM
                    gcloud secrets versions access latest \
                        --secret="$SECRET_NAME" \
                        --project="$PROJECT_ID" \
                        --authorization="Bearer $access_token" 2>/dev/null
                    return
                fi
            fi
        fi
    fi
    
    # Fallback to gcloud CLI
    if command -v gcloud &>/dev/null; then
        gcloud secrets versions access latest \
            --secret="$SECRET_NAME" \
            --project="$PROJECT_ID" 2>/dev/null && return
    fi
    
    return 1
}

main() {
    # Try cache first
    if get_cached_credential; then
        return 0
    fi
    
    # Fetch fresh credential
    if credential=$(fetch_from_gsm); then
        # Cache it
        echo "$credential" > "$CACHE_DIR/${PROJECT_ID}_${SECRET_NAME}"
        chmod 600 "$CACHE_DIR/${PROJECT_ID}_${SECRET_NAME}"
        echo "$credential"
    else
        echo "❌ Failed to retrieve credential: $SECRET_NAME from $PROJECT_ID" >&2
        exit 1
    fi
}

main "$@"
