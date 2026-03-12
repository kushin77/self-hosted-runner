# AWS OIDC Federation Implementation

> **Status**: ✅ Production Ready  
> **Phase**: Tier 2 - AWS Credential Elimination  
> **Properties**: Immutable • Idempotent • Ephemeral • No-Ops • Hands-Off

## Overview

This document describes the implementation of **AWS OIDC Federation** for GitHub Actions, enabling secure authentication without long-lived AWS Access Keys. This is part of the broader credential elimination strategy for the self-hosted runner infrastructure.

### What is OIDC Federation?

OpenID Connect (OIDC) Federation establishes a **trust relationship** between GitHub and AWS, allowing GitHub Actions workflows to:

1. **Generate OIDC tokens** - GitHub issues cryptographically signed tokens scoped to a specific workflow
2. **Exchange tokens for credentials** - AWS exchanges the OIDC token for temporary STS credentials
3. **Assume IAM role** - Temporary credentials are used to call AWS APIs

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **No Long-Lived Keys** | AWS credentials never stored in GitHub Secrets |
| **Token Expiration** | STS credentials automatically expire (1 hour) |
| **Scope Limiting** | Tokens scoped to repository, branch, and workflow |
| **Full Audit Trail** | All credential usage logged to AWS CloudTrail |
| **Easy Revocation** | Disable OIDC provider to revoke all GitHub access |
| **Cross-Account Support** | Support multi-account deployments via role chaining |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Actions Workflow                                         │
├─────────────────────────────────────────────────────────────────┤
│ 1. Workflow starts                                              │
│ 2. GitHub generates OIDC token (cryptographically signed)       │
│ 3. Token includes: repository, branch, commit, timestamp        │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ AWS                                                             │
├─────────────────────────────────────────────────────────────────┤
│ 1. AWS OIDC Provider (trusts GitHub)                            │
│    - URL: https://token.actions.githubusercontent.com           │
│    - Thumbprint: verified from GitHub's JWK Set                │
│                                                                 │
│ 2. GitHub OIDC Role                                             │
│    - Trust policy references OIDC Provider                      │
│    - Condition: token.actions.githubusercontent.com:aud         │
│    - Subject: repo:kushin77/self-hosted-runner:*               │
│                                                                 │
│ 3. Token Exchange                                              │
│    - Workflow calls: aws-actions/configure-aws-credentials     │
│    - STS AssumeRoleWithWebIdentity API called                  │
│    - AWS validates OIDC token signature                        │
│    - Returns temporary STS credentials                         │
│                                                                 │
│ 4. Temporary Credentials                                        │
│    - AccessKeyId (starts with ASIA...)                         │
│    - SecretAccessKey                                           │
│    - SessionToken (proof they're temporary)                    │
│    - Expiration: 1 hour (default)                              │
│                                                                 │
│ 5. CloudTrail Logging                                           │
│    - All API calls logged with OIDC principal                  │
│    - Full audit trail maintained                               │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Workflow Operations                                             │
├─────────────────────────────────────────────────────────────────┤
│ - Deploy to AWS                                                │
│ - Push to ECR                                                  │
│ - Update CloudFormation                                        │
│ - All calls authenticated via temporary credentials           │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation files

### 1. Terraform Module: `infra/terraform/modules/aws_oidc_federation/`

**main.tf**
- Creates OIDC Provider resource
- Creates IAM Role for GitHub
- Defines Trust Policy
- Attaches minimal permissions

**variables.tf**
- AWS Account ID
- AWS Region
- GitHub Repository
- Role name
- Tags

**outputs.tf** (in main.tf)
- OIDC Provider ARN
- OIDC Role ARN
- OIDC Role Name

### 2. Deployment Script: `scripts/deploy-aws-oidc-federation.sh`

**Purpose**: Direct deployment to AWS without GitHub Actions

**Properties**:
- ✅ Immutable: All operations logged to JSONL audit trail
- ✅ Idempotent: Terraform rerun-safe, no overwrites
- ✅ Ephemeral: STS credentials obtained fresh each run
- ✅ No-Ops: Single command deployment
- ✅ Hands-Off: Commits directly to main

**Usage**:
```bash
export AWS_ACCOUNT_ID="123456789012"
export GCP_PROJECT_ID="my-gcp-project"
./scripts/deploy-aws-oidc-federation.sh
```

### 3. Test Script: `scripts/test-aws-oidc-federation.sh`

**Comprehensive test suite**:
- ✅ AWS CLI configured
- ✅ OIDC Provider exists
- ✅ OIDC Role exists
- ✅ Trust policy configured
- ✅ IAM policies attached
- ✅ Token exchange readiness
- ✅ Terraform state valid
- ✅ Required permissions present
- ✅ Security isolation
- ✅ Audit log exists

**Usage**:
```bash
./scripts/test-aws-oidc-federation.sh
```

### 4. GitHub Actions Workflow: `.github/workflows/oidc-deployment.yml`

**Demonstrates**:
- Test OIDC readiness
- Deploy OIDC infrastructure
- Verify functionality
- Generate deployment summary

**Automatically runs** on:
- Pushes to main/governance/release branches
- Changes to terraform module or scripts
- Manual workflow dispatch

## Deployment Guide

### Phase 1: Pre-Deployment

Verify AWS account access and environment setup:

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check GitHub CLI
gh --version

# Check Terraform
terraform --version
```

### Phase 2: Deploy OIDC Infrastructure

**Option A: Direct Deployment (Automated)**
```bash
cd /path/to/self-hosted-runner

# Set environment
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"
export GCP_PROJECT_ID="my-gcp-project"

# Deploy
./scripts/deploy-aws-oidc-federation.sh

# Check results
cat logs/aws-oidc-deployment-*.jsonl
```

**Option B: GitHub Actions (Manual)**
- Push changes to main branch
- GitHub workflow automatically deploys
- Review #2159 for deployment details

### Phase 3: Verify Deployment

```bash
# Test infrastructure
./scripts/test-aws-oidc-federation.sh

# Expected output
# ✅ AWS CLI configured
# ✅ OIDC Provider Exists
# ✅ OIDC Role Exists
# ✅ OIDC Role Trust Policy
# [etc.]
```

### Phase 4: Update Workflows

**Update existing workflows to use OIDC**:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write    # Required for OIDC
      contents: read
    steps:
      - name: Assume AWS Role via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-oidc-role
          aws-region: us-east-1
          audience: sts.amazonaws.com
      
      - name: Deploy to AWS
        run: |
          aws s3 ls
          # No AWS_ACCESS_KEY_ID needed!
```

### Phase 5: Eliminate Long-Lived Keys

```bash
# List current AWS keys
aws iam list-access-keys --user-name github-actions

# Delete old keys once workflows migrated
aws iam delete-access-key --access-key-id  AKIA...

# Verify in GitHub Secrets
# - Delete AWS_ACCESS_KEY_ID
# - Delete AWS_SECRET_ACCESS_KEY
```

## Security Architecture

### Trust Policy

The OIDC role trust policy enforces multiple conditions:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:ref:refs/heads/main"
    }
  }
}
```

**Security Controls**:
- Only GitHub can issue tokens (`federated` principal)
- Only correct audience can use tokens
- Only specific repository can assume role
- Only specific branches (main, governance/*, release/*) can use role
- Tokens automatically expire after 1 hour

### IAM Policies (Least Privilege)

Role has minimal permissions:

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:123456789012:key/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:github-actions/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole"
      ],
      "Resource": "arn:aws:iam::123456789012:role/github-*"
    }
  ]
}
```

