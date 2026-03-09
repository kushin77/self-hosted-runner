Secrets Handoff: GSM / Vault / KMS (Guidance)

Goal: Remove long-lived secrets from repository and workflows; use OIDC and short-lived credentials from GSM (GCP Secret Manager), Vault, or cloud Secret Manager + KMS.

Principles
- Immutable: never commit secret material to repo; secrets remain in external secret manager with audit logs.
- Ephemeral: obtain short-lived tokens via OIDC (GitHub Actions id-token) or workload identity.
- Idempotent: retrieval helpers are deterministic and safe to run multiple times.
- No-ops (hands-off): rotations and key management automated via CI workflows.

Workflows (examples)
- GitHub Actions + HashiCorp Vault:
  - Grant `id-token: write` permission in workflow and configure Vault OIDC auth role bound to repo/org.
  - Use `scripts/vault_oidc_login.sh` to exchange GitHub OIDC token for a Vault token at runtime.
  - Read secrets with `curl -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/data/...` or use `vault` CLI.

- GCP Secret Manager (GSM) + Workload Identity:
  - Use GCP Workload Identity to allow GitHub Actions to impersonate a service account, or use `google-github-actions/auth` to fetch an access token.
  - Use `gcloud secrets versions access latest --secret=projects/PROJECT/secrets/NAME` in a step (token retrieved via OIDC).

- AWS Secrets Manager + OIDC (AssumeRoleWithWebIdentity):
  - Use GitHub OIDC to call AWS STS AssumeRoleWithWebIdentity, receive temporary credentials, then call AWS Secrets Manager / KMS.

Key Rotation & Signing Keys
- Store signing keys (cosign private key) encrypted in Vault KV v2 or cloud-secret-manager with restricted access.
- Rotate keys using automated workflow `.github/workflows/cosign-key-rotation.yml` that generates a new keypair and stores it securely.
- Workflows should read keys at runtime via OIDC→Vault and never store private keys as repo secrets.

Operational Checklist
- [ ] Ensure `VAULT_ADDR`, `VAULT_ROLE` (or cloud equivalents) are configured in org secrets.
- [ ] Remove long-lived tokens from repository secrets; replace with retrieval from external stores.
- [ ] Configure audit logging and rotation policies in Vault/GSM/KMS.
- [ ] Validate retrieval helpers in staging before promoting to production.

References
- `scripts/vault_oidc_login.sh` — example OIDC→Vault login helper.
- `.github/workflows/examples/vault-oidc-get-secret.yml` — example workflow demonstrating retrieval.
- `.github/workflows/cosign-key-rotation.yml` — rotation workflow for cosign keys.
