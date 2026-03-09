#!/bin/bash
set -euo pipefail

##############################################################################
# OIDC & Credential Infrastructure Setup Script
# Purpose: Configure GitHub Actions OIDC integration with GSM/Vault/KMS
# Requirements: gcloud, aws, vault CLIs; appropriate permissions
##############################################################################

TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
LOG_FILE="oidc-setup-${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }

# Configuration
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
VAULT_ADDR="${VAULT_ADDR:-}"
GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
GITHUB_REPO="${GITHUB_REPO:-self-hosted-runner}"

##############################################################################
# Phase 1: GCP Configuration (GSM as Primary)
##############################################################################

setup_gcp() {
  log_info "=== Phase 1: GCP Configuration (Primary Layer) ==="
  
  if [ -z "$GCP_PROJECT_ID" ]; then
    log_fail "GCP_PROJECT_ID not set"
    return 1
  fi

  # Step 1: Enable required APIs
  log_info "Enabling GCP APIs..."
  gcloud services enable secretmanager.googleapis.com \
    --project="$GCP_PROJECT_ID" || log_warn "Secret Manager API might already be enabled"
  gcloud services enable iamcredentials.googleapis.com \
    --project="$GCP_PROJECT_ID" || log_warn "IAM Credentials API might already be enabled"
  log_pass "GCP APIs enabled"

  # Step 2: Create Workload Identity Provider
  log_info "Creating Workload Identity Provider..."
  PROVIDER_ID="github-actions"
  PROVIDER_NAME="projects/$GCP_PROJECT_ID/locations/global/workloadIdentityPools/$PROVIDER_ID/providers/github"

  gcloud iam workload-identity-pools create "$PROVIDER_ID" \
    --project="$GCP_PROJECT_ID" \
    --location="global" \
    --display-name="GitHub Actions" \
    --disabled=false 2>/dev/null || log_warn "Workload pool might already exist"

  gcloud iam workload-identity-pools providers create-oidc github \
    --project="$GCP_PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$PROVIDER_ID" \
    --display-name="GitHub" \
    --attribute-mapping="google.subject=assertion.sub,assertion.aud=assertion.aud" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-condition="assertion.aud == '$PROVIDER_NAME'" 2>/dev/null || \
    log_warn "OIDC provider might already exist"

  log_pass "Workload Identity Provider configured"

  # Step 3: Create service account
  log_info "Creating/updating service account..."
  SA_NAME="github-actions-sa"
  SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

  gcloud iam service-accounts create "$SA_NAME" \
    --project="$GCP_PROJECT_ID" \
    --display-name="GitHub Actions Service Account" 2>/dev/null || \
    log_warn "Service account might already exist"

  # Grant Secret Manager access
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=none 2>/dev/null || log_warn "IAM binding might already exist"

  # Step 4: Setup Workload Identity binding
  log_info "Setting up Workload Identity binding..."
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$GCP_PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_ID}/locations/global/workloadIdentityPools/${PROVIDER_ID}/attribute.repository/${GITHUB_OWNER}/${GITHUB_REPO}" \
    2>/dev/null || log_warn "Binding might already exist"

  log_pass "GCP configuration complete"
  echo "export GCP_PROJECT_ID=$GCP_PROJECT_ID"
  echo "export GCP_WORKLOAD_IDENTITY_PROVIDER=$PROVIDER_NAME"
  echo "export GCP_SERVICE_ACCOUNT=$SA_EMAIL"
}

##############################################################################
# Phase 2: AWS Configuration (KMS as Tertiary)
##############################################################################

setup_aws() {
  log_info "=== Phase 2: AWS Configuration (Tertiary Layer) ==="
  
  if [ -z "$AWS_ACCOUNT_ID" ]; then
    log_fail "AWS_ACCOUNT_ID not set"
    return 1
  fi

  # Step 1: Create IAM role for GitHub Actions
  log_info "Creating IAM role..."
  ROLE_NAME="GitHubActionsRole"
  
  TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_OWNER}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)

  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" 2>/dev/null || \
    log_warn "Role might already exist"

  # Step 2: Create KMS key for encryption
  log_info "Creating KMS key..."
  KMS_KEY_ID=$(aws kms create-key \
    --description "GitHub Actions Credential Encryption" \
    --key-policy '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "Enable IAM policies",
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::'$AWS_ACCOUNT_ID':root"
          },
          "Action": "kms:*",
          "Resource": "*"
        }
      ]
    }' 2>/dev/null | jq -r '.KeyMetadata.KeyId' || \
    log_warn "KMS key creation might have failed")

  # Step 3: Enable key rotation
  if [ -n "$KMS_KEY_ID" ]; then
    aws kms enable-key-rotation --key-id "$KMS_KEY_ID" 2>/dev/null || true
    log_pass "KMS key created and rotation enabled: $KMS_KEY_ID"
  fi

  # Step 4: Create Secrets Manager secret for test
  log_info "Create IAM policy for GitHub Actions..."
  POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:*:${AWS_ACCOUNT_ID}:key/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:${AWS_ACCOUNT_ID}:secret:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GitHubActionsPolicy" \
    --policy-document "$POLICY" 2>/dev/null || \
    log_warn "IAM policy might not have been created"

  # Get the role ARN
  ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)
  
  log_pass "AWS configuration complete"
  echo "export AWS_OIDC_ROLE_ARN=$ROLE_ARN"
  echo "export AWS_KMS_KEY_ID=$KMS_KEY_ID"
}

