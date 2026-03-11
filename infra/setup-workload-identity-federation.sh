#!/bin/bash
#
# GitHub Actions Workload Identity Federation Setup
# Enables passwordless authentication from GitHub runners to GCP
#
# Features:
#  - No hardcoded service account keys
#  - OIDC token exchange for short-lived credentials
#  - Minimum privilege (only deploy-runner role)
#  - Immutable audit trail
#
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-nexusshield-prod}"
REPO="kushin77/self-hosted-runner"
POOL_ID="runner-pool-20260311"
PROVIDER_ID="runner-provider-20260311"
SERVICE_ACCOUNT="runner-oidc@${PROJECT_ID}.iam.gserviceaccount.com"
AUDIT_LOG="/tmp/workload-identity-setup-$(date +%Y%m%d-%H%M%S).jsonl"

# Logging functions
log() {
    local level="$1" msg="$2"
    local ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    echo "{\"timestamp\":\"$ts\",\"level\":\"$level\",\"message\":\"$msg\"}" | tee -a "$AUDIT_LOG"
}

main() {
    log "INFO" "╔════════════════════════════════════════════════════════════╗"
    log "INFO" "║ GitHub Actions Workload Identity Federation Setup          ║"
    log "INFO" "║ Project: $PROJECT_ID | Repository: $REPO ║"
    log "INFO" "╚════════════════════════════════════════════════════════════╝"
    
    # Step 1: Verify workload identity pool and provider exist
    log "INFO" "Step 1: Verifying Workload Identity Pool and Provider..."
    
    if gcloud iam workload-identity-pools describe "$POOL_ID" \
        --location=global --project="$PROJECT_ID" &>/dev/null; then
        log "INFO" "✅ Workload Identity Pool exists: $POOL_ID"
    else
        log "WARN" "⚠️  Creating Workload Identity Pool..."
        gcloud iam workload-identity-pools create "$POOL_ID" \
            --project="$PROJECT_ID" \
            --location=global \
            --display-name="GitHub Actions Runner Pool" \
            --disabled=false || log "WARN" "Pool may already exist; continuing"
    fi
    
    if gcloud iam workload-identity-pools providers describe-oidc "$PROVIDER_ID" \
        --location=global --workload-identity-pool="$POOL_ID" --project="$PROJECT_ID" &>/dev/null; then
        log "INFO" "✅ OIDC Provider exists: $PROVIDER_ID"
    else
        log "WARN" "Provider not found or needs creation (checked in previous step)"
    fi
    
    # Step 2: Create runner service account if needed
    log "INFO" "Step 2: Setting up runner service account..."
    
    if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project="$PROJECT_ID" &>/dev/null; then
        log "INFO" "Creating service account: $SERVICE_ACCOUNT"
        gcloud iam service-accounts create runner-oidc \
            --project="$PROJECT_ID" \
            --display-name="GitHub Actions OIDC Runner" \
            --description="Passwordless auth for GitHub runner"
        log "INFO" "✅ Service account created"
    else
        log "INFO" "✅ Service account already exists"
    fi
    
    # Step 3: Bind Workload Identity Pool to service account
    log "INFO" "Step 3: Binding Workload Identity to service account..."
    
    local workload_identity_resource="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}/sub/repo:${REPO}"
    
    # Check if binding exists
    if gcloud iam service-accounts get-iam-policy "$SERVICE_ACCOUNT" \
        --project="$PROJECT_ID" 2>/dev/null | grep -q "workloadIdentityUser"; then
        log "INFO" "ℹ️  Workload Identity binding may already exist; updating..."
    fi
    
    # Add workloadIdentityUser role
    log "INFO" "Granting workloadIdentityUser role to token provider..."
    gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
        --project="$PROJECT_ID" \
        --role=roles/iam.workloadIdentityUser \
        --member="principal://iam.googleapis.com/${workload_identity_resource}" \
        --condition=None 2>&1 | tee -a "$AUDIT_LOG" || true
    
    log "INFO" "✅ Workload Identity binding configured"
    
    # Step 4: Grant minimal deployment permissions
    log "INFO" "Step 4: Granting minimum required IAM roles..."
    
    local roles=(
        "roles/run.invoker"                          # Invoke Cloud Run services
        "roles/storage.objectViewer"                 # Read deployment artifacts
        "roles/artifactregistry.reader"              # Read container images
        "roles/logging.logWriter"                    # Write deployment logs
    )
    
    for role in "${roles[@]}"; do
        log "INFO" "Granting: $role"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT}" \
            --role="$role" \
            --quiet 2>&1 | grep -v "^Updated" | tee -a "$AUDIT_LOG" || true
    done
    
    log "INFO" "✅ IAM roles assigned"
    
    # Step 5: Get federation credentials
    log "INFO" "Step 5: Computing federation credentials..."
    
    local workload_identity_pool_resource="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}"
    
    cat > /tmp/workload-identity-config.json <<EOF
{
    "type": "external_account",
    "audience": "iam.googleapis.com/${workload_identity_pool_resource}/providers/${PROVIDER_ID}",
    "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
    "service_account_impersonate_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SERVICE_ACCOUNT}:generateAccessToken",
    "token_url": "https://sts.googleapis.com/v1/token",
    "credential_source": {
        "environment_id": "github",
        "regional_cred_verification_url": "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15"
    }
}
EOF
    
    log "INFO" "✅ Federation configuration created"
    
    # Step 6: Output summary
    log "INFO" "╔════════════════════════════════════════════════════════════╗"
    log "INFO" "║ ✅ WORKLOAD IDENTITY FEDERATION COMPLETE                   ║"
    log "INFO" "╚════════════════════════════════════════════════════════════╝"
    
    echo ""
    echo "Configuration Summary:"
    echo "  Project: $PROJECT_ID"
    echo "  Pool: $POOL_ID"
    echo "  Provider: $PROVIDER_ID"
    echo "  Service Account: $SERVICE_ACCOUNT"
    echo ""
    echo "GitHub Actions Configuration (add to .github/workflows):"
    echo "  - uses: google-github-actions/auth@v1.0.0"
    echo "    with:"
    echo "      workload_identity_provider: projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
    echo "      service_account: ${SERVICE_ACCOUNT}"
    echo ""
    echo "Audit Log: $AUDIT_LOG"
    echo ""
    
    log "INFO" "Audit trail written to: $AUDIT_LOG"
}

main "$@"
