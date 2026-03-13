Portal docker helper files

Purpose:
- Use the `docker-compose.yml` in this folder to run the portal API and frontend on a worker node.
- Environment variables are read from `.env` by default; `./.env.example` and `./.env.production` provide templates.

Recommended deploy flow (hands-off):
1. Ensure worker has Docker and Docker Compose installed and authenticated to any required container registries.
2. Ensure GSM (gcloud) or Vault CLI is configured on the worker so `scripts/remote-deploy.sh` can fetch secrets into `.env`.
3. From your workstation run: `./portal/scripts/remote-deploy.sh user@worker` to rsync and start the stack.
4. Run `./portal/docker/smoke-check.sh <worker-host>` to validate API and frontend endpoints.

Security:
- Secrets must never be committed. The deploy script writes `.env` on the worker with 0600 permissions.
- For production, prefer a temporary runtime secret store or mount (GSM/Vault agent) to avoid persistent files.

Zeroize / Ephemeral secrets:
- By default `portal/scripts/remote-deploy.sh` attempts to fetch secrets into an ephemeral `.env.tmp` and then securely deletes it.
- After startup the script will also remove any persistent `.env` or `.env.production` files from the worker for immutability and hygiene. To skip this behavior set the environment variable `KEEP_ENV=1` when invoking the deploy script.
- Best practice: run a secrets agent on the worker (Vault Agent, GCP Secret Manager Agent, or use a short-lived mount) so secrets never land on disk. The current deploy helper provides a pragmatic fallback (ephemeral `.env.tmp`).
