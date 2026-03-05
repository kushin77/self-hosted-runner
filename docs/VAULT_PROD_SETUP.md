# Vault Production Setup for RunnerCloud

This document describes recommended steps to configure HashiCorp Vault for production use with the `managed-auth` and `provisioner-worker` services.

Goals
- Securely store runner registration tokens and provisioning credentials in KV v2.
- Use AppRole for CI and service authentication (least privilege).
- Automate Vault credentials in GitHub Actions via repository secrets.

Prerequisites
- Vault server accessible from CI and production hosts.
- Vault operator privileges to create mounts, policies, and AppRoles.

1) Create KV v2 mount

```sh
vault secrets enable -path=secret kv-v2
```

2) Create a policy for `managed-auth` (read/write limited path)

Example policy `runnercloud-managed-auth.hcl`:

```
path "secret/data/runnercloud/tokens/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

Apply policy:

```sh
vault policy write runnercloud-managed-auth runnercloud-managed-auth.hcl
```

3) Create AppRole for CI (integration tests)

```sh
vault write auth/approle/role/runnercloud-ci token_policies="runnercloud-managed-auth" token_ttl=1h token_max_ttl=4h
vault read auth/approle/role/runnercloud-ci/role-id
vault write -f auth/approle/role/runnercloud-ci/secret-id
```

Store the `role_id` and `secret_id` securely in GitHub repository secrets `VAULT_ROLE_ID` and `VAULT_SECRET_ID` (or use a file path `VAULT_SECRET_ID_PATH` mounted into runners).

4) CI configuration (GitHub Actions)

- Add `VAULT_ADDR`, and either `VAULT_TOKEN` (short-lived, limited) or `VAULT_ROLE_ID` + `VAULT_SECRET_ID` to repository or environment secrets.
- The `p2-vault-integration.yml` workflow will prefer these secrets; if absent it uses a local dev Vault for tests.

5) Service configuration (production)

- For `managed-auth` and `provisioner-worker`, configure environment variables:
  - `SECRETS_BACKEND=vault`
  - `VAULT_ADDR=https://vault.internal:8200`
  - either `VAULT_TOKEN` (rotate regularly) or AppRole credentials: `VAULT_ROLE_ID` + `VAULT_SECRET_ID_PATH` (file with secret id)

6) Rotation & monitoring

- Use Vault's TTL & token renewal for short-lived credentials.
- Monitor Vault audit logs and set Prometheus alerts for auth failures.

Follow-ups
- Automate AppRole secret provisioning for CI using a CI operator account with minimal scope.
- Add a CI job to run `vault-integration` against real Vault in a staging environment before production rollout.
