Governance: Releases, Tags, and Secret Vault Policy

- Objective: Enforce NO GitHub Actions, NO PR-based releases, and prevent tag-based releases. Use GSM → Vault → KMS as the canonical credential vault chain.

Releases & Tags
- GitHub Releases are prohibited by policy. Server-side prevention is not available; we enforce this via branch protection, tag-push restrictions, and local git hooks.
- Local hooks: `.githooks/prevent-tags` blocks tag pushes by default; `scripts/install-githooks.sh` installs them.
- CI/workflows: All files under `.github/workflows` have been archived/removed and a pre-commit hook prevents re-adding workflows.
- Enforcement is idempotent: re-running `scripts/github/orchestrate-governance-enforcement.sh` re-applies the same settings safely.

Secrets & Key Vaults
- Secrets MUST be stored in an external vault chain: GSM -> Vault -> KMS (Key Vault) for signing and encryption.
- Do NOT store credentials in repository files or repo secrets. Use ephemeral tokens obtained via OIDC where possible.
- Steps to retrieve secrets (recommended automated flow):
  1. Request short-lived token from GSM.
  2. Use Vault AppRole (or equivalent) to exchange for ephemeral secret material.
  3. Use KMS to decrypt/unwrap if necessary.

Audit Trail
- All enforcement steps are recorded in committed docs (`docs/GOVERNANCE_ENFORCEMENT.md`, `issues/1615-AUTOMATION-RECORD.md`) and closed issues (#1615, #1648).

If you need a deploy-time helper to fetch secrets, I can add a small helper that uses OIDC to fetch a GSM secret and then an AppRole to Vault, then call KMS unwrap. Ask if you want that helper added.