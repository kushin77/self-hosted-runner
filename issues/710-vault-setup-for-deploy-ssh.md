# Request: Vault Setup for Deploy SSH Key (Workflow Integration)

Related PR: #708
Related Issue: #707

Summary
---
Updated the `deploy-rotation-staging` GitHub Actions workflow to fetch the deploy SSH private key from **Vault** using AppRole authentication (instead of GCP Secret Manager).

Required GitHub Secrets
---
Add the following repository secrets in GitHub (Settings → Secrets and variables → Actions):

| Secret | Example | Description |
|--------|---------|-------------|
| `VAULT_ADDR` | `<VAULT_ADDR>` | Vault server URL (set in GitHub Actions secrets) |
| `VAULT_ROLE_ID` | `<VAULT_ROLE_ID>` | AppRole Role ID for CI (store in GitHub Secrets) |
| `VAULT_SECRET_ID` | `<VAULT_SECRET_ID>` | AppRole Secret ID (rotate regularly; store in GitHub Secrets) |

Required Vault Secret
---
Store the deploy SSH private key in Vault at the following path:

**Path**: `secret/data/runnercloud/deploy-ssh-key`  
**Key**: `private_key`  
**Value**: (the SSH private key content)

Example (using Vault CLI):
```bash
vault kv put secret/runnercloud/deploy-ssh-key \
  private_key=@/path/to/id_rsa
```

Workflow Dispatch Inputs
---
When dispatching the `deploy-rotation-staging` workflow, use these inputs:

| Input | Example | Notes |
|-------|---------|-------|
| `inventory_file` | `ansible/inventory/staging` | Ansible inventory file path |
| `vault_secret_path` | `secret/data/runnercloud/deploy-ssh-key` | Vault path to SSH key secret |
| `ansible_user` | `deploy` | SSH user for Ansible (optional, defaults to `deploy`) |
| `dry_run` | `false` | Set to `true` for check-mode only |
| `tags` | (empty) | Ansible tags to run (optional) |

Example Dispatch
---
```bash
gh workflow run deploy-rotation-staging.yml \
  -f inventory_file='ansible/inventory/staging' \
  -f vault_secret_path='secret/data/runnercloud/deploy-ssh-key' \
  -f ansible_user='deploy' \
  -f dry_run='false'
```

Verification
---
1. Confirm Vault is accessible at the configured `VAULT_ADDR`.
2. Verify AppRole credentials (`VAULT_ROLE_ID`, `VAULT_SECRET_ID`) are valid and have access to the secret path.
3. Ensure the secret at `secret/data/runnercloud/deploy-ssh-key` contains the `private_key` field with the SSH key content.
4. Merge PR #708 and dispatch the workflow.
5. Monitor the workflow run and verify the deployment succeeded.

Troubleshooting
---
- **Vault auth failed (403)**: Check `VAULT_ROLE_ID` and `VAULT_SECRET_ID` are correct; verify AppRole policy grants access.
- **Secret not found (404)**: Verify the path `secret/data/runnercloud/deploy-ssh-key` exists and contains the `private_key` field.
- **Ansible failed**: Check `ansible_user` matches the SSH user that has the private key configured.

Next Steps
---
1. Add repo secrets `VAULT_ADDR`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`.
2. Add the deploy SSH key to Vault at `secret/data/runnercloud/deploy-ssh-key`.
3. Merge PR #708.
4. Dispatch workflow with the inputs above.
5. I will monitor the run and update/close related issues upon success.
