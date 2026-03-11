Repository policy: NO GitHub Actions

As per operational policy, this repository must NOT use GitHub Actions or any
pull-request-based release automation for deployments.

Approved deployment model:
- Direct development: commits may be merged directly to `main` by authorized
  operators or automation without PR-based release workflows.
- Direct deployment: `scripts/deployment/deploy-direct.sh` (or `scripts/lib/deploy-common.sh`)
  is the supported deployment mechanism (SSH to operator-managed hosts + `docker-compose`).
- Secrets: all secrets must be provisioned via GSM / HashiCorp Vault / KMS.

Required actions for operators:
- Disable or remove any `.github/workflows/*` entries that perform CI/CD.
- Ensure branch protections and access controls align with direct-commit policies.
- Use the provided `secrets.env.template` and the `scripts/cloudrun/secret_providers.py` helpers
  to fetch secrets at runtime from GSM/Vault/KMS.

Reasoning: This policy enforces a single, auditable deployment path (direct deploy),
eliminates PR-based automated releases, and centralizes secret handling to approved
secret storage solutions.
