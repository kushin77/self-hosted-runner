# E2E Runbook: Self-hosted runner Vault AppRole provisioning and E2E test

Purpose
- Provide an operator-safe, copy-paste runbook to provision a temporary Vault AppRole or set secrets, run the repository end-to-end tests, and then clean up.

Prerequisites
- Access to the self-hosted runner host with permissions to edit the runner service or run commands as the runner user.
- `vault` CLI installed and reachable from the runner host.

Two safe operator flows

1) Non-admin flow (recommended if you cannot provide `VAULT_ADMIN_TOKEN`):

 - Operator provisions the AppRole `role_id` and `secret_id` into the runner's secure environment (systemd service env, or a file accessible by the runner user). Steps:

   - Create a secure file for `secret_id` on the runner host:

```sh
mkdir -p /run/vault
cat > /run/vault/approle-secret <<'EOF'
<paste-secret-id-here>
EOF
chmod 600 /run/vault/approle-secret
export VAULT_ADDR=https://vault.example.com
export VAULT_ROLE_ID=<paste-role-id-here>
export VAULT_SECRET_ID_PATH=/run/vault/approle-secret
# (optionally export VAULT_SECRET_ID directly for a one-off run)
```

 - Then run the local e2e script as the runner user (or in the repo workspace):

```sh
cd /home/akushnir/self-hosted-runner
./scripts/ci/run-e2e-self-hosted-with-vault.sh
```

2) Admin auto-provision flow (if operator is comfortable providing `VAULT_ADMIN_TOKEN`):

 - Export admin token temporarily (the script will create and revoke short-lived AppRole):

```sh
export VAULT_ADDR=https://vault.example.com
export VAULT_ADMIN_TOKEN="<vault-admin-token-here>"
cd /home/akushnir/self-hosted-runner
./scripts/ci/provision-approle-and-run-e2e.sh
unset VAULT_ADMIN_TOKEN
```

Cleanup and rotation
- The auto-provision script attempts to revoke the created `secret_id` and delete the AppRole and policy. If you used the non-admin flow, remove `/run/vault/approle-secret` after the run and rotate the secret in Vault if it was created from a production AppRole.

Notes
- The automation scripts and runbook are in `scripts/ci/` and `issues/` respectively: see `scripts/ci/run-e2e-self-hosted-with-vault.sh` and `scripts/ci/provision-approle-and-run-e2e.sh`.
- Do not commit real secrets to the repository. Use the secure file path or service environment variables on the runner host.

Contact
- Tag the repo owner or ops team in the GitHub issue created alongside this runbook for coordination.
