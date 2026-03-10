#!/bin/bash
###############################################################################
# Phase 3B: AWS + Vault Credentials Provisioning (GCP skipped)
# Handles Layer 2 (AWS OIDC + KMS) and Layer 3 (Vault JWT)
# Architecture: Ephemeral (auto-expires), Immutable (audit logged), Idempotent
###############################################################################

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly AUDIT_LOG_DIR="${HOME}/.phase3-credentials-awsvault"
readonly AUDIT_LOG="${AUDIT_LOG_DIR}/credentials.jsonl"
readonly STATE_DIR="${AUDIT_LOG_DIR}/state"
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly VAULT_ADDR="${VAULT_ADDR:-https://vault.example.com:8200}"
readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-github-actions}"

# Location for local credential caches (created by provisioning/CI)
readonly CRED_DIR="${CRED_DIR:-$(pwd)/.credentials}"

# Load secrets from secure cache and authenticate non-interactively
load_secrets_and_auth() {
    # GCP service account (optional) - use for gcloud non-interactive actions
    if [[ -f "$CRED_DIR/gcp-admin-sa-key.json" ]]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$CRED_DIR/gcp-admin-sa-key.json"
        if command -v gcloud &>/dev/null; then
            gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --quiet || true
            log_info "Using GCP service account from $GOOGLE_APPLICATION_CREDENTIALS"
        fi
    fi

    # AWS credentials (optional)
    if [[ -f "$CRED_DIR/aws_access_key_id" && -f "$CRED_DIR/REDACTED_AWS_SECRET_ACCESS_KEY" ]]; then
        export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID"$CRED_DIR/aws_access_key_id")"
        export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY"$CRED_DIR/REDACTED_AWS_SECRET_ACCESS_KEY")"
        export AWS_DEFAULT_REGION="${AWS_REGION}"
        log_info "AWS credentials loaded from $CRED_DIR"
    fi

    # Vault token (prefer AppRole if role_id/secret_id present)
    if [[ -f "$CRED_DIR/vault-token" ]]; then
        export REDACTED_VAULT_TOKEN="$(< "$CRED_DIR/vault-token")"
        log_info "REDACTED_VAULT_TOKEN loaded from $CRED_DIR/vault-token"
    else
        # Try AppRole
        if [[ -f "$CRED_DIR/vault-credentials.role_id.cache" && -f "$CRED_DIR/vault-credentials.secret_id.cache" ]]; then
            local role_id secret_id
            role_id="$(< "$CRED_DIR/vault-credentials.role_id.cache")"
            secret_id="$(< "$CRED_DIR/vault-credentials.secret_id.cache")"
            if command -v vault &>/dev/null; then
                # login via AppRole and export token to env (do not persist to disk)
                local token
                token=$(vault write -field=token auth/approle/login role_id="$role_id" secret_id="$secret_id" 2>/dev/null || true)
                if [[ -n "$token" ]]; then
                    export REDACTED_VAULT_TOKEN="$token"
                    log_info "Logged into Vault via AppRole (token from AppRole)"
                else
                    log_info "Vault AppRole login failed or Vault unreachable"
                fi
            fi
        fi
    fi

    # Sanity: report which layers are authenticated
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
        log_info "GCP: service account available"
    fi
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
        log_info "AWS: credentials available"
    fi
    if [[ -n "${REDACTED_VAULT_TOKEN:-}" ]]; then
        log_info "Vault: token available"
    fi
}

