# AWS OIDC Setup for Issue #231 Auto-Apply

## Overview
The Issue #231 Auto-Apply workflow supports two credential sources:
1. **GCP Secret Manager (GSM)** - for static AWS credentials (fallback)
2. **AWS OpenID Connect (OIDC)** - ephemeral, short-lived credentials (preferred)

## Why AWS OIDC?
- ✅ **Ephemeral credentials**: Short-lived tokens that auto-expire
- ✅ **No static secrets**: No AWS_ACCESS_KEY_ID stored in repositories
- ✅ **Audit-friendly**: Full traceability via IAM logs
- ✅ **GitOps best practice**: Recommended by AWS and GitHub

## Required Setup

### 1. Create AWS IAM Role for GitHub Actions

```bash
# Set variables
AWS_ACCOUNT_ID="your-aws-account-id"
GITHUB_ORG="kushin77"
GITHUB_REPO="self-hosted-runner"

# Create trust policy JSON
cat > /tmp/trust-policy.json <<EOF
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
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name github-actions-terraform-role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "Role for GitHub Actions to run Terraform"
```

### 2. Create IAM Policy for Terraform Operations

```bash
# Create policy JSON
cat > /tmp/terraform-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "rds:*",
        "s3:*",
        "iam:*",
        "cloudformation:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach policy to role
aws iam put-role-policy \
  --role-name github-actions-terraform-role \
  --policy-name terraform-permissions \
  --policy-document file:///tmp/terraform-policy.json
```

### 3. Add GitHub Secret

Store the IAM role ARN in GitHub repository secrets:

```bash
# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name github-actions-terraform-role --query 'Role.Arn' --output text)

# Store in GitHub (you'll do this via GitHub UI)
# Secret name: AWS_ROLE_TO_ASSUME
# Secret value: $ROLE_ARN
```

**GitHub UI Steps:**
1. Go to your repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `AWS_ROLE_TO_ASSUME`
4. Value: Your IAM role ARN (e.g., `arn:aws:iam::123456789012:role/github-actions-terraform-role`)
5. Click "Add secret"

### 4. Verify OIDC Provider (One-time setup)

```bash
# Check if GitHub OIDC provider exists
aws iam list-open-id-connect-providers | grep -i github

# If not found, create it:
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

## Fallback: GSM Credentials (Static)

If OIDC is not available, the workflow will use static AWS credentials from GCP Secret Manager:

```bash
# Store credentials in GSM
echo -n "YOUR_AWS_ACCESS_KEY" | gcloud secrets create aws-access-key-id --data-file=-
echo -n "YOUR_AWS_SECRET_KEY" | gcloud secrets create aws-secret-access-key --data-file=-
echo -n "us-east-1" | gcloud secrets create aws-region --data-file=-
```

**⚠️ Warning**: Static credentials should only be used as a fallback. Prefer OIDC.

## Workflow Behavior

The auto-apply workflow will:
1. Check for AWS credentials in GSM (static)
2. If not found, attempt AWS OIDC authentication
3. If credentials available → run `terraform apply`
4. If no credentials → run `terraform plan` (dry-run only)
5. Post results and auto-close issues on success

## Testing

```bash
# Dispatch the workflow manually
gh workflow run issue-231-auto-apply.yml --repo kushin77/self-hosted-runner

# Monitor the run
gh run list --repo kushin77/self-hosted-runner --workflow issue-231-auto-apply.yml --limit 1

# View logs
gh run view <RUN_ID> --repo kushin77/self-hosted-runner --log
```

## Security Best Practices

✅ **Do:**
- Use AWS OIDC for automation
- Rotate IAM roles periodically
- Audit IAM logs for access patterns
- Limit scope of IAM permissions
- Monitor workflow execution logs

❌ **Don't:**
- Store AWS credentials in environment variables
- Commit credentials to git
- Use overly permissive IAM policies
- Share AWS account credentials across projects

## References
- [AWS OIDC Provider Setup](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub OIDC Token](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Terraform AWS Provider Auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#using-environment-variables)
