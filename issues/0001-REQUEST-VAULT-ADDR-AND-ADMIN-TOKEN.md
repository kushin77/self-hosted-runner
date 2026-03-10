Title: REQUEST: Provide VAULT_ADDR and Vault admin token
Status: open
Labels: operational, security, blocker

Summary
-------
We need a reachable `VAULT_ADDR` (HTTPS URL) and a short-lived Vault admin token (or run-as step) to provision an AppRole for the automation-runner.

Why
---
- The Cloud Run automation-runner relies on a Vault AppRole to authenticate and write runtime secrets synced from Google Secret Manager (GSM).
- Without a valid Vault address and admin token we cannot complete the automated GSM→Vault seed and validate `vault_sync`.

Required action
---------------
Either:

1) Operator runs locally (preferred):

```bash
export PROJECT=nexusshield-prod
export VAULT_ADDR="https://<vault.example.com>"
# Authenticate to Vault (e.g. `vault login <admin-token>`) in the same shell, then:
bash ./scripts/vault/create_approle_and_store.sh
```

Or 2) Provide the following to the automation agent (only share via secure channel):
- `VAULT_ADDR` (https URL)
- Confirmation that an operator will authenticate to Vault and run the AppRole creation script (we will not accept raw tokens in repo)

Post-conditions
---------------
- AppRole `automation-runner` created in Vault
- `automation-runner-vault-role-id` and `automation-runner-vault-secret-id` written to GSM (Secret Manager)
- Cloud Run runner can authenticate and `vault_sync` will succeed

Notes
-----
- We will not store Vault admin tokens in repo. We will only push role_id/secret_id to GSM and update `terraform.tfvars` with `vault_addr` (no tokens).
- This issue blocks final automation validation and sign-off.

Assignee: @operator
