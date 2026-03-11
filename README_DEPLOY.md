Direct deployment and credential provisioning

This repository enforces direct deployment (no GitHub Actions, no PR-based releases).

Scripts:
- `scripts/deploy/direct_deploy.sh` — Deploy Cloud Run service and scheduler job idempotently.
- `scripts/credentials/provision_all_creds.sh` — Provision secrets into Google Secret Manager, Vault, and test KMS.
- `scripts/monitoring-notification-channels.sh` — (existing) configure notification channels.
- `scripts/health-checks/comprehensive-health-check.sh` — (existing) 26-point health checks.

Principles:
- Immutable: all scripts append immutable JSONL audit entries to `logs/`.
- Ephemeral: no long-lived tokens are stored in code; use GSM/Vault/KMS.
- Idempotent: scripts safe to run repeatedly.
- No-Ops / Hands-Off: scripts intended to be run by an authorized operator or automation (Cloud Scheduler, cron, or an orchestration agent).

Run examples:

```bash
# Provision credentials (interactive editing of secrets required)
vim scripts/credentials/provision_all_creds.sh
export GCP_PROJECT_ID=nexusshield-prod
./scripts/credentials/provision_all_creds.sh

# Direct deploy
export GCP_PROJECT_ID=nexusshield-prod
export IMAGE=gcr.io/nexusshield-prod/nexusshield-portal:20260311
./scripts/deploy/direct_deploy.sh
```
