# Close: Disable GitHub Actions Workflows

Status: Closed

Action taken:
- Archived all non-sentinel GitHub Actions workflows to `archived_workflows/`.
- Added `scripts/enforce/disable_github_actions.sh` to perform the archival and removal.
- Added repository policy `POLICY_NO_GITHUB_ACTIONS.md` describing the enforcement and rationale.

Follow-up:
- Ensure server-side/pre-receive hooks (org-level) are configured to prevent re-enabling workflows, if available.
- Monitor repository for untracked workflow files in contributed patches.
