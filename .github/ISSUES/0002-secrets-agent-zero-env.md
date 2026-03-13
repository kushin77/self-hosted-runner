Title: Hardening: Use Secrets Agent (Vault Agent / GSM Agent) and enforce zero-env
Status: open

Summary:
- Replace fallback `.env` writes with a secrets agent (Vault Agent or GSM agent) that injects secrets in-memory or via ephemeral mounts. Do not persist secrets on disk.
- Ensure `KEEP_ENV` is opt-in and forbidden for production. Use agent-managed lifecycle and systemd unit for the agent.

Acceptance Criteria:
- Example `vault-agent.service` and `install-vault-agent.sh` are provided in `portal/docker/`.
- CI/CD checks verify no `.env` files are present in the repo and deployment scripts default to ephemeral secrets.
