# AWS IAM Role for GitHub OIDC (Assume-Role) — Setup Guide

Purpose: document the recommended IAM role, trust policy and least-privilege permissions for GitHub Actions to assume an AWS role via OIDC for accessing Secrets Manager (used as a rotation/fallback tier).

Follow these steps to create the role, record the ARN as a repository secret, and test assume-role in a workflow.

## 1) Create IAM Role (Trust Policy)

Use the AWS console or Terraform. Ensure `sts:AssumeRoleWithWebIdentity` is allowed and restrict `sub` to your repository and environment if possible.

Example Terraform snippet:

```hcl
resource "aws_iam_role" "github_actions_oidc" {
  name = "gh-actions-oidc-secrets-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com" }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main" }
        }
      }
    ]
  })
}
```

Adjust the `sub` condition for finer-grained restrictions (branch, tag, environment). If you need organization-wide access, tighten by the `aud` claim and repository refs.

## 2) Least-Privilege Policy (Secrets Manager + S3 for backups)

Attach a policy granting only required actions for rotation and reading/writing secrets:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:CreateSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:your-secret-prefix-*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::your-backup-bucket", "arn:aws:s3:::your-backup-bucket/*"]
    }
  ]
}
```

Limit `Resource` ARNs to the exact Secrets Manager ARNs and S3 buckets used by your workflows.

## 3) Save Role ARN to GitHub Repo Secrets

Once the role exists, add the role ARN to repository secrets (recommended name): `AWS_OIDC_ROLE_ARN`.

Example (gh CLI):

```bash
gh secret set AWS_OIDC_ROLE_ARN --body "arn:aws:iam::123456789012:role/gh-actions-oidc-secrets-manager" -R kushin77/self-hosted-runner
```

## 4) Configure Workflows to Use the Role via OIDC

Use `aws-actions/configure-aws-credentials@v2` in your workflows:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: ${{ secrets.AWS_OIDC_ROLE_ARN }}
    aws-region: us-east-1
```

This action will use GitHub OIDC to obtain temporary credentials without long-lived keys.

## 5) Test the Assume-Role Flow

- Create a small workflow that runs `aws sts get-caller-identity` after configure-aws-credentials to confirm successful assume-role.
- Verify that the role's permissions allow the actions your rotation workflows need.

## 6) Security Notes

- Rotate the role if its ARN is ever compromised (use short-lived session tokens automatically)  
- Use condition keys (`token.actions.githubusercontent.com:sub` and `aud`) to limit trust to specific repos/environments  
- Monitor CloudTrail for `AssumeRoleWithWebIdentity` events and unexpected activity

## 7) Links

- Reference workflows: `.github/workflows/secret-rotation-mgmt-token.yml`, `.github/workflows/rotate-vault-approle.yml`
- See `SECRETS_MASTER_DEPLOYMENT_PLAN.md` for the full runbook and recovery steps.

---

If you'd like, I can create a PR that adds the Terraform role and policy resources (with placeholders) to `infra/` so ops can review and apply. Say “create PR for IAM role” and I'll scaffold it.
