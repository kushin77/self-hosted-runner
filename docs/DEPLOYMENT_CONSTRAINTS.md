**Deployment Constraints & Best Practices**

- **Immutable**: Deploy artifacts (images, audit logs) are immutable; releases are tracked by image tags and git commit hashes in the audit trail.
- **Ephemeral**: All runtime state should be held in external services (S3/MinIO, RDS-like DB) and containers must be replaceable.
- **Idempotent**: Deployment scripts (`scripts/deploy-direct.sh`) are safe to run multiple times and should converge to the same state.
- **No-Ops / Hands-Off**: Operator actions are scripted and automated. Use `scripts/deploy-direct.sh` for production deploys.
- **Secrets**: All secrets must be provisioned from GSM/Vault/KMS. Do NOT store secrets in git or in `docker-compose` files. Use `.env` on the target host; see `scripts/provision-secrets.sh` as a template.
- **Direct Deployment**: Use SSH-based direct deploy (no PR-merges required to trigger deploys). GitHub Actions and automated GitHub releases are not used in this workflow.
- **Audit Trail**: Every deploy run must write an append-only JSONL audit log to `logs/` and push evidence (commit, timestamp) to the repo.

Follow-up tasks:
- Add a `postgres_exporter` and re-enable Postgres metrics via exporter port.
- Integrate `scripts/provision-secrets.sh` with Vault/GSM/KMS and add automated bootstrap.
- Add a cron or systemd timer on the deployment host to rotate secrets from GSM.
