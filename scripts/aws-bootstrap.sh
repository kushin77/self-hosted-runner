#!/bin/bash

###############################################################################
# AWS-BOOTSTRAP.SH
# 
# Automated AWS Secrets Manager setup for direct-deploy credential provisioning.
# 
# Prerequisites:
#   - AWS CLI installed (aws)
#   - AWS credentials configured (aws configure OR AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)
#   - IAM permissions:
#      - secretsmanager:CreateSecret
#      - secretsmanager:PutSecretValue
#      - secretsmanager:GetSecretValue
#      - kms:Decrypt (if using customer-managed KMS key)
# 
# Usage:
#   # Configure AWS credentials first
#   aws configure
#
#   # Then provision SSH key to AWS Secrets Manager
#   bash scripts/aws-bootstrap.sh --region=us-east-1
#
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# AWS configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_SECRET_NAME="${AWS_SECRET_NAME:-runner/ssh-credentials}"
AWS_KMS_KEY_ID="${AWS_KMS_KEY_ID:-}" # Leave empty for AWS-managed encryption

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region=*)
            AWS_REGION="${1#*=}"
            ;;
        --secret-name=*)
            AWS_SECRET_NAME="${1#*=}"
            ;;
        --kms-key-id=*)
            AWS_KMS_KEY_ID="${1#*=}"
            ;;
        --help)
            grep "^# Usage:" "$0" -A 15
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            ;;
    esac
    shift
done

log_info "AWS Secrets Manager Bootstrap"
log_info "Region: $AWS_REGION"
log_info "Secret: $AWS_SECRET_NAME"

# ============================================================================
# VERIFY AWS CREDENTIALS
# ============================================================================
log_info "Verifying AWS credentials..."

if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Run: aws configure"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text)
log_ok "Authenticated to AWS account: $ACCOUNT_ID"

# ============================================================================
# CREATE OR UPDATE SECRET
# ============================================================================
log_info "Setting up AWS Secrets Manager secret..."

# Prepare secret data
SSH_KEY_PATH="${REPO_DIR}/.ssh/runner_ed25519"
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    log_error "SSH private key not found at: $SSH_KEY_PATH"
fi

SSH_KEY_CONTENT="$(cat "$SSH_KEY_PATH")"
SSH_PUB_PATH="${REPO_DIR}/.ssh/runner_ed25519.pub"
SSH_PUB_CONTENT="$(cat "$SSH_PUB_PATH")"

# Create secret JSON
SECRET_JSON=$(jq -n \
    --arg key "$SSH_KEY_CONTENT" \
    --arg pub "$SSH_PUB_CONTENT" \
    --arg user "akushnir" \
    '{
        ssh_key: $key,
        ssh_pub: $pub,
        ssh_user: $user,
        created_at: now | todate,
        runner_host: "192.168.168.42"
    }')

log_info "Creating/updating secret..."

# Check if secret exists
if aws secretsmanager describe-secret \
    --secret-id "$AWS_SECRET_NAME" \
    --region "$AWS_REGION" \
    >/dev/null 2>&1; then
    
    log_info "Secret exists; updating value..."
    aws secretsmanager put-secret-value \
        --secret-id "$AWS_SECRET_NAME" \
        --secret-string "$SECRET_JSON" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1
    log_ok "Secret updated"
else
    log_info "Creating new secret..."
    
    # Build create command
    CMD="aws secretsmanager create-secret \
        --name '$AWS_SECRET_NAME' \
        --secret-string '$SECRET_JSON' \
        --region '$AWS_REGION'"
    
    if [[ -n "$AWS_KMS_KEY_ID" ]]; then
        CMD="$CMD --kms-key-id '$AWS_KMS_KEY_ID'"
        log_info "Using customer-managed KMS key: $AWS_KMS_KEY_ID"
    fi
    
    eval "$CMD" >/dev/null 2>&1
    log_ok "Secret created"
fi

# ============================================================================
# SETUP IAM POLICY FOR WATCHER
# ============================================================================
log_info "Creating IAM policy for watcher access..."

POLICY_NAME="runner-deploy-watcher-policy"
POLICY_DOC=$(cat <<'POLICY_EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:runner/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "*"
    }
  ]
}
POLICY_EOF
)

# Try to create policy (or use existing)
if ! aws iam get-policy --policy-name "$POLICY_NAME" >/dev/null 2>&1; then
    log_info "Creating IAM policy: $POLICY_NAME..."
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "$POLICY_DOC" \
        >/dev/null 2>&1 || true
    log_ok "IAM policy created"
else
    log_ok "IAM policy already exists: $POLICY_NAME"
fi

# ============================================================================
# VERIFY SECRET
# ============================================================================
log_info "Verifying secret access..."

if aws secretsmanager get-secret-value \
    --secret-id "$AWS_SECRET_NAME" \
    --region "$AWS_REGION" \
    >/dev/null 2>&1; then
    log_ok "Secret is accessible"
else
    log_warn "Could not verify secret; check permissions"
fi

# ============================================================================
# OUTPUT CONFIGURATION
# ============================================================================
log_ok "=========================================="
log_ok "AWS Bootstrap Complete"
log_ok "=========================================="
echo ""
echo "Export these variables to use AWS:"
echo "  export AWS_REGION='$AWS_REGION'"
echo "  export AWS_SECRET_NAME='$AWS_SECRET_NAME'"
echo ""
echo "Watcher will auto-detect AWS credentials from:"
echo "  1. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars"
echo "  2. ~/.aws/credentials file"
echo "  3. IAM instance role (if running on EC2)"
echo ""
echo "Next step: Update watcher to use AWS"
echo "  export CRED_PROVIDER=aws"
echo "  systemctl restart wait-and-deploy.service"
echo ""
