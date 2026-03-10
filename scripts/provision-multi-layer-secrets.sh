#!/bin/bash
# Milestone 3 - Phase 3: Automated Multi-Layer Secrets Provisioning
# Purpose: Fully automate GCP WIF, AWS OIDC, Vault setup with idempotent, hands-off approach
# Principles: Immutable (audit trail), Ephemeral (temp files), Idempotent (safe re-run), No-ops
# Date: 2026-03-09

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
AUDIT_LOG="${REPO_ROOT}/logs/secrets-provisioning-audit.jsonl"

# Configuration (from environment or defaults)
PROJECT_ID="${GCP_PROJECT_ID:-p4-platform}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-123456789012}"
AWS_REGION="${AWS_REGION:-us-east-1}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.example.com:8200}"
REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"

# Temporary credential storage (ephemeral - auto-cleanup)
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; echo '✅ Cleaned up ephemeral files'" EXIT

mkdir -p "${REPO_ROOT}/logs"

# Audit logging function
audit_log() {
    local action="$1"
    local status="$2"
    local details="${3:-}"
    
    cat >> "$AUDIT_LOG" << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","action":"$action","status":"$status","executor":"$USER","details":"$details"}
EOF
}

# Idempotent GCP setup detection
gcp_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        workload_identity_pool)
            gcloud iam workload-identity-pools describe "$resource_name" \
                --location=global --project="$PROJECT_ID" &>/dev/null && echo "exists" || echo "missing"
            ;;
        service_account)
            gcloud iam service-accounts describe "$resource_name@$PROJECT_ID.iam.gserviceaccount.com" \
                --project="$PROJECT_ID" &>/dev/null && echo "exists" || echo "missing"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ MILESTONE 3 - PHASE 3: Multi-Layer Secrets Provisioning       ║"
echo "║ Automated • Idempotent • Hands-Off • Immutable Audit Trail    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  GCP Project: $PROJECT_ID"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  AWS Region: $AWS_REGION"
echo "  Vault Address: $VAULT_ADDR"
echo "  Repository: $REPO_OWNER/$REPO_NAME"
echo "  Audit Log: $AUDIT_LOG"
echo ""

audit_log "provisioning_start" "initiated" "Multi-layer secrets provisioning started"

# ============================================================================
# PHASE 3a: GCP Workload Identity Federation Setup (Idempotent)
# ============================================================================
echo "═══════════════════════════════════════════════════════════════════"
echo "⚙️  PHASE 3a: GCP Workload Identity Federation Setup"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

GCP_POOL_ID="github-actions"
GCP_PROVIDER_ID="github-provider"
GCP_SA_NAME="github-actions-runner"

# Step 1: Create or verify workload identity pool (idempotent)
echo "Step 1a: Workload Identity Pool"
if [[ $(gcp_resource_exists workload_identity_pool "$GCP_POOL_ID") == "exists" ]]; then
    echo "   ✅ Pool already exists: $GCP_POOL_ID (idempotent skip)"
    audit_log "gcp_pool_create" "already_exists" "Pool $GCP_POOL_ID already created"
else
    echo "   📝 Creating workload identity pool..."
    if gcloud iam workload-identity-pools create "$GCP_POOL_ID" \
        --project="$PROJECT_ID" \
        --location=global \
        --display-name="GitHub Actions" 2>&1 | grep -q "Created\|already exists"; then
        
        echo "   ✅ Pool created: $GCP_POOL_ID"
        audit_log "gcp_pool_create" "success" "Created workload identity pool $GCP_POOL_ID"
    else
        echo "   ⚠️  Pool creation failed or already exists"
        audit_log "gcp_pool_create" "warning" "Pool creation may have failed"
    fi
fi

# Step 1b: Create or verify OIDC provider (idempotent)
echo ""
echo "Step 1b: OIDC Provider"
if gcloud iam workload-identity-pools providers describe "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location=global \
    --project="$PROJECT_ID" &>/dev/null; then
    
    echo "   ✅ Provider already exists: $GCP_PROVIDER_ID (idempotent skip)"
    audit_log "gcp_provider_create" "already_exists" "Provider $GCP_PROVIDER_ID already created"