### Audit Trail

All OIDC credential usage is logged:

**AWS CloudTrail**:
```json
{
  "eventName": "AssumeRoleWithWebIdentity",
  "principal": {
    "AWS": "arn:aws:iam::123456789012:role/github-oidc-role",
    "principalId": "AIDAI..."
  },
  "sourceIPAddress": "140.82.113.0",  // GitHub Actions IP
  "requestParameters": {
    "roleArn": "arn:aws:iam::123456789012:role/github-oidc-role"
  }
}
```

**GitHub Audit Log**:
- Workflow run ID
- Actor requesting credentials
- Repository and branch
- Timestamp

## Troubleshooting

### Issue: "No OIDC Provider Found"

```bash
# Check provider exists
aws iam list-open-id-connect-providers

# If empty, deploy the module:
cd infra/terraform/modules/aws_oidc_federation
terraform apply
```

### Issue: "AssumeRoleWithWebIdentity Failed"

Check the trust policy:
```bash
aws iam get-role --role-name github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument' | jq .
```

Verify conditions:
- `aud` must be `sts.amazonaws.com`
- `sub` must match repository pattern
- Federated principal must be OIDC provider ARN

### Issue: "Access Denied" When Running AWS Commands

Check attached policies:
```bash
aws iam list-attached-role-policies \
  --role-name github-oidc-role

aws iam list-role-policies \
  --role-name github-oidc-role
```

