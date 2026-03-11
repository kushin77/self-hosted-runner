# Policy: No Pull-Request Releases

Status: Enforced

Summary:
This repository disallows release workflows triggered by GitHub pull requests or merges. All releases must be performed via direct deployment tooling and operator-managed processes to preserve immutability, auditability, and hands-off operations.

Requirements:
- No `release` or `pull_request` triggers in `.github/workflows/`.
- No automated GitHub-based releases or tags created by Actions or pull-request merges.
- All deployment workflows must use `scripts/deploy/direct_deploy.sh` or operator tools.
- Release artifacts must be recorded in the immutable audit log (`logs/deploy-audit.jsonl`).

Enforcement:
- `scripts/enforce/disable_github_actions.sh` archives workflows and prevents re-enabling in this repo tree.
- Operators should configure organization-level pre-receive hooks or branch protections to block workflow files and PR-based releases.

Next steps:
1. Notify maintainers and update contributor guide.
2. Validate no active release workflows remain.
