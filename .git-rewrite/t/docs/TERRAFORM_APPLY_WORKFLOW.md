# Terraform Plan/Apply Workflow

This repository contains a GitHub Actions workflow to run `terraform plan` and optionally `terraform apply` from a self-hosted runner. Use this to safely run plan and then apply in production without sharing raw credentials in issues.

## Required repository secrets
- `PROD_TFVARS` — (recommended) the full content of `terraform/prod.tfvars` with production values. Example content can be copied from `terraform/prod.tfvars.example`.
- `GOOGLE_CREDENTIALS` — JSON service account key for GCP (the workflow writes this to `/tmp/gcloud-creds.json` and sets `GOOGLE_APPLICATION_CREDENTIALS`).

Security note: Do NOT commit `prod.tfvars` or credentials to the repo. Use repository secrets (or org-scoped secrets) only.

## How it works
1. Run the workflow (Actions → Terraform plan/apply → Run workflow). By default it runs `plan` and uploads the `prod.tfplan` artifact.
2. Inspect the plan artifact in Actions artifacts to review changes.
3. To apply, re-run the workflow and set the `apply` input to `true`. The workflow will then run `terraform apply` on the plan it generates in that run.

## Commands run by the workflow
- `terraform init -input=false`
- `terraform plan -var-file=prod.tfvars -out=prod.tfplan -input=false`
- `terraform apply -input=false prod.tfplan` (only when `apply=true`)

## Running locally on an infra host (alternative)
If you prefer running on an infra host rather than Actions, use `scripts/terraform/run_terraform_apply_safe.sh` which now supports plan and apply with an interactive confirmation.

## Next steps for Ops
1. Add `PROD_TFVARS` and `GOOGLE_CREDENTIALS` as repository secrets (or org secrets scoped to this repo).
2. Run the workflow to create the plan artifact and review.
3. Re-run with `apply=true` to apply.

