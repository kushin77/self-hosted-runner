Migration: Direct deployment / No Git Actions mandate

Goal
- Migrate repository from GitHub Actions/workflows to a direct-deploy, direct-development model.

Principles
- Deploys are performed by operators or automated runtime agents (systemd/timers, cron, or scheduler) using repository-provided deploy scripts.
- No GitHub Actions/workflows shall perform deployments or enforce merge-time operations.
- All credentials must be retrieved at runtime from GSM/Vault/KMS — do not store secrets in repository or GitHub Actions secrets.
- Maintain an immutable JSONL audit trail for each direct deploy (logs/).

Quick migration steps
1. Use `scripts/direct-deploy.sh` to perform idempotent deploys locally or from CI hosts.
2. Move `.github/workflows/*` into an archive folder (e.g. `.github/workflows.disabled`) and disable Actions in repository settings.
3. Migrate any secret usage from Actions to runtime retrieval (GSM/Vault/KMS). See `CREDENTIAL_PROVISIONING_RUNBOOK.md` for examples.
4. Update documentation and governance to require direct development and disable workflow triggers.
5. Test a direct deploy in staging: `bash scripts/direct-deploy.sh staging` and verify `logs/direct-deploy-*.jsonl` entries.

Notes
- This repository contains legacy workflow files under `.github/workflows/`. Those are now deprecated — do not re-enable them.
- To fully disable workflows for this repo, an admin should go to repository Settings → Actions → General and set appropriate restrictions or disable Actions.
