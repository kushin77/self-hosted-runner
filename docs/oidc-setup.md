# OIDC Setup for Credentialless CI/CD (AWS & GCP)

This document describes how to configure GitHub OIDC so workflows can authenticate to cloud providers without long-lived secrets. The automation in this repo includes a template workflow at `.github/workflows/oidc-auth-template.yml` that will use OIDC if `USE_OIDC=true` is set as a repo secret.

## Overview
- Recommend using OIDC for security (no long-lived secrets in repo)
- Two basic flows covered: AWS (Assume Role via OIDC) and GCP (Workload Identity Federation)

## Quick steps — AWS
1. Create an OIDC identity provider in AWS for `token.actions.githubusercontent.com`.
2. Create an IAM Role with a trust policy that allows the GitHub repository to assume it.
3. Store the role ARN in the repo secret `AWS_OIDC_ROLE_ARN` and the region in `AWS_DEFAULT_REGION`.
4. Add `USE_OIDC=true` as a repo secret.

Terraform example (trust provider snippet):
```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-oidc-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "${aws_iam_openid_connect_provider.github.arn}"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:ref:refs/heads/main"}
      }
    }
  ]
}
EOF
}
```

## Quick steps — GCP
1. Create a Workload Identity Pool and Provider that trusts `https://token.actions.githubusercontent.com`.
2. Create or reuse a GCP service account and allow the provider to impersonate it.
3. Set `GCP_WORKLOAD_IDENTITY_PROVIDER` to the provider resource name and `GCP_WORKLOAD_SERVICE_ACCOUNT` to the service account email.
4. Set `USE_OIDC=true` as a repo secret.

gcloud example (conceptual):
```bash
gcloud iam workload-identity-pools create github-pool --location="global" --display-name="GitHub Actions Pool"
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --display-name="GitHub Actions OIDC Provider"

# Allow the provider to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding SA_EMAIL \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/kushin77/self-hosted-runner"
```

## Using the template
- After provider setup, create the repo secrets: `USE_OIDC=true`, `AWS_OIDC_ROLE_ARN`, `AWS_DEFAULT_REGION`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_WORKLOAD_SERVICE_ACCOUNT`.
- Trigger the workflow: `gh workflow run oidc-auth-template.yml`.

If you want, I will open a PR with these docs and a workflow (already staged) and a short script to validate once OIDC is enabled — tell me to open the PR and I'll push the branch and create it now.
