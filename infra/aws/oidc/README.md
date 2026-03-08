# AWS OIDC Provider Terraform Module

This directory is a placeholder for Terraform code that will create an IAM OIDC Provider and roles
for GitHub Actions to assume. The `deploy-cloud-credentials.yml` workflow will run Terraform here
when executed with `dry_run=false`.

Notes:
- To run fully automated, supply AWS admin credentials via repository secrets or run from an environment
  with `aws` CLI authenticated.
- Module design is idempotent — re-running apply will keep state consistent.
