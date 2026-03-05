# Infra Tasks (local tracker)

The GitHub API call to create issues failed (likely missing credentials or wrong repo/permissions). Temporary local tracking lives here until GH issues can be created.

1) Apply Terraform: GCP KMS & GCS for Vault (auto-unseal)
- Files: `terraform/gcp-vault-infra.tf`, `terraform/provider.tf`, `terraform/variables.tf`
- Command:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
cd terraform
terraform init
terraform apply -var="project_id=YOUR_PROJECT_ID" -auto-approve
```

2) Configure Workload Identity Federation (GitHub Actions OIDC)
- Create a GCP Workload Identity Pool & Provider for GitHub Actions and bind the `vault-admin-sa` to the pool.
- Reference: `docs/security/GSM_VAULT_RUNBOOK.md`.

3) Configure GitHub Actions OIDC Trust
- Add a `roles/iam.serviceAccountTokenCreator` binding to allow GitHub OIDC to impersonate `vault-admin-sa`.

4) Final Production Test
- Run the existing `scripts/automation/pmo/deploy-p2-production.sh` with real OIDC creds and validate Trivy gating and Vault auto-unseal.

When you provide a GitHub token with issue write permissions or confirm repo/owner, I will create/update/close the corresponding GitHub issues automatically.