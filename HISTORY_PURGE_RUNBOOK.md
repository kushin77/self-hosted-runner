# HISTORY PURGE RUNBOOK

Purpose: safely prepare and execute a git history purge for sensitive files discovered by gitleaks.

High-level steps:
1. Coordinate maintenance window and notify contributors (force-push will rewrite history).
2. Create an offline backup bundle from a secure host:
   ```bash
   git clone --mirror https://github.com/kushin77/self-hosted-runner.git repo.git
   cd repo.git
   git bundle create ../backup-repo.bundle --all
   ```
3. Identify sensitive paths (from `reports/secret-scan-report-redacted.json`).
4. Run `git filter-repo` in the mirror repo using `--invert-paths` to remove paths.
   Example:
   ```bash
   git filter-repo --invert-paths --paths artifacts/discovery/sa_keys.json \
     --paths nexusshield/infrastructure/terraform/production/terraform-apply-production-20260310-031213.log \
     --paths artifacts/audit/credential-rotation-20260311.jsonl --force
   ```
5. Verify results: run `gitleaks` on the rewritten repo, validate no findings, and confirm functionality if possible.
6. Force-push cleaned history to `origin`:
   ```bash
   git push --force --all
   git push --force --tags
   ```
7. Rotate any credentials that were exposed and add rotated values to GSM/Vault/KMS.
8. Append remediation and verification entries to `audit-trail.jsonl` and upload the file to the immutable audit bucket.

Notes:
- Do not run any step that force-pushes without a confirmed maintenance window and backups.
- `git filter-repo` must be installed on the secure host (`pip install git-filter-repo`).
