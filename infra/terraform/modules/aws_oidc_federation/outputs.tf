output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "URL of the GitHub OIDC Provider"
  value       = aws_iam_openid_connect_provider.github.url
}

output "oidc_role_arn" {
  description = "ARN of the GitHub OIDC IAM role"
  value       = aws_iam_role.github_oidc.arn
}

output "oidc_role_name" {
  description = "Name of the GitHub OIDC IAM role"
  value       = aws_iam_role.github_oidc.name
}

output "oidc_role_id" {
  description = "ID of the GitHub OIDC IAM role"
  value       = aws_iam_role.github_oidc.id
}

output "github_oidc_subject_prefix" {
  description = "Subject prefix for GitHub OIDC claims (use in IAM conditions)"
  value       = "repo:${var.github_repo}:*"
}

output "github_oidc_audience" {
  description = "OIDC audience claim required for token exchange"
  value       = "sts.amazonaws.com"
}

output "github_actions_workflow_example" {
  description = "Example GitHub Actions workflow using OIDC"
  value       = <<-EOT
# Example: .github/workflows/deploy-with-oidc.yml
name: Deploy with AWS OIDC

on:
  push:
    branches: [main, governance/*, release/*]

permissions:
  id-token: write     # Required for OIDC token generation
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Assume AWS Role via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${aws_iam_role.github_oidc.arn}
          aws-region: ${var.aws_region}
          audience: sts.amazonaws.com

      - name: Verify Identity
        run: |
          echo "✅ Successfully assumed AWS role via OIDC"
          aws sts get-caller-identity --output table

      - name: Deploy Application
        run: |
          # AWS credentials are automatically injected via STS assume role
          # No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY needed!
          aws s3 ls
          aws cloudformation describe-stacks
EOT
}

output "deployment_summary" {
  description = "Summary of deployed OIDC infrastructure"
  value       = <<-EOT
✅ AWS OIDC Federation Deployment Complete

📊 OIDC Provider:
   - URL: ${aws_iam_openid_connect_provider.github.url}
   - ARN: ${aws_iam_openid_connect_provider.github.arn}
   - Thumbprint: ${aws_iam_openid_connect_provider.github.thumbprint_list[0]}

🔐 GitHub Actions IAM Role:
   - Name: ${aws_iam_role.github_oidc.name}
   - ARN: ${aws_iam_role.github_oidc.arn}
   - Repository: ${var.github_repo}

🎯 Trust Conditions:
   - Audience: sts.amazonaws.com
   - Subject: repo:${var.github_repo}:*
   - Max Session Duration: 1 hour

🔑 Security Benefits:
   ✓ No long-lived AWS access keys needed
   ✓ Temporary credentials (1 hour expiration)
   ✓ Full AWS CloudTrail audit logging
   ✓ Token scoped to repository and workflow
   ✓ Easy revocation by disabling OIDC provider

📝 Next Steps:
   1. Update GitHub Actions workflows with:
      • permissions: { id-token: write }
      • aws-actions/configure-aws-credentials@v4
   2. Test token exchange: aws sts get-caller-identity
   3. Delete AWS_ACCESS_KEY_ID from GitHub Secrets
   4. Delete AWS_SECRET_ACCESS_KEY from GitHub Secrets
   5. Monitor CloudTrail for OIDC usage

🔗 Resources:
   - GitHub Docs: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
   - AWS OIDC: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
EOT
}
