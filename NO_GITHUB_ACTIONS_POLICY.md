Policy: No GitHub Actions Allowed

- Purpose: This repository does not allow GitHub Actions workflows to run in CI or as part of automated releases. All production deployments must use direct SSH + docker-compose, operator-run scripts, and approved automation.

- Secrets: Use Vault, Google Secret Manager (GSM), or KMS for all credentials. Never store tokens, keys, or secrets in the repository.

- Archive: Historical workflow files have been moved to `.github/workflows.disabled/` and sanitized (no hard-coded tokens).

- Enforcement:
  - Local pre-commit hook `.githooks/prevent-workflows` blocks commits that add or modify `.github/workflows/` files.
  - Operators should enforce org-level policy if desired (disable Actions at org-level via GitHub settings).

- Recovery: If automation is required, create an operator-run script that retrieves secrets via approved secret managers (see `scripts/`) and runs deployments directly.

- Contact: Tag `@ops-admin` for requests to re-enable any workflow; requests must include an explicit security review and vault/gsm integration.