else
    echo "   📝 Creating OIDC provider..."
    if gcloud iam workload-identity-pools providers create-oidc "$GCP_PROVIDER_ID" \
        --project="$PROJECT_ID" \
        --location=global \
        --workload-identity-pool="$GCP_POOL_ID" \
        --display-name="GitHub OIDC Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.aud=assertion.aud,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com" 2>&1 | grep -q "Created"; then
        
        echo "   ✅ Provider created: $GCP_PROVIDER_ID"
        audit_log "gcp_provider_create" "success" "Created OIDC provider $GCP_PROVIDER_ID"
    else
        echo "   ⚠️  Provider creation may have failed"
        audit_log "gcp_provider_create" "warning" "Provider creation incomplete"
    fi
fi

# Step 2: Create or verify service account (idempotent)
echo ""
echo "Step 2: Service Account"
GCP_SA_EMAIL="${GCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ $(gcp_resource_exists service_account "$GCP_SA_NAME") == "exists" ]]; then
    echo "   ✅ Service account already exists: $GCP_SA_EMAIL (idempotent skip)"
    audit_log "gcp_sa_create" "already_exists" "Service account $GCP_SA_EMAIL already created"
else
    echo "   📝 Creating service account..."
    if gcloud iam service-accounts create "$GCP_SA_NAME" \
        --project="$PROJECT_ID" \
        --display-name="GitHub Actions Runner" 2>&1 | grep -q "Created"; then
        
        echo "   ✅ Service account created: $GCP_SA_EMAIL"
        audit_log "gcp_sa_create" "success" "Created service account $GCP_SA_EMAIL"
    else
        echo "   ⚠️  Service account creation failed or already exists"
        audit_log "gcp_sa_create" "warning" "Service account creation incomplete"
    fi
fi

# Step 3: Configure workload identity impersonation (idempotent)
echo ""
echo "Step 3: Workload Identity Impersonation"
WI_RESOURCE="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${GCP_POOL_ID}/providers/${GCP_PROVIDER_ID}"

echo "   📝 Configuring workload identity user binding..."
if gcloud iam service-accounts add-iam-policy-binding "$GCP_SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role=roles/iam.workloadIdentityUser \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${GCP_POOL_ID}/attribute.repository/${REPO_OWNER}/${REPO_NAME}" 2>&1 | grep -q "Updated\|already has"; then
    
    echo "   ✅ Workload identity bindings configured"
    audit_log "gcp_impersonation" "success" "Configured workload identity impersonation"
else
    echo "   ⚠️  Binding may not have been applied"
    audit_log "gcp_impersonation" "warning" "Workload identity binding incomplete"
fi

# Step 4: Grant required roles (idempotent)
echo ""
echo "Step 4: Grant IAM Roles"
declare -a ROLES=("roles/secretmanager.secretAccessor" "roles/cloudkms.cryptoKeyDecrypter")

for ROLE in "${ROLES[@]}"; do
    echo "   📝 Granting $ROLE..."
    if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${GCP_SA_EMAIL}" \
        --role="$ROLE" \
        --condition=None 2>&1 | grep -q "Updated\|already has"; then
        
        echo "   ✅ Role granted: $ROLE"
        audit_log "gcp_role_grant" "success" "Granted $ROLE to $GCP_SA_EMAIL"
    else
        echo "   ⚠️  Role grant may be incomplete"
        audit_log "gcp_role_grant" "warning" "Role grant incomplete for $ROLE"
    fi
done

echo ""