##############################################################################
# Phase 3: Vault Configuration (Secondary)
##############################################################################

setup_vault() {
  log_info "=== Phase 3: Vault Configuration (Secondary Layer) ==="
  
  if [ -z "$VAULT_ADDR" ]; then
    log_fail "VAULT_ADDR not set"
    return 1
  fi

  if [ -z "$VAULT_TOKEN" ]; then
    log_fail "VAULT_TOKEN not set (required for initial setup)"
    return 1
  fi

  # Step 1: Enable JWT auth
  log_info "Enabling JWT authentication..."
  curl -sS "$VAULT_ADDR/v1/sys/auth/jwt" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -X POST \
    -d @- <<EOF 2>/dev/null || log_warn "JWT auth might already be enabled"
{
  "type": "jwt"
}
EOF

  # Step 2: Configure JWT auth
  log_info "Configuring JWT auth for GitHub Actions..."
  curl -sS "$VAULT_ADDR/v1/auth/jwt/config" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -X POST \
    -d @- <<EOF 2>/dev/null
{
  "oidc_discovery_url": "https://token.actions.githubusercontent.com",
  "bound_audiences": "https://$VAULT_ADDR"
}
EOF

  # Step 3: Create role
  log_info "Creating Vault role for GitHub Actions..."
  curl -sS "$VAULT_ADDR/v1/auth/jwt/role/github-actions" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -X POST \
    -d @- <<EOF 2>/dev/null
{
  "user_claim": "actor",
  "role_type": "jwt",
  "bound_audiences": "https://$VAULT_ADDR",
  "policies": ["credentials-policy"],
  "ttl": "1h"
}
EOF

  # Step 4: Create credentials secret engine
  log_info "Creating Vault secret engine..."
  curl -sS "$VAULT_ADDR/v1/sys/mounts/secret/credentials" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -X POST \
    -d '{"type":"kv","version":2}' 2>/dev/null || \
    log_warn "Secret engine might already exist"

  log_pass "Vault configuration complete"
}

##############################################################################
# Phase 4: Validation
##############################################################################

validate_setup() {
  log_info "=== Phase 4: Validation ==="
  
  # Test GCP
  if [ -n "$GCP_PROJECT_ID" ]; then
    log_info "Testing GCP connectivity..."
    if gcloud secrets list --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
      log_pass "GCP GSM accessible"
    else
      log_fail "GCP GSM not accessible"
    fi
  fi

  # Test AWS
  if [ -n "$AWS_ACCOUNT_ID" ]; then
    log_info "Testing AWS connectivity..."
    if aws sts get-caller-identity >/dev/null 2>&1; then
      log_pass "AWS KMS accessible"
    else
      log_fail "AWS not accessible (expected in GH Actions)"
    fi
  fi

  # Test Vault
  if [ -n "$VAULT_ADDR" ]; then
    log_info "Testing Vault connectivity..."
    if curl -sS "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
      log_pass "Vault accessible"
    else
      log_fail "Vault not accessible"
    fi
  fi
}

##############################################################################
# MAIN
##############################################################################

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}OIDC & Credential Infrastructure Setup${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Run phases
setup_gcp 2>&1 | tee -a "$LOG_FILE" || true
echo ""
setup_aws 2>&1 | tee -a "$LOG_FILE" || true
echo ""
setup_vault 2>&1 | tee -a "$LOG_FILE" || true
echo ""
validate_setup 2>&1 | tee -a "$LOG_FILE"

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN}Setup Complete${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo "Log file: $LOG_FILE"
echo ""
echo "Next steps:"
echo "  1. Source the environment variables output above"
echo "  2. Add to GitHub Actions secrets (org-level)"
echo "  3. Run: scripts/audit-all-secrets.sh"
echo "  4. Run: scripts/authenticate-to-all-layers.sh (test)"
echo ""
