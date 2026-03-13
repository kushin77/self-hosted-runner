# NOTICE: Repository history rewrite — Immediate action required

Date: 2026-03-13 (UTC)

Summary
- The repository history on `main` was rewritten to remove committed sensitive data.
- Backup tag created: `backup/main-before-history-purge-20260313T0042Z` (do not delete).
- This is an emergency remediation action to reduce exposure; follow the instructions below.

What you must do (recommended: reclone)
- Recommended (cleanest): reclone the repository into a new directory:

```bash
git clone https://github.com/kushin77/self-hosted-runner.git
cd self-hosted-runner
git checkout main
```

- Alternative (update existing clone): if you cannot reclone, run these commands (this will discard local changes):

```bash
git fetch origin --prune
git checkout main
git reset --hard origin/main
git clean -fdx
```

- If you have local branches with work you need to keep, create patches or branch them off before resetting.

Why this matters
- The history purge removed sensitive entries that were committed earlier. After a history rewrite, all local clones with previous history are incompatible with `main` and must be reconciled.

Backup and audit
- Backup tag: `backup/main-before-history-purge-20260313T0042Z`
- Audit: see `reports/HISTORY_PURGE_AUDIT_20260313.md` and `audit-trail.jsonl` for details.

Next steps for maintainers
- Rotate any external keys/tokens that may have been exposed.
- Inform your teams to reclone or reset as above.

Contact / Questions
- Open an issue in the repository or tag @repo-admins for urgent help.

