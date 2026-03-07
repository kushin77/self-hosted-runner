# Phase 3 Automation — Current Status & Next Steps

Date: 2026-03-07

Summary
- Automation for Phase P3 orchestration is implemented and validated for no-op/dry-run behavior.
- Key workflows added/updated:
  - `.github/workflows/cloud-provision-oidc.yml` — manual Action to provision AWS OIDC role (runs `scripts/cloud/aws-oidc-setup.sh`).
  - `.github/workflows/terraform-auto-apply.yml` — hardened: OIDC via `aws-actions/configure-aws-credentials@v2`, static creds fallback, and safe backend-free dry-run when no credentials present.
  - `.github/workflows/auto-trigger-on-label.yml` — retry/backoff for dispatch to avoid transient HTTP 422 errors.
  - `.github/workflows/slsa-provenance-release.yml` — provenance workflow reviewed and minor fixes applied.

What I validated
- Label-driven dispatch works end-to-end in simulation (label `oidc-ready` triggers dispatch).
- Terraform workflows run a safe backend-free init/plan when credentials are not available (no-op, idempotent).
- Cosign signing and attestation stages are present and guarded by `inputs.skip_signature` for no-op runs.

Blocking item (manual cloud action required)
- The AWS S3 backend used by Terraform requires either:
  1. An OIDC role with S3/DynamoDB/KMS permissions (recommended), or
  2. Short-lived AWS credentials in repository secrets (fallback, less preferred).

Runbook for cloud admins (preferred: Actions-run)
1. Open: Repository → Actions → "Cloud: Provision AWS OIDC Role (manual run)".
2. Run workflow with inputs:
   - `account_id` — your AWS account id
   - `region` — region for IAM resources (e.g., `us-east-1`)
   - `state_bucket` — Terraform state S3 bucket name
   - `lock_table` — DynamoDB lock table name
   - `repo_owner` — default: `kushin77`
   - `repo_name` — default: `self-hosted-runner`
   - `dry_run` — `false` to actually provision

3. After successful run, set these repository secrets in the target repo:
   - `AWS_OIDC_ROLE_ARN` = arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
   - `USE_OIDC` = `true`
   - `AWS_DEFAULT_REGION` = chosen region

4. Add label `oidc-ready` to Issue #1309 (the provisioning workflow can also label it).

Alternate local run (cloud admin environment)
```bash
bash scripts/cloud/aws-oidc-setup.sh --account-id <AWS_ACCOUNT_ID> --region <AWS_REGION> \
  --state-bucket <TERRAFORM_STATE_BUCKET> --lock-table <TERRAFORM_LOCK_TABLE> \
  --repo-owner kushin77 --repo-name self-hosted-runner
```

Validation steps after provisioning
- When `oidc-ready` label is applied, automation will:
  - Dispatch preflight SLSA provenance workflow
  - Dispatch `terraform-auto-apply.yml` which will assume the OIDC role and run `terraform init/plan/apply`.
- I will monitor runs, collect logs, fix failures if any, and then close the orchestration issues.

Files changed / added
- `.github/workflows/cloud-provision-oidc.yml` (new)
- `.github/workflows/terraform-auto-apply.yml` (updated)
- `.github/workflows/auto-trigger-on-label.yml` (updated)
- `.github/workflows/slsa-provenance-release.yml` (reviewed)
- `scripts/cloud/aws-oidc-setup.sh` (existing — used by new workflow)

If you'd like me to attempt provisioning from this runner, provide short-lived AWS credentials and confirm the repo-secret names to use; otherwise please ask cloud admins to run the provisioning workflow or the local script and then tag Issue #1309 with `oidc-ready`.

-- Automation agent
