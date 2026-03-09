#!/bin/bash

###############################################################################
# AWS OIDC Provider Setup for GitHub Actions
# 
# This script sets up OIDC authentication to allow GitHub Actions to assume
# an IAM role without long-lived access keys.
#
# Requirements:
#   - aws CLI installed and configured
#   - Proper AWS IAM permissions (CreateOpenIDConnectProvider, CreateRole, etc)
#   - AWS_REGION environment variable set (or default: us-east-1)
#
# Output:
#   - OIDC Provider ARN
#   - IAM Role ARN (AWS_ROLE_TO_ASSUME)
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

###############################################################################
# CONFIGURATION
###############################################################################

AWS_REGION="${AWS_REGION:=us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:=}"
GITHUB_REPO="${GITHUB_REPO:=kushin77/self-hosted-runner}"
OIDC_PROVIDER_URL="https://token.actions.githubusercontent.com"
ROLE_NAME="${ROLE_NAME:=github-actions-runner}"

# Output file for credentials
OUTPUT_FILE="${OUTPUT_FILE:=/tmp/aws-oidc-credentials.txt}"

###############################################################################
# VALIDATION
###############################################################################

log_info "Starting AWS OIDC Provider setup..."
echo ""

# Check if aws CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

log_success "AWS CLI found"

# Get AWS Account ID
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    log_info "Retrieving AWS Account ID..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    log_error "Failed to retrieve AWS Account ID"
    exit 1
fi

log_success "AWS Account ID: $AWS_ACCOUNT_ID"

###############################################################################
# STEP 1: Check if OIDC Provider Already Exists
###############################################################################

log_info ""
log_info "Step 1: Checking for existing OIDC provider..."

OIDC_PROVIDER_ARN=""

# List all OIDC providers
PROVIDERS=$(aws iam list-open-id-connect-providers --region "$AWS_REGION" 2>/dev/null || echo "")

if echo "$PROVIDERS" | grep -q "token.actions.githubusercontent.com"; then
    log_info "Found existing GitHub OIDC provider"
    
    # Get the full ARN
    OIDC_PROVIDER_ARN=$(echo "$PROVIDERS" | grep -o 'arn:aws:iam::[0-9]*:oidc-provider/token.actions.githubusercontent.com' | head -1)
    
    if [[ -n "$OIDC_PROVIDER_ARN" ]]; then
        log_success "Existing OIDC provider found: $OIDC_PROVIDER_ARN"
    fi
fi

# If not found, create it
if [[ -z "$OIDC_PROVIDER_ARN" ]]; then
    log_info "Creating OIDC provider for GitHub Actions..."
    
    # Get GitHub's OIDC certificate thumbprint
    GITHUB_THUMBPRINT=$(echo | openssl s_client -servername token.actions.githubusercontent.com \
        -connect token.actions.githubusercontent.com:443 2>/dev/null | \
        openssl x509 -noout -fingerprint -sha1 | cut -d'=' -f2 | tr -d ':')
    
    if [[ -z "$GITHUB_THUMBPRINT" ]]; then
        log_error "Failed to retrieve GitHub OIDC certificate thumbprint"
        exit 1
    fi
    
    log_info "GitHub thumbprint: $GITHUB_THUMBPRINT"
    
    # Create OIDC provider
    OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
        --url "$OIDC_PROVIDER_URL" \
        --thumbprint-list "$GITHUB_THUMBPRINT" \
        --client-id-list "sts.amazonaws.com" "actions.github.com" \
        --region "$AWS_REGION" \
        --query 'OpenIDConnectProviderArn' \
        --output text)
    
    if [[ -z "$OIDC_PROVIDER_ARN" ]]; then
        log_error "Failed to create OIDC provider"
        exit 1
    fi
    
    log_success "OIDC provider created: $OIDC_PROVIDER_ARN"
fi

###############################################################################
# STEP 2: Create IAM Role
###############################################################################

log_info ""
log_info "Step 2: Creating/verifying IAM role..."

# Check if role already exists
ROLE_ARN=""
if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    log_warning "Role $ROLE_NAME already exists, skipping creation"
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
else
    # Create trust policy
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)
    
    log_info "Creating IAM role with trust policy..."
    
    ROLE_ARN=$(aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --query 'Role.Arn' \
        --output text)
    
    log_success "Role created: $ROLE_ARN"
fi

###############################################################################
# STEP 3: Create and Attach Inline Policy
###############################################################################

log_info ""
log_info "Step 3: Creating inline policy for secrets and KMS access..."

# Extract role name from ARN if needed
ROLE_NAME_FROM_ARN=$(echo "$ROLE_ARN" | rev | cut -d'/' -f1 | rev)

POLICY_NAME="github-actions-secrets-kms"
POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:github/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.${AWS_REGION}.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)

# Check if policy exists
if aws iam get-role-policy --role-name "$ROLE_NAME_FROM_ARN" --policy-name "$POLICY_NAME" 2>/dev/null; then
    log_warning "Policy $POLICY_NAME already exists, updating..."
    aws iam put-role-policy \
        --role-name "$ROLE_NAME_FROM_ARN" \
        --policy-name "$POLICY_NAME" \
        --policy-document "$POLICY_DOCUMENT"
else
    log_info "Adding inline policy to role..."
    aws iam put-role-policy \
        --role-name "$ROLE_NAME_FROM_ARN" \
        --policy-name "$POLICY_NAME" \
        --policy-document "$POLICY_DOCUMENT"
fi

log_success "Policy attached to role"

###############################################################################
# STEP 4: Create KMS Key (Optional but Recommended)
###############################################################################

log_info ""
log_info "Step 4: Verifying/creating KMS key..."

