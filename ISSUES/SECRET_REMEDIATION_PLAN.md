Title: Secret Remediation & Git History Purge Plan

Status: Draft — run scanners and confirm findings before purging history.

Goal
- Identify any real secret exposures (API keys, private keys, tokens) and remediate by rotation.
- Purge any confirmed secret material from Git history (only after rotation), and enforce policies to prevent recurrence.

Immediate notes
- Automated scans attempted: `gitleaks` was run but the environment did not persist the JSON report; `trufflehog` and `git-secrets` are not installed in this environment so a fallback regex scan was performed producing `secret-scan-findings.txt` (many matches are documentation or templates). Do NOT purge history until findings are manually reviewed and secrets are confirmed.

Step 1 — Prepare
1. Notify stakeholders and schedule a maintenance window for history rewrite if secrets need purging.
2. Backup the repository and refs:

```bash
# create a mirror clone backup
git clone --mirror git@github.com:owner/repo.git repo-backup.git
cd repo-backup.git
git reflog expire --expire=now --all; git gc --prune=now --aggressive
tar czf ../repo-backup-$(date -u +%Y%m%dT%H%M%SZ).tgz ..
```

Step 2 — Install and run high-fidelity scanners
- On a secure, isolated host with network access, install: `trufflehog` (v3+), `gitleaks` (v8+), and `git-secrets`.

TruffleHog example:
```bash
# install trufflehog v3 (example)
pip install trufflehog
trufflehog filesystem --path /path/to/repo --json > /tmp/trufflehog-report.json
```

Gitleaks example:
```bash
gitleaks detect --source /path/to/repo --report-format json --report-path /tmp/gitleaks-report.json
```

git-secrets (AWS pattern checks):
```bash
git secrets --register-aws --global
git secrets --scan -r /path/to/repo > /tmp/git-secrets-report.txt
```

Step 3 — Review findings
1. Consolidate reports and triage each finding: file path, commit SHA(s), and evidence snippet.
2. For each confirmed secret exposure, create a rotation ticket and rotate the credential immediately in GSM/Vault/KMS before any history rewrite.

Step 4 — Purge history (ONLY AFTER ROTATION)
Use `git-filter-repo` (preferred over BFG). Example to remove a file or a pattern:

```bash
# Install git-filter-repo: https://github.com/newren/git-filter-repo
git clone --mirror git@github.com:owner/repo.git
cd repo.git
# Example: remove a single file path
git filter-repo --invert-paths --paths path/to/secret-file

# Example: remove by content using replace-text
cat > regex-to-remove.txt <<'EOF'
REGEX-TO-MATCH-SECRET
EOF
git filter-repo --replace-text regex-to-remove.txt

# Cleanup and push
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force --all
git push --force --tags
```

Step 5 — Post-purge actions
1. Rotate any secrets again if there is doubt.
2. Notify teams of forced-pushes and require local clones to re-clone or run `git fetch --all && git reset --hard origin/main`.
3. Re-enable CI and run full validation pipelines.

Step 6 — Hardening & Prevention
- Enforce pre-commit secret scanning hooks and CI gates (gitleaks or similar) to block commits containing secrets.
- Add a repository policy (done): `prohibit:github_actions` job and `NO_GITHUB_ACTIONS_POLICY.md` to block GitHub Actions files.
- Ensure all runtime secrets are stored in GSM/Vault and referenced only as environment variables or secret mounts.

Owner: @admin-team

If you want, I can:
- run `trufflehog` and `gitleaks` in this environment if you allow installing tools (may require network). 
- prepare a dry-run `git-filter-repo` command list for each confirmed secret commit (requires the list of offending SHAs).
