# How to add required AWS repo secrets

This repository requires a small set of repository-level secrets so Terraform runs
on self-hosted or GitHub Actions runners can authenticate with AWS. Do NOT
commit secret values to the repo — use GitHub Secrets, Organization Secrets,
or a secrets manager (Vault) with the runner configured to fetch them.

Required secrets (P4 — AWS Spot Runner):

- `AWS_ROLE_TO_ASSUME` — ARN of the role the runner should assume for Terraform
  operations (e.g. `arn:aws:iam::123456789012:role/ci-terraform-plan-role`).
- `AWS_REGION` — AWS region the deployment targets (e.g. `us-east-1`).

Recommended steps to add secrets via the GitHub web UI:

1. Go to the repository Settings -> Secrets and variables -> Actions -> New repository secret.
2. Add `AWS_ROLE_TO_ASSUME` and its value.
3. Add `AWS_REGION` and its value.
4. If you prefer organization-scoped secrets, add them under the Organization Settings -> Secrets.

Advanced: Using Vault or an external secrets manager

- Configure your self-hosted runner to fetch short-lived credentials from Vault or AWS STS rather than storing long-lived credentials in GitHub Secrets.
- Store the Vault token / accessor as a GitHub secret and use the runner's startup scripts to obtain temporary AWS credentials before running Terraform.

If you want me to add the secrets to the repo and you provide values (or provide a secure channel), I can set them via the `gh` CLI. Otherwise please ask an org admin to add them and then I will re-run the plan.
