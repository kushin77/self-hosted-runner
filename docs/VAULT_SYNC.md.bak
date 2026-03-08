# HashiCorp Vault → GitHub Actions Secrets sync

This document describes a helper script to fetch secrets from Vault and write them to GitHub Actions repository secrets.

Prerequisites
- `vault` CLI installed and authenticated (token or approle). If using AppRole, prefer short-lived credentials or OIDC where possible.
- `gh` CLI authenticated with `repo` scope.

Quick usage (local operator):

```bash
./scripts/ops/vault_sync.sh --addr https://vault.example:8200 kushin77/self-hosted-runner secret/data/prod/slack:webhook_url
```

Notes
- The script supports KV v2 and reads JSON outputs from `vault` and `vault kv`.
- It writes GitHub secrets using `gh secret set` and uses temporary files; values are not committed.
- Recommended repo secrets for automation runners: `VAULT_ADDR`, `VAULT_TOKEN` (or configure AppRole and provide role/secret via secure channel).

Automation
- A manual workflow is available at `.github/workflows/vault-sync-run.yml` that can be run from Actions (workflow_dispatch). Ensure `VAULT_ADDR` and `VAULT_TOKEN` are set in repo secrets before running.
