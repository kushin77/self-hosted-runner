# Direct Deployment (Cloud Build) - No GitHub Actions

This repository uses direct deployment via Google Cloud Build. GitHub Actions and GitHub pull-based releases are not used.

Principles
- Immutable artifacts and idempotent infrastructure (Terraform with remote state)
- Secrets: Google Secret Manager (GSM) and Vault + KMS for encryption
- Single outbound agent for data-plane operations
- Fully automated: Cloud Build triggers, no manual server-side steps

Quick deploy (local):

```bash
# trigger default build
scripts/ops/deploy_cloudbuild.sh --project nexusshield-prod --config cloudbuild.nexus-phase0.yaml
```

Security
- All secrets referenced by Cloud Build must be read from GSM or Vault via KMS.
- No plaintext secrets in repo or CI.

Operator notes
- Ensure Cloud Build service account has access to GSM secrets and KMS decrypt.
- Configure Cloud Build triggers in the GCP console or via `gcloud beta builds triggers create`.
