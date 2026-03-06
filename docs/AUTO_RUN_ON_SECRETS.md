**Auto-run Deploys When Vault Secrets Appear**

Purpose
- Small helper to poll the repository for Vault-related secrets and automatically dispatch the deploy workflows once secrets are present. Useful when Ops will set secrets asynchronously and you want the automation to proceed without manual re-triggering.

Requirements
- `gh` CLI installed and authenticated with permissions to list secrets and trigger workflows on `kushin77/self-hosted-runner`.
- No secrets should be supplied via chat — run from a secure admin host or CI controller.

Usage

```
# optional: override default repo and polling parameters
export GH_REPO=kushin77/self-hosted-runner
export CHECK_INTERVAL=60   # seconds between checks
export MAX_CHECKS=360      # how many times to check (default ~6h)
./scripts/ci/watch-and-run-deploys.sh
```

Behavior
- Checks `gh secret list` for `VAULT_ROLE_ID` or `VAULT_ADMIN_TOKEN` and, when found, dispatches:
  - `.github/workflows/deploy-immutable-ephemeral.yml`
  - `.github/workflows/deploy-rotation-staging.yml`
- Logs progress to stdout. Exits with non-zero if timed out.

Security
- The script does not read or emit secret values. It only checks existence and triggers workflows.
