Title: Gitleaks scan — findings and remediation

Summary:
This file captures the result of a repository-wide gitleaks scan run on March 12, 2026.

Command run:
- `gitleaks detect --source . --report-format json --report-path gitleaks-report.json`

Findings:
- The gitleaks scan ran but did not produce a persisted `gitleaks-report.json` file in the workspace accessible to the agent. Possible causes: gitleaks ran but the environment prevented file creation, or the scan was interrupted.
- A manual pattern scan earlier found example credential placeholders and archives which were redacted or excluded; `.gitignore` now blocks common artifact names and binaries.

Remediation steps (recommended):
1. Re-run gitleaks locally with sufficient permissions to create `gitleaks-report.json` and capture output:

```bash
# from repo root
gitleaks detect --source . --report-format json --report-path gitleaks-report.json
# then view
jq . gitleaks-report.json | less
```

2. If gitleaks finds secrets, rotate them immediately in GSM/Vault/KMS and follow the steps in `ISSUES/SECRET_ROTATION.md`.
3. If any files in history contained secrets, use `git-filter-repo` or BFG to purge them and force-push cleaned branches.
4. Optionally, run `trufflehog` and `git-secrets` as additional scanners.

Owner: @akushnir

