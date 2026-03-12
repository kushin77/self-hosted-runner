Workflow archive and secret scanning

This PR adds helper scripts to identify and safely archive GitHub Actions workflows, and to scan the repository for potential secrets.

Scripts added:
- `scripts/ops/find-github-workflows.sh` — list existing `.github/workflows` files and archived copies.
- `scripts/ops/archive-github-workflows.sh` — moves `.github/workflows/*` into `archived_workflows/<timestamp>/.github/workflows/` using `git mv` and leaves a README placeholder.
- `scripts/ops/scan-secrets.sh` — heuristic scanner using `git grep` and optional `gitleaks` invocation.

Recommended process:
1. Run `./scripts/ops/find-github-workflows.sh` to review current workflows.
2. Run `./scripts/ops/scan-secrets.sh` and review the generated report. If secrets are found:
   - Rotate the secret in the external service immediately.
   - Create a new secret in GSM or Vault.
   - Replace references in Cloud Build triggers to use GSM (see `docs/REPO_DEPLOYMENT_POLICY.md`).
   - Remove the secret from git history (use `git filter-repo` or `bfg`), but coordinate with security team.
3. If ready, run `./scripts/ops/archive-github-workflows.sh`, commit the changes, and push your branch to open a PR that archives the workflows.

Notes on safety:
- These scripts do not automatically remove secrets from history. Removing secrets is a destructive operation and must be coordinated with the security team and CI.
- Archiving workflows keeps an auditable copy under `archived_workflows/` and prevents accidental reactivation.

Contact: @kushin77, @BestGaaS220 for approvals and coordination.