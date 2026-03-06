# OIDC -> Vault Prototype (Runner registration & rotation)

This document describes the prototype scripts to authenticate to Vault using OIDC, retrieve short-lived GitHub runner registration tokens, and rotate self-hosted runners.

Files added:
- `scripts/ci/vault_oidc_auth.sh` — Prototype to exchange an OIDC JWT for a Vault client token via the `auth/oidc/login` endpoint.
- `scripts/ci/get-runner-token.sh` — Reads a KV v2 secret containing the runner registration token and prints it to stdout.
- `scripts/ci/rotate-runner.sh` — Best-effort rotation script that removes and re-registers a runner using a fresh token from Vault.

Usage notes
- These scripts are prototypes and expect environment-specific configuration (Vault mount path, role names, how to obtain the JWT).
- Recommended flow:
  1. Provision an OIDC-capable identity (GitHub Actions OIDC, cloud instance OIDC, or workload identity).
  2. Obtain a JWT and set `VAULT_OIDC_JWT` or adapt `vault_oidc_auth.sh` to fetch it from metadata.
  3. Call `get-runner-token.sh secret/data/ci/self-hosted/my-runner --vault-addr https://vault.example.com` to print the registration token.
  4. Run `rotate-runner.sh /opt/actions-runner https://github.com/owner/repo my-runner secret/data/ci/self-hosted/my-runner` to rotate.

Security
- Do NOT commit tokens to logs or VCS. The scripts attempt to avoid printing tokens; use environment-scoped retrieval and OS-level secret stores in production.
- Vault must be configured with a proper role and policy that allows reading the KV secret. Provide example Vault policy in a follow-up.

Next steps
- Add example Vault role and policy snippets (in a follow-up PR).
- Integrate these scripts into Terraform `user_data` for automated bootstrap.
- Implement unit/integration tests and a CI workflow to exercise the prototype in staging.
