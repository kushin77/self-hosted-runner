GitOps Policy — Direct Deployments Only

Purpose:
This repository follows a direct-deploy, no-GitHub-Actions policy to ensure deployments are immutable, ephemeral, idempotent, and fully automated via operator-approved runbooks.

Policy:
- No GitHub Actions workflows are allowed in this repository. Any existing workflows must be removed and GitHub Actions disabled in repository settings.
- No PR-based release flows are permitted. Deployments are performed directly to `main` using approved operator-operated automation.
- All credentials must flow through GSM → Vault → (optional) KMS. No persistent service account keys are allowed in the repo or runner mounts.
- All changes that affect deployment or credentials must include runbooks and verification steps.
- Audit logs must be append-only JSONL and stored immutably.

Enforcement:
- A small helper script is provided at `scripts/enforce/no_github_actions_check.sh` to detect any workflows present.
- Operators should remove workflows and disable Actions at the org/repo level. When removal is approved, the `Close/remove any existing workflows` todo will be completed.

Direct Deployment Process:
- Developers commit directly to `main` following the repository's approval rules.
- Operator runs the curated automation (Terraform, provisioners, and validation scripts) from vetted hosts.
- Validation: `scripts/cloud/validate_gsm_vault_kms.sh` and `scripts/vault/sync_gsm_to_vault.sh`.

Contact: See `DEPLOYMENT_CREDENTIAL_HARDENING_SUMMARY.md` for the current status and operator issue links.