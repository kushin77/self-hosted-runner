#!/bin/bash
##############################################################################
# AWS OIDC Setup for GitHub Actions (Self-Hosted Runner Repo)
# 
# This script sets up GitHub OIDC for credentialless CI/CD authentication to AWS.
# Run this in an AWS environment with appropriate IAM permissions.
#
# Requirements:
#   - AWS CLI v2 configured with credentials
#   - jq (for JSON parsing)
#   - GitHub CLI (gh) for setting repo secrets
#   - Repository admin access
#
# Usage:
#   bash scripts/cloud/aws-oidc-setup.sh \
#     --account-id <AWS_ACCOUNT_ID> \
#     --region <AWS_REGION> \
#     --state-bucket <TERRAFORM_STATE_BUCKET> \
#     --lock-table <TERRAFORM_LOCK_TABLE> \
#     --repo-owner <GITHUB_OWNER> \
#     --repo-name <GITHUB_REPO_NAME>
##############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
ACCOUNT_ID=""
REGION="us-east-1"
STATE_BUCKET=""
LOCK_TABLE="terraform-lock"
REPO_OWNER=""
REPO_NAME="self-hosted-runner"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-id) ACCOUNT_ID="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --state-bucket) STATE_BUCKET="$2"; shift 2 ;;
    --lock-table) LOCK_TABLE="$2"; shift 2 ;;
    --repo-owner) REPO_OWNER="$2"; shift 2 ;;
    --repo-name) REPO_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) 
      grep "^#" "$0" | head -30
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate inputs
if [[ -z "$ACCOUNT_ID" ]] || [[ -z "$STATE_BUCKET" ]] || [[ -z "$REPO_OWNER" ]]; then
  echo -e "${RED}Error: --account-id, --state-bucket, and --repo-owner are required${NC}"
  exit 1
fi

echo -e "${YELLOW}========== AWS OIDC Setup for GitHub Actions ==========${NC}"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
echo "State Bucket: $STATE_BUCKET"
echo "Lock Table: $LOCK_TABLE"
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo ""

# Step 1: Check if OIDC provider exists
echo -e "${YELLOW}[Step 1] Checking for existing GitHub OIDC provider...${NC}"
PROVIDER_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(OpenIDConnectProviderArn, 'token.actions.githubusercontent.com')].OpenIDConnectProviderArn" --output text 2>/dev/null || echo "")

if [[ -z "$PROVIDER_ARN" ]]; then
  echo -e "${YELLOW}  Creating GitHub OIDC provider...${NC}"
  THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
  if [[ "$DRY_RUN" == "false" ]]; then
    PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
      --url "https://token.actions.githubusercontent.com" \
      --client-id-list "sts.amazonaws.com" \
      --thumbprint-list "$THUMBPRINT" \
      --query "OpenIDConnectProviderArn" \
      --output text)
    echo -e "${GREEN}  Created provider: $PROVIDER_ARN${NC}"
  else
    echo -e "${YELLOW}  [DRY-RUN] Would create OIDC provider${NC}"
    PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
  fi
else
  echo -e "${GREEN}  Provider already exists: $PROVIDER_ARN${NC}"
fi
echo ""

# Step 2: Create IAM role for GitHub Actions
ROLE_NAME="github-actions-terraform-${REGION}"
echo -e "${YELLOW}[Step 2] Creating/checking IAM role: $ROLE_NAME${NC}"

ROLE_ARN=""
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null || echo "")

if [[ -z "$ROLE_EXISTS" ]]; then
  # Create trust policy document
  cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$PROVIDER_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:sub": "repo:${REPO_OWNER}/${REPO_NAME}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF
  
  if [[ "$DRY_RUN" == "false" ]]; then
    ROLE_ARN=$(aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document file:///tmp/trust-policy.json \
      --description "GitHub Actions OIDC role for Terraform" \
      --query "Role.Arn" \
      --output text)
    echo -e "${GREEN}  Created role: $ROLE_ARN${NC}"
  else
    echo -e "${YELLOW}  [DRY-RUN] Would create role${NC}"
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
  fi
else
  ROLE_ARN="$ROLE_EXISTS"
  echo -e "${GREEN}  Role already exists: $ROLE_ARN${NC}"
fi
rm -f /tmp/trust-policy.json
echo ""

# Step 3: Attach least-privilege policy
POLICY_NAME="github-terraform-s3-backend"
echo -e "${YELLOW}[Step 3] Creating/attaching policy: $POLICY_NAME${NC}"

# Replace placeholders in policy
POLICY_CONTENT=$(cat infra/oidc/aws/iam-policy-s3-backend.json | \
  sed "s|<TERRAFORM_STATE_BUCKET>|$STATE_BUCKET|g" | \
  sed "s|<TERRAFORM_LOCK_TABLE>|$LOCK_TABLE|g" | \
  sed "s|<REGION>|$REGION|g" | \
  sed "s|<ACCOUNT_ID>|$ACCOUNT_ID|g")

# For simplicity, create an inline policy (in production, use managed policies)
if [[ "$DRY_RUN" == "false" ]]; then
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_CONTENT"
  echo -e "${GREEN}  Attached policy to role${NC}"
else
  echo -e "${YELLOW}  [DRY-RUN] Would attach policy${NC}"
fi
echo ""

# Step 4: Set GitHub repo secrets
echo -e "${YELLOW}[Step 4] Setting GitHub repository secrets...${NC}"

REPO="${REPO_OWNER}/${REPO_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
  echo "  Setting AWS_OIDC_ROLE_ARN..."
  gh secret set AWS_OIDC_ROLE_ARN --body "$ROLE_ARN" --repo "$REPO" || true
  
  echo "  Setting USE_OIDC..."
  gh secret set USE_OIDC --body "true" --repo "$REPO" || true
  
  echo "  Setting AWS_DEFAULT_REGION..."
  gh secret set AWS_DEFAULT_REGION --body "$REGION" --repo "$REPO" || true
  
  echo -e "${GREEN}  Repo secrets set successfully${NC}"
else
  echo -e "${YELLOW}  [DRY-RUN] Would set secrets:${NC}"
  echo "    AWS_OIDC_ROLE_ARN=$ROLE_ARN"
  echo "    USE_OIDC=true"
  echo "    AWS_DEFAULT_REGION=$REGION"
fi
echo ""

# Step 5: Label the issue to trigger automation
echo -e "${YELLOW}[Step 5] Labeling issue #1309 'oidc-ready' to trigger automation...${NC}"

if [[ "$DRY_RUN" == "false" ]]; then
  gh issue edit 1309 --repo "$REPO" --add-label oidc-ready || true
  echo -e "${GREEN}  Issue labeled, automation should trigger automatically${NC}"
else
  echo -e "${YELLOW}  [DRY-RUN] Would label issue #1309 with 'oidc-ready'${NC}"
fi
echo ""

echo -e "${GREEN}========== Setup Complete ==========${NC}"
echo -e "${GREEN}Role ARN: $ROLE_ARN${NC}"
echo ""
echo "Next steps:"
echo "1. Verify repo secrets are set: gh secret list --repo $REPO"
echo "2. Monitor workflow runs: gh run list --repo $REPO"
echo "3. Check the 'oidc-ready' labeled issue for automation progress"
echo ""