KMS_KEY_ID=""
KMS_KEY_ALIAS="alias/github-secrets"

# Check if key alias exists
if aws kms describe-key --key-id "$KMS_KEY_ALIAS" --region "$AWS_REGION" 2>/dev/null; then
    log_info "KMS key alias $KMS_KEY_ALIAS already exists"
    KMS_KEY_ID=$(aws kms describe-key --key-id "$KMS_KEY_ALIAS" --region "$AWS_REGION" --query 'KeyMetadata.KeyId' --output text)
else
    log_info "Creating KMS key for secrets encryption..."
    
    KMS_KEY_ID=$(aws kms create-key \
        --description "GitHub Actions Secrets Encryption" \
        --region "$AWS_REGION" \
        --query 'KeyMetadata.KeyId' \
        --output text)
    
    log_success "KMS key created: $KMS_KEY_ID"
    
    # Create alias
    aws kms create-alias \
        --alias-name "$KMS_KEY_ALIAS" \
        --target-key-id "$KMS_KEY_ID" \
        --region "$AWS_REGION"
    
    log_success "KMS key alias created: $KMS_KEY_ALIAS"
fi

# Grant role permission to use KMS key
log_info "Granting role permissions to use KMS key..."

aws kms grant-tokens \
    --key-id "$KMS_KEY_ID" \
    --role-arn "$ROLE_ARN" \
    --region "$AWS_REGION" 2>/dev/null || log_warning "Grant failed (may need manual setup)"

###############################################################################
# STEP 5: Create Secrets Manager Secret (Example)
###############################################################################

log_info ""
log_info "Step 5: Creating example Secrets Manager secret..."

SECRET_NAME="github/docker-hub-test"

# Check if secret exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" 2>/dev/null; then
    log_warning "Secret $SECRET_NAME already exists"
else
    log_info "Creating example secret..."
    
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --secret-string "test-value-replace-me" \
        --region "$AWS_REGION" \
        --kms-key-id "$KMS_KEY_ALIAS" || true
    
    log_success "Example secret created (update with real value later)"
fi

###############################################################################
# STEP 6: Save Credentials to File
###############################################################################

log_info ""
log_info "Step 6: Saving credentials..."

cat > "$OUTPUT_FILE" <<EOF
###############################################################################
# AWS OIDC Provider - GitHub Actions Setup
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
###############################################################################

# 1. AWS Account Information
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}

# 2. OIDC Provider
AWS_OIDC_PROVIDER_ARN=${OIDC_PROVIDER_ARN}
OIDC_PROVIDER_URL=${OIDC_PROVIDER_URL}

# 3. IAM Role
# ⭐ SAVE THIS TO GITHUB SECRET: AWS_ROLE_TO_ASSUME
AWS_ROLE_TO_ASSUME=${ROLE_ARN}

# 4. KMS Key
AWS_KMS_KEY_ID=${KMS_KEY_ID}
AWS_KMS_KEY_ALIAS=alias/github-secrets

# 5. GitHub Configuration
GITHUB_REPO=${GITHUB_REPO}

###############################################################################
# How to use in GitHub Actions workflows:
###############################################################################

# In your workflow, add this step to authenticate:

permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: \${{ secrets.AWS_ROLE_TO_ASSUME }}
      aws-region: us-east-1
  
  - name: Retrieve secret from AWS Secrets Manager
    run: |
      aws secretsmanager get-secret-value \
        --secret-id github/docker-hub-password \
        --query SecretString \
        --output text

###############################################################################
# Create these GitHub Secrets:
###############################################################################

1. AWS_ROLE_TO_ASSUME = ${ROLE_ARN}
2. AWS_REGION = ${AWS_REGION}
3. AWS_KMS_KEY_ID = ${KMS_KEY_ID}

###############################################################################
# Verify Setup:
###############################################################################

# Check role trust policy:
aws iam get-role --role-name ${ROLE_NAME_FROM_ARN}

# Check role inline policy:
aws iam get-role-policy --role-name ${ROLE_NAME_FROM_ARN} --policy-name github-actions-secrets-kms

# List OIDC providers:
aws iam list-open-id-connect-providers

# Describe KMS key:
aws kms describe-key --key-id ${KMS_KEY_ID}

EOF

log_success "Credentials saved to $OUTPUT_FILE"

###############################################################################
# SUMMARY
###############################################################################

log_info ""
log_info "═══════════════════════════════════════════════════════════════════════"
log_success "AWS OIDC Provider Setup Complete!"
log_info "═══════════════════════════════════════════════════════════════════════"
echo ""

echo "✅ OIDC Provider: ${OIDC_PROVIDER_ARN}"
echo "✅ IAM Role: ${ROLE_ARN}"
echo "✅ KMS Key: ${KMS_KEY_ID}"
echo ""

echo "📋 Create these GitHub Secrets:"
echo "   1. AWS_ROLE_TO_ASSUME = ${ROLE_ARN}"
echo "   2. AWS_REGION = ${AWS_REGION}"
echo "   3. AWS_KMS_KEY_ID = ${KMS_KEY_ID}"
echo ""

echo "📝 Full configuration saved to: $OUTPUT_FILE"
echo ""

echo "🚀 Next steps:"
echo "   1. Copy the AWS_ROLE_TO_ASSUME value above"
echo "   2. Add to GitHub repository secrets:"
echo "      gh secret set AWS_ROLE_TO_ASSUME --body '${ROLE_ARN}'"
echo "   3. Add AWS_REGION and AWS_KMS_KEY_ID to secrets"
echo "   4. Create AWS Secrets Manager secrets (use github/ prefix)"
echo "   5. Test with: .github/workflows/test-credential-helpers.yml"
echo ""

log_success "Setup complete!"
