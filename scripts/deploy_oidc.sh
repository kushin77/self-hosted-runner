#!/usr/bin/env bash
set -euo pipefail

# Helper script to apply the Terraform module that provisions:
# - GitHub OIDC provider + role restricted to repo/branch
# - KMS key + alias
# - IAM policy attachment
# After apply it sets the repository secret `AWS_ROLE_TO_ASSUME` with the created role ARN.

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "Please run from a checked-out git repo or set GITHUB_REPOSITORY (owner/repo)"
  exit 1
fi

if [ -z "${AWS_REGION:-}" ]; then
  AWS_REGION="us-east-1"
fi

if [ $# -lt 2 ]; then
  echo "Usage: $0 <github-owner> <github-repo> [branch]"
  exit 1
fi

GITHUB_OWNER="$1"
GITHUB_REPO="$2"
BRANCH="${3:-main}"

cd infra/oidc

export TF_VAR_github_owner="$GITHUB_OWNER"
export TF_VAR_github_repo="$GITHUB_REPO"
export TF_VAR_branch="$BRANCH"
export TF_VAR_aws_region="$AWS_REGION"

terraform init
terraform apply -auto-approve

ROLE_ARN=$(terraform output -raw role_arn)

if [ -z "$ROLE_ARN" ]; then
  echo "Failed to obtain role ARN from Terraform outputs" >&2
  exit 1
fi

echo "Setting GitHub repository secret AWS_ROLE_TO_ASSUME to role ARN: $ROLE_ARN"

# Requires `gh` CLI auth with repo:workflow permission then set secret
echo -n "$ROLE_ARN" | gh secret set AWS_ROLE_TO_ASSUME --repo "$GITHUB_OWNER/$GITHUB_REPO" --body -

echo "Done. Please verify workflow runs now have access to assume the role." 
