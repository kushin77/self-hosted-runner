# Hands-off Deploy Runbook (Immutable · Sovereign · Ephemeral · Idempotent)

This runbook documents the steps and requirements to enable the fully automated "hands-off" deploy flow implemented in the repository.

Goals:
- Immutable: no in-place edits; deploys write to immutable locations
- Sovereign: artifacts stored in self-hosted MinIO under your control
- Ephemeral: runtime state is transient and cleaned on restart
- Idempotent: second-run produces no changes
- Hands-off: optional automated provisioning and secret persistence for trusted automation

Prerequisites
- Provide the following repository secrets (Settings → Secrets):
  - `MINIO_ENDPOINT` — e.g. https://minio.example:9000
  - `MINIO_ACCESS_KEY`
  - `MINIO_SECRET_KEY`
  - `MINIO_BUCKET`
  - `VAULT_ADDR`
  - `GITHUB_ADMIN_TOKEN` (optional, required only for hands-off secret persistence)
  - `VAULT_ADMIN_TOKEN` (optional, required only for auto-provisioning AppRole)

Environments
- Create an environment named `deploy-approle` and add approvers (Repo Settings → Environments).

Workflows & Usage
- The deploy workflows (`deploy-immutable-ephemeral`, `deploy-rotation-staging`) will:
  1. Use `MINIO_*` secrets to store artifacts instead of GitHub-hosted artifacts.
  2. Attempt to fetch `VAULT_ROLE_ID`/`VAULT_SECRET_ID` from repo secrets; if missing and `VAULT_ADMIN_TOKEN` is provided, they will auto-provision an AppRole.
  3. If you run with the input `hands_off=true` and a repository secret `GITHUB_ADMIN_TOKEN` is present, workflows will persist generated `VAULT_ROLE_ID` and `VAULT_SECRET_ID` back into repository secrets via `gh secret set` (opt-in, guarded).

How to run the MinIO smoke test
1. Ensure MinIO secrets are set as above.
2. Go to Actions → MinIO Artifact Smoke Test → Run workflow (or open PR #750 and use the workflow dispatch link).
3. The job will upload and download a small test file and verify checksum.

How to perform a hands-off deploy (recommended flow)
1. Confirm `MINIO_*`, `VAULT_ADDR`, and either `VAULT_ROLE_ID/VAULT_SECRET_ID` or `VAULT_ADMIN_TOKEN` are configured.
2. If you want persistent automation, set `GITHUB_ADMIN_TOKEN` as a repo secret (grant `repo` and `secrets` write scope only to the automation principal).
3. Trigger the deploy workflow and set the input `hands_off=true`.
4. If approvers are required for `deploy-approle`, someone with approval rights must approve the provisioning job in the Actions UI.
5. After successful run, `VAULT_ROLE_ID`/`VAULT_SECRET_ID` will be persisted to repository secrets (if `hands_off` + `GITHUB_ADMIN_TOKEN`), enabling future runs without manual provisioning.

Security Notes & Best Practices
- `GITHUB_ADMIN_TOKEN` should be tightly scoped and only available to trusted automation (use a machine user or GitHub App with least privilege).
- Persisted secrets are sensitive: rotate `VAULT_SECRET_ID` periodically and use Vault policies to limit access.
- Approvers on the `deploy-approle` environment provide auditability and human oversight; keep the list minimal.

Troubleshooting
- If MinIO upload/download fails: verify runner network connectivity to `MINIO_ENDPOINT`, TLS trust, and secret values.
- If AppRole provisioning fails: check `VAULT_ADMIN_TOKEN` permissions and Vault audit logs.
- If `gh secret set` fails: ensure `GITHUB_ADMIN_TOKEN` has permissions and the `gh` CLI is available on the runner.

Related Draft issues & Issues
- MinIO helpers and workflow migration: PR #746
- MinIO smoke-test workflow: PR #750
- Hands-off AppRole persistence: PR #760
- Ops tasks: Issue #748 (MinIO secrets) and Issue #749 (deploy-approle environment)

Contact
- For operational help, mention `@platform` team or open a new issue and tag `ops`.
