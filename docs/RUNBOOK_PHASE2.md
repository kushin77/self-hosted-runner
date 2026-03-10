# Phase 2 — Automated Terraform Apply Runbook

Purpose
- Provide step-by-step, idempotent, hands-off run instructions for Phase‑2 Terraform apply using the automation runner.

Prerequisites
- Runner host with repo checked out (this repo root).  
- `gcloud`, `jq`, and `terraform` installed and authenticated for the target project.  
- Service account credentials available to the runner via one of these methods (in order of preference):
  1. Google Secret Manager secret named `gcp-terraform-sa-key` (used by `scripts/phase2-runner.sh`).
  2. Vault secret at `secret/data/gcp/terraform-sa-key` (used by runner if `VAULT_ADDR` present).
  3. GCE metadata-attached service account (no key file needed).

Immutable audit
- The runner appends immutable JSONL audit entries to `logs/terraform_phase2_runner_audit.jsonl` for every action.

Fast unblock (admin)
1. Create a least-privilege service account for automation (admin):

```bash
gcloud iam service-accounts create terraform-runner \
  --display-name="Terraform Runner SA" --project=nexusshield-prod

# Example roles (adjust least-privilege as required):
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:terraform-runner@nexusshield-prod.iam.gserviceaccount.com \
  --role=roles/compute.admin
# add roles/iam.serviceAccountAdmin, roles/secretmanager.admin, roles/cloudsql.admin, roles/artifactregistry.writer, roles/servicenetworking.admin as needed

# Create key and upload to GSM
gcloud iam service-accounts keys create /tmp/terraform-sa.json \
  --iam-account=terraform-runner@nexusshield-prod.iam.gserviceaccount.com --project=nexusshield-prod

gcloud secrets create gcp-terraform-sa-key --data-file=/tmp/terraform-sa.json --project=nexusshield-prod || true
gcloud secrets versions add gcp-terraform-sa-key --data-file=/tmp/terraform-sa.json --project=nexusshield-prod
```

2. On runner host re-run the automation:

```bash
bash scripts/phase2-runner.sh
```

Workload Identity / long-term
- Prefer Workload Identity or attaching a service account to the runner VM to avoid key material. Configure GCP and/or Vault as your governance requires.

Verification & cleanup
- Check `logs/terraform_phase2_runner_audit.jsonl` for immutable entries.  
- Validate resources in GCP (`gcloud`), and confirm Cloud SQL, Cloud Run, and other resources were created.  
- Revoke or rotate any keys as required and document in GSM/Vault/KMS.

Rollback
- Terraform is idempotent — to roll back, create a plan to remove resources (or rely on usual Terraform lifecycle). Use `terraform plan` and `terraform apply` with the desired plan file.

How automation marks issues
- The automation will post status comments and attach the audit artifact. After a successful apply, issues #2317, #2321, #2112, and #2297 will be updated and closed with links to the audit log and runbook.
