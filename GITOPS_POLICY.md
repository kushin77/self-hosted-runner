Repository Policy: No GitHub Actions

- Purpose: Enforce direct development + direct deployment using Cloud Build.
- Policy:
  - No GitHub Actions or PR-release workflows are allowed in this repository.
  - CI/CD must use Cloud Build triggers and signed artifact registries.
  - Secrets must be stored in Google Secret Manager (GSM) and encrypted with Cloud KMS. HashiCorp Vault may be used as an orchestrator, but GSM is required for Cloud Build access.
  - Branch protection rules must require Cloud Build status checks before merges.
  - Any exceptions require an explicit security-reviewed approval recorded in the org policy board.

See `DEPLOYMENT.md` for deployment steps and `scripts/ops/setup_gsm_vault_kms.md` for secret setup.
