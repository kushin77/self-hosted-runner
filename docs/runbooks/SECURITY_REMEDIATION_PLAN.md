# Security Remediation Plan — gitleaks findings

Summary:
- This repository's documentation push triggered a `gitleaks-scan` branch-protection failure. The automated remediation tooling below helps locate leaked secrets, replace them with secure placeholders, and prepare a remediation PR.

Steps taken by automation:
1. `scripts/remediate-gitleaks.sh` performs a dry-run to list candidate matches and writes a summary to `/tmp/gitleaks_remediation_summary.txt`.
2. When executed with `--apply`, it creates `.bak` backups for modified files and replaces matched secret lines with a placeholder `<REDACTED_SECRET_REMOVED_BY_AUTOMATION>`.
3. The automation stages changes so a remediation branch commit can be made and a PR created.

Recommended follow-up manual steps:
1. Review the remediation branch diffs carefully; validate that no functional code was broken.
2. Rotate all affected credentials (GSM/Vault/AWS/GCP/GitHub) that were exposed. Treat all findings as compromised until rotation completes.
3. Re-run `gitleaks-scan` locally or via CI to confirm no remaining leaks.
4. Merge the remediation PR and then merge the documentation Draft issues once `gitleaks-scan` passes.
5. Improve developer guidance: add pre-commit gitleaks hook and CI preflight check to block accidental secrets in Draft issues.

Emergency contact: Security team and service owners must be notified immediately for rotation actions.
