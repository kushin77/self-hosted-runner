One-day request: Provision Vault-AppRole and Vault SecretID on the self-hosted runner.

Purpose : Provision may be enabled environmentally for tests. Provisioning orders is:
- configure `VAULT_ADDR`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID` in the hws.
- ensure the specified vault config is secure and hidden.

Operator steps:
1. On the self-hosted runner host, temporarily set the following env vars in the runner's service or via a secure file readable by the runner user:

   - `VAULT_ADDR` (e.g. https://vault.example.com)
   - `VAULT_ROLE_ID` (temporary role id)
   - `VAULT_SECRET_ID` (temporary secret id)

2. Alternatively, install `vault-agent` with a short-lived token and configure a template to expose the `secret_id` as a file at `/run/vault/.secret` and set `VAULT_SECRET_ID_PATH` accordingly.

3. Notify the infra team when secrets are provisioned so I can run an end-to-end CI validation and then remove or rotate the secrets.

See `issues/001-audit-and-sanitize-docs.md` for audit context.