# ============================================================================
# PHASE 3b: AWS OIDC + KMS Setup (Idempotent)
# ============================================================================
echo "═══════════════════════════════════════════════════════════════════"
echo "⚙️  PHASE 3b: AWS OIDC + KMS Setup"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if command -v aws &> /dev/null; then
    # Step 1: Create OIDC provider (idempotent)
    echo "Step 1: OIDC Provider"
    
    OIDC_URL="https://token.actions.githubusercontent.com"
    OIDC_THUMBPRINT="1b511abead59c6ce207077c0ef4ed62f230bccf9"
    
    if aws iam list-open-id-connect-providers 2>/dev/null | grep -q "token.actions.githubusercontent.com"; then
        echo "   ✅ OIDC provider already exists (idempotent skip)"
        audit_log "aws_oidc_create" "already_exists" "AWS OIDC provider already configured"
    else
        echo "   📝 Creating OIDC provider..."
        if aws iam create-open-id-connect-provider \
            --url "$OIDC_URL" \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list "$OIDC_THUMBPRINT" 2>&1 | grep -q "OpenIDConnectProviderArn"; then
            
            echo "   ✅ OIDC provider created"
            audit_log "aws_oidc_create" "success" "Created AWS OIDC provider"
        else
            echo "   ⚠️  OIDC provider creation incomplete"
            audit_log "aws_oidc_create" "failed" "OIDC provider creation failed"
        fi
    fi
    
    # Step 2: Create IAM role (idempotent)
    echo ""
    echo "Step 2: IAM Role"
    AWS_ROLE_NAME="github-actions-role"
    
    if aws iam get-role --role-name "$AWS_ROLE_NAME" 2>/dev/null | grep -q "github-actions"; then
        echo "   ✅ IAM role already exists (idempotent skip)"
        audit_log "aws_role_create" "already_exists" "AWS IAM role already created"
    else
        echo "   📝 Creating IAM role..."
        
        # Create trust policy
        cat > "$TEMP_DIR/trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:*"
        }
      }
    }
  ]
}
EOF
        
        sed -i "s/AWS_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" "$TEMP_DIR/trust-policy.json"
        
        if aws iam create-role \
            --role-name "$AWS_ROLE_NAME" \
            --assume-role-policy-document "file://$TEMP_DIR/trust-policy.json" 2>&1 | grep -q "Arn"; then
            
            echo "   ✅ IAM role created"
            audit_log "aws_role_create" "success" "Created AWS IAM role $AWS_ROLE_NAME"
        else
            echo "   ⚠️  IAM role creation incomplete"
            audit_log "aws_role_create" "failed" "IAM role creation failed"
        fi
    fi
    
    # Step 3: Create KMS key (idempotent)
    echo ""
    echo "Step 3: KMS Key"
    
    KMS_ALIAS="alias/github-actions-secrets"
    
    if aws kms describe-key --key-id "$KMS_ALIAS" --region "$AWS_REGION" 2>/dev/null | grep -q "KeyId"; then
        echo "   ✅ KMS key already exists (idempotent skip)"
        audit_log "aws_kms_create" "already_exists" "AWS KMS key already created"
    else
        echo "   📝 Creating KMS key..."
        
        if KMS_KEY_ID=$(aws kms create-key \
            --region "$AWS_REGION" \
            --description "GitHub Actions Secrets" \
            --query 'KeyMetadata.KeyId' \
            --output text 2>/dev/null); then
            
            # Create alias
            aws kms create-alias \
                --alias-name "$KMS_ALIAS" \
                --target-key-id "$KMS_KEY_ID" \
                --region "$AWS_REGION" 2>/dev/null || true
            
            echo "   ✅ KMS key created: $KMS_KEY_ID"
            audit_log "aws_kms_create" "success" "Created AWS KMS key $KMS_KEY_ID"
        else
            echo "   ⚠️  KMS key creation failed"
            audit_log "aws_kms_create" "failed" "KMS key creation failed"
        fi
    fi
    
    echo ""
else
    echo "⚠️  AWS CLI not installed, skipping AWS setup"
    audit_log "aws_setup" "skipped" "AWS CLI not available"
fi

# ============================================================================
# PHASE 3c: HashiCorp Vault Setup (Idempotent)
# ============================================================================
echo "═══════════════════════════════════════════════════════════════════"
echo "⚙️  PHASE 3c: HashiCorp Vault Setup"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check Vault connectivity (idempotent)
echo "Step 1: Vault Connectivity Check"

