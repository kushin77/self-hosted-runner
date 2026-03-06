Vault Integration Patterns
==========================

This document describes recommended patterns to integrate Vault with CI, runners, and deployment tooling.

Quick rules
-----------
- Never store secrets in source control.
- CI workflows should fetch secrets at runtime using the Vault helper (`ci/scripts/fetch-vault-secret.sh`).
- Use short-lived tokens and approle/oidc for CI authentication.

Examples
--------
- Fetch DB password into an env var:

```
export VAULT_ADDR=https://vault.internal
export VAULT_TOKEN="$(cat /var/run/vault-token)"
./ci/scripts/fetch-vault-secret.sh secret/data/db postgres_password DB_PASS
# use $DB_PASS in subsequent steps
```

- Use Vault Agent / Injector when running in Kubernetes to avoid plumbing tokens in workflows.

Security
--------
- Ensure Vault TLS is enforced and CA pinned in runner images.
- Rotate tokens regularly and limit token scopes.
