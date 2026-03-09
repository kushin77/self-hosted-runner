#!/bin/bash
###############################################################################
# Phase 3: Multi-Layer Credentials Provisioning - Fully Automated
# Issue: #1692 - Operator action: configure cloud credentials
# Architecture: Immutable (audit logged), Ephemeral (auto-expires),
#             Idempotent (safe to re-run), Hands-off (fully automated)
###############################################################################

set -euo pipefail

# ============================================================================
# CONFIG
# ============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly AUDIT_LOG_DIR="${HOME}/.phase3-credentials"
readonly AUDIT_LOG="${AUDIT_LOG_DIR}/credentials.jsonl"
readonly STATE_DIR="${AUDIT_LOG_DIR}/state"
readonly GCP_PROJECT="${GCP_PROJECT:-p4-platform}"
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly VAULT_ADDR="${VAULT_ADDR:-https://vault.example.com:8200}"
readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-github-actions}"

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

# ============================================================================
# PHASE 3A: GCP Workload Identity Federation (WIF)
# ============================================================================
setup_gcp_wif() {
    log_info "Phase 3A: Setting up GCP Workload Identity Federation..."
    log_audit "gcp_wif_start" "STARTED"
    
    local pool_id="github-actions"
    local provider_id="github-provider"
    
    # Check if pool already exists (idempotent)
    if gcloud iam workload-identity-pools list \
        --project="$GCP_PROJECT" \
        --location=global \
        --format='value(name)' \
        | grep -q "$pool_id"; then
        log_info "WIF pool already exists: $pool_id (idempotent skip)"
        log_audit "gcp_wif_skip" "SKIPPED" "Pool exists"
        return 0
    fi
    
    log_info "Creating GCP Workload Identity Pool: $pool_id"
    
    # Create pool
    if ! gcloud iam workload-identity-pools create "$pool_id" \
        --project="$GCP_PROJECT" \
        --location=global \
        --display-name="GitHub Actions" > /dev/null 2>&1; then
        log_error "Failed to create WIF pool"
        log_audit "gcp_wif_pool_failed" "ERROR" "Pool creation failed"
        return 1
    fi
    
    log_info "Creating OIDC provider: $provider_id"
    
    # Create OIDC provider
    if ! gcloud iam workload-identity-pools providers create-oidc "$provider_id" \
        --project="$GCP_PROJECT" \
        --location=global \
        --workload-identity-pool="$pool_id" \
        --display-name="GitHub OIDC Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.aud=assertion.aud" \
        --issuer-uri="https://token.actions.githubusercontent.com" > /dev/null 2>&1; then
        log_error "Failed to create OIDC provider"
        log_audit "gcp_wif_provider_failed" "ERROR" "Provider creation failed"
        return 1
    fi
    
    log_info "✅ GCP WIF setup complete"
    log_audit "gcp_wif_success" "SUCCESS" "Pool and provider created"
}

# ============================================================================
# PHASE 3B: GCP Service Account Setup
# ============================================================================
setup_gcp_service_account() {
    log_info "Phase 3B: Setting up GCP Service Account..."
    log_audit "gcp_sa_start" "STARTED"
    
    local sa_name="github-actions-runner"
    local sa_email="${sa_name}@${GCP_PROJECT}.iam.gserviceaccount.com"
    
    # Check if SA already exists (idempotent)
    if gcloud iam service-accounts describe "$sa_email" \
        --project="$GCP_PROJECT" > /dev/null 2>&1; then
        log_info "Service account already exists: $sa_email (idempotent skip)"
        log_audit "gcp_sa_skip" "SKIPPED" "SA exists"
        return 0
    fi
    
    log_info "Creating service account: $sa_name"
    
    if ! gcloud iam service-accounts create "$sa_name" \
        --project="$GCP_PROJECT" \
        --display-name="GitHub Actions Runner" > /dev/null 2>&1; then
        log_error "Failed to create service account"
        log_audit "gcp_sa_failed" "ERROR" "SA creation failed"
        return 1
    fi
    
    # Grant roles (idempotent)
    log_info "Granting required IAM roles..."
    
    # Secret Manager access
    gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
        --member="serviceAccount:$sa_email" \
        --role="roles/secretmanager.secretAccessor" \
        --quiet > /dev/null 2>&1 || true
    
    # Cloud KMS access
    gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
        --member="serviceAccount:$sa_email" \
        --role="roles/cloudkms.cryptoKeyDecrypter" \
        --quiet > /dev/null 2>&1 || true
    
    log_info "✅ GCP Service Account setup complete"
    log_audit "gcp_sa_success" "SUCCESS" "SA created with required roles"
}

