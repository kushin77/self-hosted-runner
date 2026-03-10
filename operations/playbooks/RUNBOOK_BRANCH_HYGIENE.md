Branch Hygiene Runbook

Purpose
- Document branch retention, naming, and cleanup procedures.

Retention
- Retain branches for 90 days since last commit. Weekly cleanup runs (Sunday 03:00 UTC).
- Exclusions: `main`, `develop`, `staging`, `production`, `release/*`, `hotfix/*`.

Naming
- Allowed prefixes: `release/`, `hotfix/`, `chore/`, `fix/`, `feat/`, `pr/`, `automation/`, `archive/`, `enhance/`, `migration/`, `ops/`, `test/`, `tmp_`.
- Rules: lowercase, no spaces, max 100 chars, allowed chars `[a-z0-9._\-\/]`.

Enforcement
- `Branch name lint` workflow validates branch names on push/PR.
- Branch protection requires `validate-policies-and-keda` and `Branch name lint` on protected branches.

Cleanup workflow
- Location: .github/workflows/cleanup-stale-branches.yml
- Behavior: deletes branch heads older than 90 days if no open PR exists; safe-list excludes above prefixes.
- Dry-run procedure: set `DRY_RUN=true` (add to script) or review logs in issue #2120 before live run.

Monitoring & Recovery
- Monitor workflow runs and check `Branch name lint` for failures for 24h after enforcement.
- If a branch-name check fails, open an issue with branch name and correct naming pattern; maintainers can rename or recreate branch.
- Deleted branches are permanent in GitHub; for accidental deletes, recreate from tag/commit if available.

Commands
- Audit branches locally:
  git fetch --all --prune
  git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:iso8601)' refs/heads

- Dry-run cleanup (example): use the cleanup workflow logs or run script with `DRY_RUN=true`.

- Apply branch protection (idempotent script):
  ./scripts/apply-branch-protection.sh --repo owner/repo --branch <branch> --token $GITHUB_TOKEN

Tracking
- Audit/cleanup tracking issue: https://github.com/kushin77/self-hosted-runner/issues/2120

Contacts
- Repo admins and governance team (repo-admins)
