**Vault Auto-provisioning Helper**

- **Purpose**: Helper script to create an AppRole in Vault and optionally set `VAULT_ROLE_ID` and `VAULT_SECRET_ID` as GitHub repository secrets using the `gh` CLI.
- **Location**: `scripts/ci/provision-approle-and-set-secrets.sh`

Usage example (run from a secure admin host):

```
export VAULT_ADDR="https://vault.example.com"
export VAULT_ADMIN_TOKEN="s.xxxxx"
export GITHUB_REPOSITORY="owner/repo"   # optional
./scripts/ci/provision-approle-and-set-secrets.sh --role-name runner-deploy --policy-file ./policies/runner-deploy.hcl
```

Notes:
- The script prefers the Vault HTTP API and requires `VAULT_ADMIN_TOKEN` with privileges to create policies and enable auth methods.
- If `gh` is installed and authenticated, the script will write the repo secrets directly. Otherwise it prints the role_id and secret_id for manual entry.
- Do NOT paste tokens or secrets into public channels. Use GitHub repository secrets or a secure vault for storing credentials.
