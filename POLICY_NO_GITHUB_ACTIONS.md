# Repository Policy: No GitHub Actions

This repository enforces a "no GitHub Actions" policy. All CI/CD and deployment automation must run via the repository's direct deployment tooling (see `scripts/deploy/direct_deploy.sh`) or operator systems outside GitHub Actions.

Key requirements:
- No workflows with triggers are allowed in `.github/workflows/` (only `disable-workflows.yml` sentinel is permitted).
- Any existing workflow files must be archived and removed from the active workflows directory — use `scripts/enforce/disable_github_actions.sh` to perform this action.
- Releases via pull requests are disallowed. Use direct deployment tools and operator-managed releases.
- All automation must be idempotent, immutable audit-logged, ephemeral where applicable, and hands-off (no manual approvals required).

See `scripts/enforce/disable_github_actions.sh` for operational enforcement steps.
