# Secrets Inventory & Handling Guidance

This document maps where credentials and secrets are stored, and prescribes handling, rotation and audit procedures.

Principles
- Immutable: Secrets are stored in managed secret stores (GSM/Vault) and never committed to Git.
- Ephemeral: Where possible, short-lived credentials are used (STS, ephemeral tokens).
- Idempotent: Provisioners re-apply state without creating duplicates.
- Hands-off: All runtime services read secrets from GSM/Vault/KMS; no manual plaintext insertion.

Primary secret stores
- Google Secret Manager (GSM): production secrets and rotation automation.
- HashiCorp Vault: dynamic secrets for databases, SSH, and rotation workflows.
- KMS: key-encryption and signing keys stored in KMS-backed keyrings.

Repository references
- `scripts/ops/` and `docs/` contain runbooks that show *how* to provision secrets — they must reference GSM/Vault, not hard-coded values.
- `.gitignore` includes patterns to prevent archived artifacts and binaries that may contain secrets from being committed.

Rotation & remediation
1. If a secret is found in the repository (committed at any point), rotate it immediately and purge history:
   - Create replacement secret in GSM/Vault.
   - Update consuming services to reference the new secret (via env or mount).
   - Purge the old secret from git history using `git-filter-repo` or BFG and force-push the cleaned branches.
2. Open an incident ticket documenting the exposure and rotation steps (example: `ISSUES/SECRET_ROTATION.md`).

Audit
- Ensure secret-access logs are enabled for GSM/Vault and retained according to the governance policy.
- Periodically run secret-scanning tools (truffleHog, git-secrets, internal scanners) on branches and PRs.

Operational checklist
- [ ] Confirm all environment variables in `docs/` and `scripts/` use placeholders and reference GSM/Vault.
- [ ] Ensure `secrets.*` patterns are enforced in pre-commit hooks and CI pipelines.
- [ ] Rotate any exposed credential and record rotation event in the audit log.

Contact
- Security / On-call: @admin-team
Secrets Inventory — NexusShield (consolidated)

Purpose

This file consolidates all repository and operator knowledge about secrets referenced in repo docs, runbooks, and automation scripts. Use it as the single source of truth for operator actions (enable versions, grant access, rotate, audit).

Location: Google Secret Manager (project `nexusshield-prod` unless otherwise noted)

Core secrets (names found across repo):

- automation-runner-vault-role-id
  - Purpose: Vault AppRole `role_id` for the automation runner AppRole login.
  - Used by: `scripts/cloud/run_validate_with_approle.sh`, Cloud Run templates (env mapping)
  - Action: Ensure an ENABLED version exists (latest) and the runner's service account has `secretmanager.versions.access`.

- automation-runner-vault-secret-id
  - Purpose: Vault AppRole `secret_id` for the automation runner.
  - Used by: AppRole wrapper and operator-run validation.
  - Action: Ensure an ENABLED version exists (latest) and is stored securely.

- gcp-terraform-sa-key
  - Purpose: Service account JSON for Terraform operations (used by automation-runner/terraform flows).
  - Used by: Terraform applies, bootstrap scripts.
  - Action: Keep encrypted and rotate per schedule. Prefer WIF where possible.

- nexusshield-portal-firestore-config-production
  - Purpose: Application-specific production Firestore config.
  - Used by: Portal infrastructure (Terraform-managed secret)

- vault_unlock_key
  - Purpose: Vault unseal/auto-unlock key artifact (if used).
  - Action: Treat as highly sensitive — store in GSM with restricted IAM.

- github-token
  - Purpose: GitHub API token used by limited automation (avoid where possible).
  - Action: Rotate and restrict scopes; prefer operator-managed operations.

- database_secret, production-portal-db-password, production-portal-db-username, nexusshield-portal-db-username-production
  - Purpose: Database credentials for portal
  - Action: Keep in GSM, read by Vault sync flows and application via Vault.

- runner_ssh_key, runner_ssh_user, RUNNER_SSH_KEY, RUNNER_SSH_USER
  - Purpose: Runner SSH credentials for operator access
  - Action: Ensure minimal access, rotate keys periodically.

- nxs-portal-sa-key-v2-1773110201, other SA keys
  - Purpose: Historical service account keys; prefer disabling and using WIF or rotating via GSM+Vault+KMS flow.

- nexusshield-tfstate-backup-key
  - Purpose: Key used to encrypt tfstate backups
  - Action: Confirm KMS policy and rotate if needed.

Notes & Actions for Operators

- Single Source: Use this file as the canonical inventory. If you add or rotate a secret, update this file and post a short comment on issue #2343.

- ENABLED Versions: For AppRole-based validation the secrets `automation-runner-vault-role-id` and `automation-runner-vault-secret-id` must have ENABLED versions (versions must exist). Use `gcloud secrets versions add ...` to create a new version.

- Access Controls: Grant the automation runner service account (`nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com`) the `roles/secretmanager.secretAccessor` and `roles/secretmanager.viewer` as needed. Principle of least privilege applies.

- Provisioning Best Practices:
  - Prefer Workload Identity Federation (WIF) for Google Cloud identities over long-lived SA keys.
  - Store AppRole IDs/Secret IDs in GSM and never check into Git.
  - Use Vault Agent token sink (`/var/run/secrets/vault/token`) when deploying containers for runtime auth.
  - Automate secret rotation and ensure audit trails are append-only JSONL.

- Validation Checklist (operator-run):
  1. Verify GSM secrets list: `gcloud secrets list --project=nexusshield-prod`
  2. Verify ENABLED versions: `gcloud secrets versions list automation-runner-vault-role-id --project=nexusshield-prod --filter="state=ENABLED"`
  3. Ensure `VAULT_ADDR` reachable from the runner and Vault CLI present.
  4. Ensure the runner has access to the GSM secrets (service account or WIF).
  5. Run: `./scripts/cloud/run_validate_with_approle.sh` (requires `VAULT_ADDR` + AppRole values via GSM or files)

Audit & Documentation

- Whenever you add a secret version, append a short note to this file and to issue #2343 so the agent retries validation automatically.
- Keep secrets labels (`component`, `env`, `managed-by`) consistent for fast discovery.

Contact

- Operator POC: @kushin77 (assigned to issue #2343)
- For emergencies: follow `docs/runbooks/credential_unblock_runbook.md`

Created: 2026-03-10 — Consolidated by automation agent