Add missing permissions:
```bash
aws iam put-role-policy \
  --role-name github-oidc-role \
  --policy-name additional-permissions \
  --policy-document file://policy.json
```

### Issue: "Insufficient Permissions for Principal Making the Call"

The OIDC role itself doesn't have permissions. Check:
1. Policies attached to the role
2. Trust policy allows the token's principal
3. Resource policies on S3, KMS, etc. allow the role

## Best Practices

### 1. Rotate OIDC Provider Thumbprint Quarterly

```bash
# Verify current thumbprint
curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration \
  | jq .jwks_uri

# Extract certificate and compute thumbprint
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Use Role Chaining for Cross-Account Access

```yaml
- name: Assume Cross-Account Role
  run: |
    # First assume the GitHub role (automatic)
    # Then chain to cross-account role
    ROLE_SESSION=$(aws sts assume-role \
      --role-arn arn:aws:iam::987654321098:role/cross-account-role \
      --role-session-name github-actions)
    
    export AWS_ACCESS_KEY_ID=$(echo $ROLE_SESSION | jq -r .Credentials.AccessKeyId)
    # etc.
```

### 3. Monitor OIDC Usage

```bash
# CloudTrail query to monitor OIDC usage
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 \
  --region us-east-1
```

### 4. Regularly Audit Permissions

```bash
# Check policy effectiveness
aws accessanalyzer validate-policy \
  --policy-document file://oidc-policy.json \
  --policy-type IDENTITY_POLICY

# Findings indicate overly permissive rules
```

### 5. Use Separate Roles for Different Workflows

```yaml
# Role per workflow type
deploy-role:        # For deployments
  Permissions: cloudformation:*, s3:*, ecr:*
  
test-role:          # For testing
  Permissions: s3:GetObject, logs:CreateLogStream…

security-audit-role: # For security scanning
  Permissions: ec2:Describe*, iam:Get*, s3:List*
```

## Migration Path

### Step 1: Deploy OIDC Infrastructure ✅
```bash
./scripts/deploy-aws-oidc-federation.sh
```

### Step 2: Create Test Workflow
Deploy test workflow to verify OIDC works

### Step 3: Update Existing Workflows
Replace `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` secrets with OIDC

### Step 4: Verify All Workflows
Test all CI/CD workflows with OIDC role

### Step 5: Rotate Long-Lived Keys
Delete AWS_ACCESS_KEY_ID from GitHub Secrets and AWS IAM

### Step 6: Remove Secrets from GitHub
Verify all workflows use OIDC, remove remaining secrets

### Step 7: Archive Old Keys
Keep deletion records for audit purposes

## Immutable Records

All OIDC deployments are recorded in audit logs:

```bash
# View deployment logs
ls logs/aws-oidc-deployment-*.jsonl
cat logs/aws-oidc-deployment-2026-03-11T14:30:00Z.jsonl

# View test results
ls logs/aws-oidc-test-*.jsonl
cat logs/aws-oidc-test-2026-03-11T14:31:00Z.jsonl

# View GitHub issue #2159
gh issue view 2159 --repo=kushin77/self-hosted-runner
```

## Compliance & Governance

This implementation satisfies:

- ✅ **AWS Security Best Practices**: No stored AWS access keys
- ✅ **SOC 2**: Full audit trail via CloudTrail and GitHub
- ✅ **GDPR**: No sensitive credentials stored in GitHub
- ✅ **CIS AWS Foundations**: Short-lived credentials configuration
- ✅ **GitHub Enterprise**: OIDC Federation recommended for production

## References

- [GitHub: Using OpenID Connect with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS: Using OIDC Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS: Assume role with web identity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [GitHub: AWS Actions](https://github.com/aws-actions)

## Support

For issues:
1. Check CloudTrail logs: `aws cloudtrail lookup-events`
2. Review OIDC role configuration
3. Run test suite: `./scripts/test-aws-oidc-federation.sh`
4. File issue on GitHub: https://github.com/kushin77/self-hosted-runner/issues/2159

---

**Last Updated**: 2026-03-11  
**Deployment Status**: ✅ Production Ready  
**Next Review**: 2026-06-11
