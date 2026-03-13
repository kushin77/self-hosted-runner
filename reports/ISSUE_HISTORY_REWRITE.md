## URGENT: Repository history rewrite — immediate action required

The repository `main` branch history was rewritten to remove committed sensitive data.

- Backup tag: `backup/main-before-history-purge-20260313T0042Z`
- Draft PR with notice: https://github.com/kushin77/self-hosted-runner/pull/2918
- Audit: `reports/HISTORY_PURGE_AUDIT_20260313.md`

Actions for all consumers:
1. Recloning the repository is recommended. See the PR for exact instructions.
2. If you cannot reclone, run:

```bash
git fetch origin --prune
git checkout main
git reset --hard origin/main
git clean -fdx
```

Maintainers: rotate any external credentials you control and verify downstream services.

@repo-admins please review and broadcast to teams. Mark this issue as `security` and `incident`.