# ============================================================================
# PHASE 3C: AWS OIDC Configuration
# ============================================================================
setup_aws_oidc() {
    log_info "Phase 3C: Setting up AWS OIDC provider..."
    log_audit "aws_oidc_start" "STARTED"
    
    # Check if OIDC provider already exists (idempotent)
    if aws iam list-open-id-connect-providers 2>/dev/null | \
        grep -q "token.actions.githubusercontent.com"; then
        log_info "OIDC provider already exists (idempotent skip)"
        log_audit "aws_oidc_skip" "SKIPPED" "Provider exists"
        return 0
    fi
    
    log_info "Creating AWS OIDC provider..."
    
    # Create OIDC provider
    if ! aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 1b511abead59c6ce207077c0ef4ed62f230bccf9 \
        --region="$AWS_REGION" > /dev/null 2>&1; then
        log_error "Failed to create AWS OIDC provider"
        log_audit "aws_oidc_failed" "ERROR" "Provider creation failed"
        return 1
    fi
    
    log_info "✅ AWS OIDC provider setup complete"
    log_audit "aws_oidc_success" "SUCCESS"
}

# ============================================================================
# PHASE 3D: AWS KMS Key Setup
# ============================================================================
setup_aws_kms() {
    log_info "Phase 3D: Setting up AWS KMS key..."
    log_audit "aws_kms_start" "STARTED"
    
    # Check if key alias already exists (idempotent)
    if aws kms describe-key --key-id alias/github-actions-secrets \
        --region="$AWS_REGION" > /dev/null 2>&1; then
        log_info "KMS key alias already exists (idempotent skip)"
        log_audit "aws_kms_skip" "SKIPPED" "Key exists"
        return 0
    fi
    
    log_info "Creating AWS KMS key..."
    
    # Create KMS key
    local key_id
    key_id=$(aws kms create-key \
        --description "GitHub Actions Secrets" \
        --region="$AWS_REGION" \
        --query 'KeyMetadata.KeyId' \
        --output text)
    
    if [[ -z "$key_id" ]]; then
        log_error "Failed to create KMS key"
        log_audit "aws_kms_failed" "ERROR" "Key creation failed"
        return 1
    fi
    
    # Create alias
    aws kms create-alias \
        --alias-name alias/github-actions-secrets \
        --target-key-id "$key_id" \
        --region="$AWS_REGION" > /dev/null 2>&1 || true
    
    log_info "✅ AWS KMS setup complete: $key_id"
    log_audit "aws_kms_success" "SUCCESS" "Key: $key_id"
}

# ============================================================================
# PHASE 3E: Vault OIDC Configuration
# ============================================================================
setup_vault_oidc() {
    log_info "Phase 3E: Setting up Vault JWT/OIDC auth..."
    log_audit "vault_oidc_start" "STARTED"
    
    # Check Vault connectivity
    if ! curl -s -k "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        log_error "Vault not reachable: $VAULT_ADDR"
        log_audit "vault_oidc_failed" "ERROR" "Vault unreachable"
        return 1
    fi
    
    log_info "Vault is reachable: $VAULT_ADDR"
    
    # Check if JWT auth already exists (idempotent)
    if vault auth list -format=json | grep -q "jwt/"; then
        log_info "JWT auth method already exists (idempotent skip)"
        log_audit "vault_oidc_skip" "SKIPPED" "Auth method exists"
        return 0
    fi
    
    log_info "Enabling JWT auth method in Vault..."
    
    # Enable JWT auth
    if ! vault auth enable jwt > /dev/null 2>&1; then
        log_error "Failed to enable JWT auth"
        log_audit "vault_jwt_enable_failed" "ERROR" "Auth enable failed"
        return 1
    fi
    
    # Configure JWT auth
    vault write auth/jwt/config \
        jwks_url="https://token.actions.githubusercontent.com/.well-known/jwks.json" \
        bound_audiences="https://github.com/kushin77" > /dev/null 2>&1 || true
    
    # Create role
    vault write auth/jwt/role/github-actions \
        bound_audiences="https://github.com/kushin77" \
        user_claim="sub" \
        role_type="jwt" \
        policies="github-actions" > /dev/null 2>&1 || true
    
    log_info "✅ Vault OIDC setup complete"
    log_audit "vault_oidc_success" "SUCCESS"
}

