# Deploying production Terraform

This document explains approved ways to provision the production infrastructure for NexusShield.

Local (manual) apply

1. Ensure you have admin credentials or a service account with required permissions.
2. From repo root run:

```bash
cd nexusshield/infrastructure/terraform/production
terraform init
terraform apply -var 'environment=production'
```

CI-based apply (recommended, approval-gated)

- A GitHub Actions workflow `Terraform Apply - Production` has been added at `.github/workflows/terraform-apply.yml`.
- It uses `environment: production`, which requires a reviewer/approver before the job runs when pushing to `main` or when triggered manually via `workflow_dispatch`.
- Recommended authentication methods:
  - GCP Workload Identity Provider (OIDC) + service account (preferred). Set `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT_EMAIL` as repository secrets or configure the environment.
  - Or provide a base64-encoded service account key as `GCP_SA_KEY` secret (fallback).

Security notes

- The run must append the final audit entry to the immutable audit trail `nexusshield/logs/deployment-audit.jsonl` as part of post-apply verification.
- Configure the `production` environment with required approvers and store secrets at the environment level if preferred.
