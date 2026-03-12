# History purge runbook — remove sensitive files from git history

Important: This is a destructive operation (force-push). Coordinate a maintenance
window with all contributors and create backups before proceeding.

Summary
- Files to remove from history: `.runner-keys/self-hosted-runner.ed25519`,
  `build/test_signing_key.pem`, `build/test_ssh_key`, and any other leaked keys.
- Goal: remove from all branches & tags, rotate credentials, and verify no secrets
  remain.

Preparation
1. Create a mirror clone as a backup:

```bash
git clone --mirror git@github.com:kushin77/self-hosted-runner.git repo-backup.git
cd repo-backup.git
git bundle create ../backup.bundle --all
```

2. Notify contributors and freeze pushes to the repository.

Runbook (non-interactive helper)

- Preferred safe flow (recommended): run the helper script `purge-history.sh` in
  a secure environment with `git-filter-repo` installed.

High-level commands (manual)

```bash
# mirror clone
git clone --mirror git@github.com:kushin77/self-hosted-runner.git to-purge.git
cd to-purge.git

# run git-filter-repo to remove paths
git filter-repo --invert-paths --paths .runner-keys/self-hosted-runner.ed25519 \
  --paths .runner-keys/self-hosted-runner.ed25519.pub \
  --paths build/test_signing_key.pem \
  --paths build/test_ssh_key

# verify
git for-each-ref --format='%(refname)' refs/heads | xargs -n1 -I{} git log -100 --pretty=oneline {}

# push results (force) once verified
git push --force --all
git push --force --tags
```

Post-purge steps
- Rotate any credentials that were exposed (create new keys off-repo).
- Seed secrets into Google Secret Manager (GSM) or Vault and update deployments
  to fetch from GSM (see `k8s/secretproviderclass-gsm.yaml`).
- Run a full repo secret scan (gitleaks) and attach the report to the incident.

Verification
- Run `gitleaks detect --source . --report-format json --report-path /tmp/secret-scan-report.json`
- Confirm the report contains no remaining cleartext/private keys.

Notes
- `git-filter-repo` is required. Do NOT use `git filter-branch` for large repos.
- Keep the backup bundle until verification completes.
