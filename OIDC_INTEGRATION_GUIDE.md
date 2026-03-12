# OIDC Integration Guide

Purpose: Describe how to use the deployed AWS OIDC federation for ephemeral credentialing from GitHub Actions-style workflows. This is documentation only — no workflows are applied by this repo.

Example usage (GitHub Actions style example for reference):

1. Ensure `id-token: write` permission is set in the workflow permissions.

2. Example job snippet (reference only):

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::830916170067:role/github-oidc-role
          aws-region: us-east-1
          audience: sts.amazonaws.com

      - name: Verify identity
        run: aws sts get-caller-identity --output table
```

Security notes:
- Remove long-lived AWS access keys from GitHub Secrets after verifying OIDC-based workflows.
- Use CloudTrail and `logs/aws-oidc-deployment-*.jsonl` to audit assume-role events.
- Restrict `role-to-assume` to specific repositories and path/subject patterns.

Operational notes:
- To revoke OIDC trust quickly, disable or delete the OIDC provider in AWS IAM.
- Rotate and retire IAM roles via Terraform (idempotent) when lifecycle changes are required.
