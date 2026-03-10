Removed workflow artifacts (2026-03-10)

Files removed to enforce `no GitHub Actions` policy:

- .github/workflows.disabled/p2-prod-integration.yml
- .github/workflows.disabled/p2-vault-integration.yml

Action taken:
- Files were deleted from the repository to remove remaining Actions artifacts.
- If you prefer these to be preserved, they can be restored under `archived_workflows/` (this file) or a ZIP archive.

Reason:
- Repository policy `GITOPS_POLICY.md` mandates no GitHub Actions or PR-release workflows.

If you want the original contents restored here as an archived copy, reply and I will recreate the original YAML content under `archived_workflows/`.