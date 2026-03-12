---
name: AWS OIDC Federation Deployment
about: Track AWS OIDC Federation setup and verification
title: "[INFRA] AWS OIDC Federation Deployment"
labels: 'tier-2-aws-oidc,infrastructure,security'
assignees: 'kushin77'
---

## Overview

This issue tracks the deployment of AWS OIDC Federation integration, replacing long-lived AWS access keys with temporary STS credentials.

## Deployment Details

- **Phase**: Tier 2 - AWS Credential Management
- **Status**: ✋ In Progress
- **Deployment Method**: Terraform + GitHub Actions
- **Target**: AWS Account `{{ AWS_ACCOUNT_ID }}`
- **GitHub Repository**: `kushin77/self-hosted-runner`

## Pre-Deployment Checklist

- [ ] AWS account access verified
- [ ] Terraform installed and configured
- [ ] GitHub CLI installed (`gh`)
- [ ] Required AWS permissions:
  - [ ] `iam:CreateOpenIDConnectProvider`
  - [ ] `iam:CreateRole`
  - [ ] `iam:PutRolePolicy`
  - [ ] `iam:CreateServiceLinkedRole`
- [ ] GitHub token available (for API updates)
- [ ] No existing OIDC provider conflicts

## Deployment Steps

### 1. Verify Environment

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check Terraform
terraform version

# Check GitHub CLI
gh auth status
```

### 2. Deploy OIDC Infrastructure

**Option A: Automated Script**
```bash
export AWS_ACCOUNT_ID="<your-account-id>"
export AWS_REGION="us-east-1"
export GCP_PROJECT_ID="<your-gcp-project>"

./scripts/deploy-aws-oidc-federation.sh
```

**Option B: Terraform Manual**
```bash
cd infra/terraform/modules/aws_oidc_federation

terraform init -upgrade
terraform plan \
  -var="aws_account_id=$AWS_ACCOUNT_ID" \
  -var="aws_region=us-east-1" \
  -var="gcp_project_id=$GCP_PROJECT_ID" \
  -var="github_repo=kushin77/self-hosted-runner"

terraform apply
```

### 3. Verify Deployment

```bash
./scripts/test-aws-oidc-federation.sh
```

Expected output (all tests pass):
```
✅ AWS CLI configured
✅ OIDC Provider Exists
✅ OIDC Role Exists
✅ OIDC Role Trust Policy
✅ IAM Policies Attached
✅ Required Permissions
✅ OIDC Token Exchange
✅ Terraform State Valid
✅ Security Isolation
✅ Audit Log Exists

Tests Passed: 10
Tests Failed: 0
```

### 4. Extract Deployment Values

```bash
cd infra/terraform/modules/aws_oidc_federation

OIDC_PROVIDER_ARN=$(terraform output -raw oidc_provider_arn)
OIDC_ROLE_ARN=$(terraform output -raw oidc_role_arn)
OIDC_ROLE_NAME=$(terraform output -raw oidc_role_name)

echo "OIDC_PROVIDER_ARN=$OIDC_PROVIDER_ARN"
echo "OIDC_ROLE_ARN=$OIDC_ROLE_ARN"
echo "OIDC_ROLE_NAME=$OIDC_ROLE_NAME"
```

### 5. Test OIDC Token Exchange

```bash
# Create a test workflow or use GitHub CLI
gh workflow run oidc-deployment.yml

# Monitor workflow execution
gh run list -w oidc-deployment.yml -L 1
gh run view <run-id> --log
```

## Post-Deployment Verification

- [ ] OIDC Provider created in AWS IAM
- [ ] GitHub OIDC Role exists with correct trust policy
- [ ] Test workflow successfully assumed OIDC role
- [ ] `aws sts get-caller-identity` shows OIDC role
- [ ] All tests from test script passing
- [ ] CloudTrail shows `AssumeRoleWithWebIdentity` events
- [ ] Deployment logged to audit trail (`logs/aws-oidc-deployment-*.jsonl`)

## Migration to OIDC Authentication

### Step 1: Update Workflows

Update existing GitHub Actions workflows to use OIDC:

```yaml
permissions:
  id-token: write    # Required for OIDC
  contents: read