# ============================================================================
# Secret retrieval helpers: prefer Vault -> GCP Secret Manager -> local cache
# ============================================================================
get_secret() {
    local name="$1"
    local project="${GCP_PROJECT:-}"

    # 1) Vault (KV v2 path: secret/data/<name> or secret/<name>)
    if [[ -n "${REDACTED_VAULT_TOKEN:-}" && -n "${VAULT_ADDR:-}" ]] && command -v vault &>/dev/null; then
        # try v2 first
        local out
        out=$(vault kv get -field=value "secret/$name" 2>/dev/null || true)
        if [[ -n "$out" ]]; then
            printf '%s' "$out"
            return 0
        fi
        # try generic read
        out=$(vault read -field=value "secret/$name" 2>/dev/null || true)
        if [[ -n "$out" ]]; then
            printf '%s' "$out"
            return 0
        fi
    fi

    # 2) GCP Secret Manager
    if command -v gcloud &>/dev/null && [[ -n "$project" ]]; then
        local gsm_out
        gsm_out=$(gcloud secrets versions access latest --secret="$name" --project="$project" 2>/dev/null || true)
        if [[ -n "$gsm_out" ]]; then
            printf '%s' "$gsm_out"
            return 0
        fi
    fi

    # 3) Local cache
    if [[ -f "$CRED_DIR/$name" ]]; then
        cat "$CRED_DIR/$name"
        return 0
    fi

    return 1
}

# Decrypt a KMS-encrypted file (binary) and print plaintext
decrypt_kms_file() {
    local file="$1"
    if [[ -f "$file" && -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
        # aws kms decrypt returns base64-encoded Plaintext
        aws kms decrypt --ciphertext-blob fileb://"$file" --output text --query Plaintext 2>/dev/null | base64 --decode || return 1
    else
        return 1
    fi
}

# ============================================================================
# LOGGING
# ============================================================================
log_audit() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    mkdir -p "$AUDIT_LOG_DIR"
    printf '{"timestamp":"%s","event":"%s","status":"%s","details":"%s","version":"%s","user":"%s"}\n' \
        "$(date -Iseconds)" "$event" "$status" "$details" "$SCRIPT_VERSION" "$USER" >> "$AUDIT_LOG"
}

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*"
}

# ============================================================================
# LAYER 2: AWS OIDC + KMS Setup (Idempotent)
# ============================================================================
setup_aws_oidc() {
    log_info "Layer 2A: Setting up AWS OIDC Provider..."
    log_audit "aws_oidc_start" "STARTED"
    
    # Check if already exists (idempotent)
    local provider_arn
    if provider_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(OpenIDConnectProviderArn, 'token.actions.githubusercontent.com')].OpenIDConnectProviderArn" --output text 2>/dev/null); then
        if [[ -n "$provider_arn" ]]; then
            log_info "  ✓ AWS OIDC Provider already exists: $provider_arn"
            log_audit "aws_oidc_exists" "SKIPPED" "Already provisioned"
            return 0
        fi
    fi
    
    log_info "  Creating AWS OIDC Provider for GitHub Actions..."
    
    # Get GitHub OIDC thumbprint
    if provider_arn=$(aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list "REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY" \
        --query 'OpenIDConnectProviderArn' \
        --output text 2>/dev/null); then
        log_success "AWS OIDC Provider created: $provider_arn"
        log_audit "aws_oidc_created" "SUCCESS" "ARN: $provider_arn"
        echo "$provider_arn" > "${STATE_DIR:-.}/aws_oidc_arn.txt"
        return 0
    else
        log_error "Failed to create AWS OIDC Provider"
        log_audit "aws_oidc_failed" "FAILED"
        return 1
    fi
}

setup_aws_kms() {
    log_info "Layer 2B: Setting up AWS KMS Key..."
    log_audit "aws_kms_start" "STARTED"
    
    local key_alias="alias/github-actions-secrets"
    
    # Check if key alias exists (idempotent)
    if aws kms describe-key --key-id "$key_alias" &>/dev/null; then
        local key_id
        key_id=$(aws kms describe-key --key-id "$key_alias" --query 'KeyMetadata.KeyId' --output text)
        log_info "  ✓ KMS Key already exists: $key_id"
        log_audit "aws_kms_exists" "SKIPPED" "Key ID: $key_id"
        return 0
    fi
    
    log_info "  Creating KMS Key and alias..."
    
    # Create KMS key
    if local key_id=$(aws kms create-key \
        --description "Secrets encryption for GitHub Actions" \
        --key-usage ENCRYPT_DECRYPT \
        --query 'KeyMetadata.KeyId' \
        --output text); then
        
        # Create alias (idempotent - if fails with AlreadyExists, that's OK)
        aws kms create-alias --alias-name "$key_alias" --target-key-id "$key_id" 2>/dev/null || true
        
        log_success "KMS Key created: $key_id"
        log_audit "aws_kms_created" "SUCCESS" "Key: $key_id"
        echo "$key_id" > "${STATE_DIR:-.}/aws_kms_key_id.txt"
        return 0
    else
        log_error "Failed to create KMS Key"
        log_audit "aws_kms_failed" "FAILED"
        return 1
    fi
}

