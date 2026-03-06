Title: Request Ops to provision Vault/AppRole on self-hosted runner

Context:
- Automated E2E and CI flows were added to this repo to validate self-hosted runners using HashiCorp Vault AppRole.
- Local dev runs passed. The automated provisioning attempt on the runner aborted because `VAULT_ADDR` was not set.

Request:
- Please provision Vault connectivity and secrets on the self-hosted runner host (do NOT add secrets to the repo):
  - Preferred (admin auto-provision flow): set `VAULT_ADDR` and provide a short-lived `VAULT_ADMIN_TOKEN` to the runner environment so the provisioning script can create an AppRole, run tests, then revoke/delete the role.
  - Alternative (non-admin flow): set `VAULT_ADDR` and place `VAULT_ROLE_ID` and `VAULT_SECRET_ID` on the runner host; `VAULT_SECRET_ID` may be delivered via a file at `/run/secrets/vault_secret_id` or as an env var.

Operator steps (copy-paste):
1. On the runner host, verify connectivity to Vault and set `VAULT_ADDR` (export or systemd unit env). Example:

   export VAULT_ADDR='https://vault.example:8200'

2a (admin): Temporarily set `VAULT_ADMIN_TOKEN` in the runner environment and inform the automation owner (I will run the auto-provision flow):

   export VAULT_ADMIN_TOKEN='s.ADMIN_TOKEN_HERE'

2b (non-admin): Create secrets file on the runner with the `secret_id` and set `VAULT_ROLE_ID` env var (or export both as env vars):

   export VAULT_ROLE_ID='ROLE_ID_HERE'
   echo 'SECRET_ID_HERE' > /run/secrets/vault_secret_id
   chown root:root /run/secrets/vault_secret_id && chmod 0600 /run/secrets/vault_secret_id

3. Notify the automation owner in this issue when done. I will run the chosen flow, collect/redact logs, revoke/delete temp credentials, and close this issue with results.

Security notes:
- Do NOT paste real secret values in issue comments or repo files. Use placeholders.
- The automation will revoke/delete any AppRole it creates and will not retain secret values in repo or logs.

Run attempt history:
- 2026-03-06: Automated provisioning attempted; aborted because `VAULT_ADDR` was not set on the runner.
