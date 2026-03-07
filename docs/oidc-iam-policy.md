# IAM Policy Snippets for OIDC Role — Minimal Privileges

This file provides ready-to-apply policy snippets for cloud teams to grant the GitHub Actions OIDC role the minimal permissions required to operate Terraform backend and locking, and to run typical Terraform operations for ElastiCache.

1) S3 backend & DynamoDB lock (least-privilege)

Path: `infra/oidc/aws/iam-policy-s3-backend.json`

- Replace placeholders: `<TERRAFORM_STATE_BUCKET>`, `<TERRAFORM_LOCK_TABLE>`, `<REGION>`, `<ACCOUNT_ID>`, `<KMS_KEY_ID>`.

2) Example broader policy for Terraform operations (ElastiCache provisioning)

Note: Terraform modifies many AWS resources — you can scope this policy by service, resource ARNs, and actions. Below is an example that grants typical ElastiCache and networking operations. Use least-privilege in production.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "elasticache:CreateReplicationGroup",
        "elasticache:ModifyReplicationGroup",
        "elasticache:DeleteReplicationGroup",
        "elasticache:CreateCacheCluster",
        "elasticache:DeleteCacheCluster",
        "elasticache:Describe*"
      ],
      "Resource": "*"
    }
  ]
}
```

3) Suggested workflow

- Apply `infra/oidc/aws/iam-policy-s3-backend.json` to the role used for GitHub OIDC. Confirm S3 bucket and DynamoDB table ARNs.
- Apply an additional (scoped) Terraform operations policy for the role with only the actions you need.

If you want I can add a CloudFormation/terraform wrapper to create the role and attach these policies automatically — tell me and I will add it to PR #1296 as an optional convenience module.