steps:
  - name: Assume AWS Role
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::{{ AWS_ACCOUNT_ID }}:role/github-oidc-role
      aws-region: us-east-1
```

### Step 2: Verify Workflows

- [ ] All workflows use new OIDC authentication
- [ ] No workflows still using AWS_ACCESS_KEY_ID secret
- [ ] No workflows still using AWS_SECRET_ACCESS_KEY secret
- [ ] CloudTrail shows correct OIDC principal

### Step 3: Clean Up

- [ ] Delete `AWS_ACCESS_KEY_ID` from GitHub Secrets
- [ ] Delete `AWS_SECRET_ACCESS_KEY` from GitHub Secrets
- [ ] Rotate or delete AWS IAM access keys
- [ ] Archive old authentication records

## Security Checklist

- [ ] OIDC role uses least-privilege permissions
- [ ] Trust policy restricts to specific repository
- [ ] Trust policy restricts to specific branches
- [ ] Token audience set to `sts.amazonaws.com`
- [ ] CloudTrail enabled for OIDC usage audit
- [ ] No direct AWS access key usage remaining
- [ ] Session duration set to 1 hour (minimum)
- [ ] KMS key policy allows OIDC role

## Troubleshooting

### Issue: "No OIDC Provider Found"
```bash
# Deploy again
./scripts/deploy-aws-oidc-federation.sh

# Check existing providers
aws iam list-open-id-connect-providers
```

### Issue: "AssumeRoleWithWebIdentity Failed"
```bash
# Verify role trust policy
aws iam get-role --role-name github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument'

# Check conditions match
aws sts get-caller-identity  # Should show OIDC role
```

### Issue: "Access Denied" in Workflows
```bash
# Verify role permissions
aws iam list-attached-role-policies --role-name github-oidc-role
aws iam list-role-policies --role-name github-oidc-role

# Add missing permissions if needed
```

## Documentation

- [AWS OIDC Implementation Guide](../../docs/AWS_OIDC_FEDERATION.md)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS OIDC Provider Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)

## Deployment Artifacts

**Terraform Module**: `infra/terraform/modules/aws_oidc_federation/`
- `main.tf` - OIDC provider and role resources
- `variables.tf` - Input variables
- `outputs.tf` - Output values

**Scripts**:
- `scripts/deploy-aws-oidc-federation.sh` - Automated deployment
- `scripts/test-aws-oidc-federation.sh` - Test suite

**Workflows**:
- `.github/workflows/oidc-deployment.yml` - GitHub Actions workflow

**Audit Logs**:
- `logs/aws-oidc-deployment-*.jsonl` - Immutable deployment records
- AWS CloudTrail - API call audit trail

## Success Criteria

✅ **OIDC Provider Created**
```bash
aws iam list-open-id-connect-providers | grep token.actions.githubusercontent.com
```

✅ **GitHub Role Created**
```bash
aws iam get-role --role-name github-oidc-role
```

✅ **Test Workflow Passed**
```bash
gh workflow run oidc-deployment.yml
# All jobs passed
```

✅ **Audit Trail Recorded**
```bash
cat logs/aws-oidc-deployment-*.jsonl
```

✅ **Workflows Migrated**
```bash
# All active workflows use OIDC, no long-lived keys
grep -r "AWS_ACCESS_KEY_ID" .github/workflows/ || echo "✅ No long-lived keys"
```

## Properties

- **Immutable**: All operations logged to JSONL audit trail
- **Idempotent**: Terraform state manages infrastructure, safe to rerun
- **Ephemeral**: STS temporary credentials (1 hour expiration)
- **No-Ops**: Fully automated deployment
- **Hands-Off**: Direct commits to main, zero manual ops

## Timeline

- **Pre-Deployment**: ⏳ Awaiting confirmation
- **Deployment**: 📋 In progress
- **Verification**: ⏳ Pending
- **Migration**: ⏳ Pending
- **Completion**: ⏳ Pending

## Contact & Support

- **Owner**: @kushin77
- **Team**: Infrastructure
- **Escalation**: Tier 2 on-call engineer

---

**Deployment Status**: 🔄 In Progress
**Last Updated**: 2026-03-11T14:00:00Z
