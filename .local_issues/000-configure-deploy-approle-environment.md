Title: Configure `deploy-approle` repository environment and approvers

Summary:
- The workflows now include a gated `provision-approle` job that requires the `deploy-approle` environment approval before generating Vault AppRole credentials.
- Repository admins must create the `deploy-approle` environment, configure required reviewers/approvers, and set protection rules.

Action items for admins:
- Create repository environment named `deploy-approle`.
- Add required reviewers/approvers (team or individuals allowed to approve provisioning runs).
- Optionally configure allow-list for GitHub Actions if needed.
- Verify a dry-run by triggering the `provision-approle` job in a test branch and approving it.

Why:
- This approval gate prevents automatic, unaudited AppRole creation while allowing operator-approved provisioning that is auditable and reproducible.

Files referencing environment:
- `.github/workflows/deploy-immutable-ephemeral.yml`
- `.github/workflows/deploy-rotation-staging.yml`

If you want, I can open a GitHub issue/PR or create a checklist for admins; confirm and I'll post it upstream.