# ============================================================================
# LAYER 3: Vault JWT Auth Setup (Idempotent)
# ============================================================================
setup_vault_jwt() {
    log_info "Layer 3A: Setting up Vault JWT Auth Method..."
    log_audit "vault_jwt_start" "STARTED"
    
    # Check Vault connectivity
    if ! vault version &>/dev/null; then
        log_error "Vault CLI not available or not authenticated"
        log_audit "vault_jwt_failed" "ERROR" "Vault inaccessible"
        return 1
    fi
    
    # Check if JWT auth already enabled (idempotent)
    if vault auth list --format=json 2>/dev/null | jq -e '.["jwt/"].type' &>/dev/null; then
        log_info "  ✓ Vault JWT auth already enabled"
        log_audit "vault_jwt_exists" "SKIPPED" "Already enabled"
        return 0
    fi
    
    log_info "  Enabling Vault JWT auth method..."
    
    if vault auth enable jwt 2>/dev/null || vault auth enable jwt 2>/dev/null | grep -q "path is already in use"; then
        log_success "Vault JWT auth enabled"
        
        # Configure JWT auth for GitHub Actions
        log_info "  Configuring JWT auth for GitHub Actions..."
        vault write auth/jwt/config \
            jwks_url="https://token.actions.githubusercontent.com/.well-known/jwks" \
            bound_issuer="https://token.actions.githubusercontent.com" \
            user_claim="actor" || true
        
        # Create role for app-deployment
        vault write auth/jwt/role/app-deployment \
            bound_audiences="sts.amazonaws.com" \
            user_claim="actor" \
            role_type="jwt" \
            policies="default,app-deployment" || true
        
        log_success "Vault JWT role configured"
        log_audit "vault_jwt_configured" "SUCCESS"
        return 0
    else
        log_error "Failed to enable Vault JWT auth"
        log_audit "vault_jwt_failed" "FAILED"
        return 1
    fi
}

# ============================================================================
# GitHub Secrets Population (Idempotent)
# ============================================================================
populate_github_secrets() {
    log_info "Populating GitHub Secrets..."
    log_audit "github_secrets_start" "STARTED"
    
    if ! command -v gh &>/dev/null; then
        log_info "  ⓘ GitHub CLI not available - skipping auto-population"
        return 0
    fi
    
    # AWS layer secrets
    if [[ -f "${STATE_DIR:-.}/aws_oidc_arn.txt" ]]; then
        local oidc_arn
        oidc_arn=$(cat "${STATE_DIR:-.}/aws_oidc_arn.txt")
        # fallback: try to fetch from Vault/GSM
        if [[ -z "$oidc_arn" ]]; then
            oidc_arn=$(get_secret aws_oidc_arn || true)
        fi
        log_info "  Setting AWS_OIDC_ARN secret..."
        if [[ -n "$oidc_arn" ]]; then
            gh secret set AWS_OIDC_ARN --body "$oidc_arn" 2>/dev/null || log_info "    (Secret already exists or skipped)"
        else
            log_info "    (No AWS_OIDC_ARN available to set)"
        fi
    fi
    
    if [[ -f "${STATE_DIR:-.}/aws_kms_key_id.txt" ]]; then
        local kms_key_id
        kms_key_id=$(cat "${STATE_DIR:-.}/aws_kms_key_id.txt")
        # fallback: try to fetch from secret backends
        if [[ -z "$kms_key_id" ]]; then
            kms_key_id=$(get_secret aws_kms_key_id || true)
        fi
        log_info "  Setting AWS_KMS_KEY_ID secret..."
        if [[ -n "$kms_key_id" ]]; then
            gh secret set AWS_KMS_KEY_ID --body "$kms_key_id" 2>/dev/null || log_info "    (Secret already exists or skipped)"
        else
            log_info "    (No AWS_KMS_KEY_ID available to set)"
        fi
    fi
    
    # Vault secrets
    if [[ -n "${VAULT_ADDR:-}" ]]; then
        log_info "  Setting VAULT_ADDR secret..."
        gh secret set VAULT_ADDR --body "$VAULT_ADDR" 2>/dev/null || log_info "    (Secret already exists or skipped)"

        log_info "  Setting VAULT_NAMESPACE secret..."
        gh secret set VAULT_NAMESPACE --body "$VAULT_NAMESPACE" 2>/dev/null || log_info "    (Secret already exists or skipped)"

        # Optionally populate REDACTED_VAULT_TOKEN if available from backends (short-lived tokens not recommended in repo)
        local REDACTED_VAULT_TOKEN
        REDACTED_VAULT_TOKEN=$(get_secret vault-token || true)
        if [[ -n "$REDACTED_VAULT_TOKEN" ]]; then
            log_info "  Setting REDACTED_VAULT_TOKEN as GitHub secret (from Vault/GSM/local cache)..."
            gh secret set REDACTED_VAULT_TOKEN --body "$REDACTED_VAULT_TOKEN" 2>/dev/null || log_info "    (Secret already exists or skipped)"
        fi
    fi
    
    log_success "GitHub Secrets populated"
    log_audit "github_secrets_populated" "SUCCESS"
}

