# Direct Deployment (No GitHub Actions / No PRs)

This repository contains an approved path for direct deployment to production without using GitHub Actions or pull-request based releases. Follow these principles:

- Immutable: all deployment records are stored in Git and GitHub Issues (audit trail).  
- Ephemeral: use OIDC and short-lived tokens where possible.  
- Idempotent: Terraform and scripts are safe to re-run.  
- No-Ops / Hands-off: scheduling and automation should run externally (cron, cloud scheduler).  
- Credentials: Use GSM (Google Secret Manager) primary, Vault secondary, AWS KMS tertiary.

Files added:

- `scripts/direct_deploy.sh` — idempotent deploy script (plan/apply/status).
- `PRODUCTION_DEPLOYMENT_AUTHORIZED.md` — record of authorization and next steps.

How to use (operator/maintainer):

1. Prepare environment variables locally (do NOT commit secrets):

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_SERVICE_ACCOUNT_KEY="/path/to/sa-key.json"
export GCP_WIP="projects/123/locations/global/workloadIdentityPools/.../providers/..."
export VAULT_ADDR="https://vault.example"
export VAULT_AUTH_KEY="..."  # set in your shell at runtime; do NOT commit
export AWS_KMS_KEY_ID="arn:aws:kms:..."
export AWS_REGION="us-west-2"
```

2. Run a plan locally:

```bash
./scripts/direct_deploy.sh plan
```

3. Apply when ready:

```bash
./scripts/direct_deploy.sh apply
```

4. Monitor using `status` or your production health checks.

Notes:
- This workflow intentionally avoids GitHub Actions and PR-based releases. Any changes to infrastructure should be made directly on `main` via an authenticated push by an authorized maintainer.
- To update GitHub issues (create/close), use `gh` CLI or API with an admin token. This script does not modify GitHub issues.
