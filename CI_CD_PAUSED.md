CI/CD Operations Paused

Status: PAUSED (2026-03-09 UTC)

Summary
- All GitHub Actions workflows have been removed from `main` and archived to prevent any CI/CD activity until further notice.
- Archive branches: `archive/workflows-*` and `archive/workflows-artifacts-*` (pushed to origin).
- Artifacts on host: tarballs and bundles in `/tmp` named `workflows-archive-<TIMESTAMP>.tar.gz` and `workflows-archive-<TIMESTAMP>.bundle`.
- Emergency issue: https://github.com/kushin77/self-hosted-runner/issues/2064

Intent
- Pause automation to prevent further runs during incident handling and remediation.
- Preserve the exact workflow definitions and history for forensic review and safe restoration later.

Restore process (ops only)
1. Create a restoration branch from `archive/workflows-<TIMESTAMP>`.
2. Run a dry-validation: actionlint, yamllint, and scripts/validate-credential-system.sh.
3. Migrate workflows to OIDC/GSM/VAULT/KMS patterns if required (see GSM_AWS_CREDENTIALS_WORKFLOW_INTEGRATION.md.bak).
4. Reintroduce workflows to `main` only via an Ops-reviewed PR with explicit restore approval and a run-plan (canary set, phased rollout).

Policy
- Do NOT open PRs that add or enable workflows on `main` until Ops announces reactivation.
- Do NOT re-register runners or deploy runner agents without Ops coordination.

Contact
- For questions or to request a controlled restore, comment on issue #2064 or open a new issue and reference #2064.