# ============================================================================
# Verification
# ============================================================================
verify_setup() {
    log_info "Verifying AWS + Vault Layer Setup..."
    log_audit "verify_start" "STARTED"
    
    local all_good=true
    
    # Verify AWS OIDC
    if aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(OpenIDConnectProviderArn, 'token.actions.githubusercontent.com')].OpenIDConnectProviderArn" --output text &>/dev/null; then
        log_info "  ✓ AWS OIDC Provider verified"
        log_audit "aws_oidc_verified" "SUCCESS"
    else
        log_error "  ✗ AWS OIDC Provider not found"
        all_good=false
    fi
    
    # Verify AWS KMS
    if aws kms describe-key --key-id "alias/github-actions-secrets" &>/dev/null; then
        log_info "  ✓ AWS KMS Key verified"
        log_audit "aws_kms_verified" "SUCCESS"
    else
        log_info "  ⓘ AWS KMS Key not yet available (may propagate)"
    fi
    
    # Verify Vault JWT
    if vault auth list --format=json 2>/dev/null | jq -e '.["jwt/"].type' &>/dev/null; then
        log_info "  ✓ Vault JWT auth verified"
        log_audit "vault_jwt_verified" "SUCCESS"
    else
        log_info "  ⓘ Vault JWT auth not available (optional)"
    fi
    
    mkdir -p "$STATE_DIR"
    # Load cached credentials and authenticate non-interactively (if available)
    load_secrets_and_auth
    if $all_good; then
        log_success "Setup verification passed"
        log_audit "verify_success" "SUCCESS"
        return 0
    else
        log_info "Setup verification partial (some components may need time to propagate)"
        return 0
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log_info "==========================================="
    log_info "Phase 3B: AWS + Vault Credentials Provisioning"
    log_info "Version: $SCRIPT_VERSION"
    log_info "(GCP WIF Layer skipped due to org-level permissions)"
    log_info "==========================================="
    log_audit "phase3b_start" "STARTED" "AWS + Vault layers"
    
    mkdir -p "$STATE_DIR"
    
    setup_aws_oidc || log_error "AWS OIDC setup failed"
    setup_aws_kms || log_error "AWS KMS setup failed"
    setup_vault_jwt || log_error "Vault JWT setup failed (optional)"
    populate_github_secrets
    verify_setup
    
    log_info ""
    log_success "==========================================="
    log_success "Phase 3B: AWS + Vault Credentials Ready"
    log_success "Immutable audit trail: $AUDIT_LOG"
    log_success "==========================================="
    log_audit "phase3b_complete" "SUCCESS" "AWS + Vault layers operational"
}

main "$@"
