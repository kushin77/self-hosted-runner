Title: Immutable, Ephemeral, Idempotent Portal Deployment
Status: closed

Summary:
- Ensure portal deployment follows: immutable images, ephemeral credentials, idempotent deployments, no-ops hands-off automation.
- Secrets must be retrieved from GSM (GCP Secret Manager) or Vault and not checked into repo.
- Direct-deploy only: no GitHub Actions or pull-based releases. Deploy by pushing images and running docker compose on worker nodes.

Resolution:
- `portal/docker/docker-compose.yml` updated to use env-driven `VITE_API_URL` and healthchecks.
- Added `portal/docker/.env.example` and `portal/docker/.env.production` and `portal/docker/smoke-check.sh`.
- Added `portal/scripts/remote-deploy.sh` which rsyncs and runs remote docker compose and attempts secrets retrieval using GSM/Vault CLIs.

Notes:
- Operator must configure GSM/Vault secrets and ensure CLI auth on the worker. For KMS-wrapped secrets, include a fetch and unwrap step in the remote-deploy script.