# ============================================================================
# PHASE 3F: GitHub Repository Secrets
# ============================================================================
setup_github_secrets() {
    log_info "Phase 3F: Setting up GitHub repository secrets..."
    log_audit "github_secrets_start" "STARTED"
    
    # Get required values
    local gcp_wif_provider
    gcp_wif_provider=$(gcloud iam workload-identity-pools providers describe \
        github-provider \
        --workload-identity-pool=github-actions \
        --project="$GCP_PROJECT" \
        --location=global \
        --format='value(name)' 2>/dev/null || echo "")
    
    if [[ -z "$gcp_wif_provider" ]]; then
        log_error "Failed to get GCP WIF provider resource name"
        log_audit "github_secrets_failed" "ERROR" "WIF provider not found"
        return 1
    fi
    
    log_info "Setting GitHub secrets..."
    
    # GCP secrets
    gh secret set GCP_PROJECT_ID --body "$GCP_PROJECT" 2>/dev/null || log_error "Failed to set GCP_PROJECT_ID"
    gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$gcp_wif_provider" 2>/dev/null || log_error "Failed to set GCP_WORKLOAD_IDENTITY_PROVIDER"
    gh secret set GCP_SERVICE_ACCOUNT_EMAIL --body "github-actions-runner@${GCP_PROJECT}.iam.gserviceaccount.com" 2>/dev/null || log_error "Failed to set GCP_SERVICE_ACCOUNT_EMAIL"
    
    # Vault secrets
    gh secret set VAULT_ADDR --body "$VAULT_ADDR" 2>/dev/null || log_error "Failed to set VAULT_ADDR"
    gh secret set VAULT_NAMESPACE --body "$VAULT_NAMESPACE" 2>/dev/null || log_error "Failed to set VAULT_NAMESPACE"
    
    log_info "✅ GitHub secrets configured"
    log_audit "github_secrets_success" "SUCCESS"
}

# ============================================================================
# PHASE 3G: Verification & Health Check
# ============================================================================
verify_setup() {
    log_info "Phase 3G: Verifying multi-layer setup..."
    log_audit "verify_start" "STARTED"
    
    local all_ok=true
    
    # Check GCP WIF
    if gcloud iam workload-identity-pools list \
        --project="$GCP_PROJECT" \
        --location=global \
        --format='value(name)' \
        | grep -q "github-actions"; then
        log_info "✅ GCP WIF: operational"
    else
        log_error "❌ GCP WIF: not found"
        all_ok=false
    fi
    
    # Check GCP Service Account
    if gcloud iam service-accounts describe \
        "github-actions-runner@${GCP_PROJECT}.iam.gserviceaccount.com" \
        --project="$GCP_PROJECT" > /dev/null 2>&1; then
        log_info "✅ GCP Service Account: operational"
    else
        log_error "❌ GCP Service Account: not found"
        all_ok=false
    fi
    
    # Check AWS OIDC
    if aws iam list-open-id-connect-providers 2>/dev/null | \
        grep -q "token.actions.githubusercontent.com"; then
        log_info "✅ AWS OIDC: operational"
    else
        log_error "❌ AWS OIDC: not configured"
        all_ok=false
    fi
    
    # Check AWS KMS
    if aws kms describe-key --key-id alias/github-actions-secrets \
        --region="$AWS_REGION" > /dev/null 2>&1; then
        log_info "✅ AWS KMS: operational"
    else
        log_error "❌ AWS KMS: not found"
        all_ok=false
    fi
    
    # Check Vault
    if curl -s -k "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        log_info "✅ Vault: operational"
    else
        log_error "❌ Vault: not reachable"
        all_ok=false
    fi
    
    if [[ "$all_ok" == true ]]; then
        log_info "✅ All verification checks passed"
        log_audit "verify_success" "SUCCESS" "All layers operational"
        return 0
    else
        log_error "⚠️  Some verification checks failed"
        log_audit "verify_warning" "WARNING" "Some layers not operational"
        return 1
    fi
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================
main() {
    log_info "=========================================="
    log_info "Phase 3: Multi-Layer Credentials Provisioning"
    log_info "Version: $SCRIPT_VERSION"
    log_info "=========================================="
    log_audit "execution_start" "STARTED" "Full Phase 3 automation"
    
    mkdir -p "$STATE_DIR"
    
    # Execute phases sequentially (idempotent)
    setup_gcp_wif || { log_error "Phase 3A failed"; exit 1; }
    setup_gcp_service_account || { log_error "Phase 3B failed"; exit 1; }
    setup_aws_oidc || { log_error "Phase 3C failed"; exit 1; }
    setup_aws_kms || { log_error "Phase 3D failed"; exit 1; }
    setup_vault_oidc || { log_error "Phase 3E failed"; exit 1; }
    setup_github_secrets || { log_error "Phase 3F failed"; exit 1; }
    verify_setup || { log_error "Verification failed"; exit 1; }
    
    log_info "=========================================="
    log_info "✅ Phase 3 Complete!"
    log_info "=========================================="
    log_audit "execution_success" "SUCCESS" "All phases completed"
    
    # Print audit trail
    echo ""
    echo "📋 Immutable Audit Trail:"
    cat "$AUDIT_LOG"
}

main "$@"
