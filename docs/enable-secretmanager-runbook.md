**Enable Secret Manager API — Runbook**

- Purpose: idempotently enable `secretmanager.googleapis.com` on `p4-platform`.
- Preferred method: apply Terraform module `nexusshield/infrastructure/terraform/modules/enable-secretmanager`.

Prerequisites:
- GCP account with `serviceusage.services.enable` (Project Owner / Service Usage Admin).
- `terraform` >= 1.0 installed and configured.

Steps:
1. From repo root, configure credentials (gcloud auth application-default login) or use a service account.
2. Create a simple root module or use existing Terraform root to call the module:

```hcl
module "enable_secretmanager" {
  source  = "./modules/enable-secretmanager"
  project = "p4-platform"
}
```

3. Run the helper script:

```bash
scripts/terraform_apply_enable_gsm.sh nexusshield/infrastructure/terraform p4-platform
```

4. Verify:
- `gcloud services list --enabled --project=p4-platform | grep secretmanager`

If you prefer not to run Terraform, enable manually:

```bash
gcloud services enable secretmanager.googleapis.com --project=p4-platform
```

IAM notes:
- Approver must ensure the account used has `serviceusage.services.enable` or is Project Owner.

Audit:
- Each attempt should be recorded to `logs/complete-finalization-audit.jsonl` (the repo contains helper scripts for this).
