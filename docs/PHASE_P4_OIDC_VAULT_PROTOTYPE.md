# Phase P4: OIDC → Vault Prototype (Dynamic Registry Credentials)

This document describes a minimal prototype for using OIDC to authenticate to HashiCorp Vault and obtain short-lived registry credentials for runner pools.

Goals
- Replace long-lived static repository secrets with short-lived credentials obtained at runtime.
- Demonstrate the flow to integrate a runner bootstrapper with Vault using OIDC login.

Files
- `scripts/identity/vault-oidc-bootstrap.sh` — prototype bootstrap script (uses `curl` + `jq`).

Quickstart (prototype)

1. Ensure Vault is configured with an OIDC or JWT auth method and a role (`VAULT_ROLE`) that maps to allowed policies.
2. Acquire an ID token from your IdP and export it as `ID_TOKEN` in the runner environment (this step depends on your IdP/OIDC provider).
3. Set `VAULT_ADDR` and `VAULT_ROLE` as environment variables.
4. Run the bootstrap script to log into Vault and retrieve registry credentials:

```bash
export VAULT_ADDR=https://vault.example.com
export VAULT_ROLE=runner-role
export ID_TOKEN="$(fetch_id_token_somehow)"
export TARGET_REGISTRY=registry-staging.example.com
scripts/identity/vault-oidc-bootstrap.sh
```

Integration with runner startup

- The repository includes `scripts/identity/runner-startup.sh` which wraps the Vault bootstrapper and then runs the GitHub runner `config.sh`.
- To integrate the prototype into the Terraform module, set the module's `custom_startup_script` to fetch and invoke the startup wrapper (example shown in `terraform/environments/staging-tenant-a/main.tf`).

Token renewal

- A simple renewal loop `scripts/identity/vault-renewal.sh` is included for prototypes to keep Vault tokens/registry logins fresh; in production use Vault agent or a process manager and robust error handling.

Notes & Next steps
- This prototype reads secrets from `secret/data/registries/staging`. Replace with your KV paths or a dedicated secrets engine.
- For production use, do not store `ID_TOKEN` in plaintext; use the cloud provider's workload identity features (e.g., GCP Workload Identity Federation) to mint tokens.
- Implement token renewal (token TTL/renew) and Vault lease lifecycle handling in the bootstrapper.
- Integrate this prototype into the runner `startup-script` in the `terraform/modules/multi-tenant-runners` module to perform credential retrieval before `config.sh` registers the runner.

Security reminder: Treat this as a prototype. Review Vault policies, audit logs, and the IdP trust model before rolling into production.
