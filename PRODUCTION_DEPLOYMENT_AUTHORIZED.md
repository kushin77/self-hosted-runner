# PRODUCTION DEPLOYMENT AUTHORIZATION RECORD

Date: 2026-03-11

Authorization: Approved — proceed now, no waiting.

Scope: Direct development/deployment to production without GitHub Actions or PR-based releases. Use GSM, Vault, AWS KMS for secrets. Ensure idempotency and ephemeral credentials.

Actions taken locally:

- Added `scripts/direct_deploy.sh` — idempotent deploy helper.
- Added `README_DIRECT_DEPLOY.md` — direct-deploy runbook and operator steps.

Next tasks (suggested, require remote credentials and admin rights):

1. Push these changes to `main` and tag release (authorized maintainer).
2. Create/close GitHub issues for audit: post comment `PRODUCTION_DEPLOYMENT_EXECUTED` and close blockers (#1838, #1816) once done.
3. Provision credentials into GSM/Vault/KMS following documented runbook. Use `VAULT_AUTH_KEY` as your runtime Vault auth variable name (do NOT commit secrets).
4. Run `./scripts/direct_deploy.sh apply` with required env vars.

Record of operator who triggered: __________