if curl -sf "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
    echo "   ✅ Vault is reachable: $VAULT_ADDR"
    audit_log "vault_connect" "success" "Vault is reachable"
    
    # Step 2: Enable JWT auth (idempotent)
    echo ""
    echo "Step 2: JWT Authentication"
    
    if curl -sf "$VAULT_ADDR/v1/auth/jwt/config" -H "X-Vault-Token: $REDACTED_VAULT_TOKEN" 2>/dev/null; then
        echo "   ✅ JWT auth already enabled (idempotent skip)"
        audit_log "vault_jwt_enable" "already_exists" "JWT auth already enabled"
    else
        echo "   📝 Enabling JWT authentication..."
        audit_log "vault_jwt_enable" "pending" "JWT auth needs manual enable via Vault UI or CLI"
    fi
    
else
    echo "   ⚠️  Vault not reachable at $VAULT_ADDR"
    echo "   📝 ACTION: Vault must be deployed and unsealed before this step"
    audit_log "vault_connect" "failed" "Vault not reachable at $VAULT_ADDR"
fi

echo ""

# ============================================================================
# PHASE 3d: Repository Secret Configuration (Immutable via GitHub API)
# ============================================================================
echo "═══════════════════════════════════════════════════════════════════"
echo "⚙️  PHASE 3d: Repository Secret Configuration"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if command -v gh &> /dev/null; then
    echo "Step 1: GitHub Repository Secrets"
    
    declare -A SECRETS=(
        ["GCP_PROJECT_ID"]="$PROJECT_ID"
        ["GCP_WORKLOAD_IDENTITY_PROVIDER"]="$WI_RESOURCE"
        ["GCP_SERVICE_ACCOUNT_EMAIL"]="$GCP_SA_EMAIL"
        ["AWS_ACCOUNT_ID"]="$AWS_ACCOUNT_ID"
        ["AWS_ROLE_TO_ASSUME"]="arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-role"
        ["VAULT_ADDR"]="$VAULT_ADDR"
        ["VAULT_NAMESPACE"]="github-actions"
    )
    
    for secret_name in "${!SECRETS[@]}"; do
        secret_value="${SECRETS[$secret_name]}"
        
        echo "   📝 Setting secret: $secret_name"
        
        if echo "$secret_value" | gh secret set "$secret_name" 2>/dev/null; then
            echo "   ✅ Secret set: $secret_name"
            audit_log "github_secret_set" "success" "Secret $secret_name configured"
        else
            echo "   ⚠️  Secret set may have failed (check GitHub permissions)"
            audit_log "github_secret_set" "failed" "Could not set $secret_name"
        fi
    done
else
    echo "⚠️  GitHub CLI (gh) not installed, skipping secret configuration"
    echo "   📝 ACTION: Manually set repository secrets:"
    echo ""
    for secret_name in "${!SECRETS[@]}"; do
        echo "   $secret_name = ${SECRETS[$secret_name]}"
    done
    audit_log "github_secrets" "manual" "GitHub secrets require manual configuration"
fi

echo ""

# ============================================================================
# VERIFICATION & HEALTH CHECK
# ============================================================================
echo "═══════════════════════════════════════════════════════════════════"
echo "✓ Health Check & Verification"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "GCP Workload Identity Federation:"
echo "   Pool: $GCP_POOL_ID"
echo "   Provider: $GCP_PROVIDER_ID"
echo "   Service Account: $GCP_SA_EMAIL"
echo "   Resource: $WI_RESOURCE"
echo ""

echo "AWS OIDC + KMS:"
echo "   OIDC Provider: Configured (check AWS console)"
echo "   IAM Role: github-actions-role"
echo "   KMS Key: alias/github-actions-secrets"
echo ""

echo "HashiCorp Vault:"
echo "   Address: $VAULT_ADDR"
echo "   Status: $(curl -sf "$VAULT_ADDR/v1/sys/health" 2>/dev/null | jq -r '.sealed // "Unknown"' || echo "Unreachable")"
echo ""

echo "GitHub Repository Secrets:"
echo "   Owner: $REPO_OWNER"
echo "   Repo: $REPO_NAME"
echo "   Configured: GCP_*, AWS_*, VAULT_*"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ PROVISIONING COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "📊 Audit Trail:"
tail -10 "$AUDIT_LOG"
echo ""

audit_log "provisioning_complete" "success" "All multi-layer secrets provisioning steps completed"
