# GitHub Actions OIDC / IAM / KMS / GSM Examples

This folder contains example Terraform snippets to provision an AWS IAM role for GitHub Actions OIDC, a KMS key for CI secrets encryption, and guidance for Google Secret Manager (GSM) integration.

These examples are templates only — adjust variables and policies to match your security posture.

Files:
- `github_oidc_role.tf` — IAM role + optional OIDC provider example
- `iam_trust_policy.json` — example assume-role policy
- `kms_key.tf` — example KMS key resource

Usage (example):

1. Create a branch and copy the files into your IaC pipeline.
2. Set variables: `account_id`, `github_owner`, `github_repo`, `branch`, `role_name`.
3. Apply with Terraform in a controlled environment.

Notes:
- Ensure the OIDC provider `token.actions.githubusercontent.com` is trusted by your AWS account before assuming roles.
- Use least-privilege policies for the role and KMS key.
