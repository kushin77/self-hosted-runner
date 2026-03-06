Title: Triage pre-commit secret scanner findings (local)

Purpose:
- Provide a triage checklist and owner for items flagged by the pre-commit secret scanner on the self-hosted runner.

Tasks:
- Reproduce scanner finding locally and capture the exact filename, line, and matched pattern.
- Determine if the finding is a false positive; if so, add a justification entry to `.gitignore-secrets`.
- If the finding contains example values too close to real secrets, redact and replace with placeholders.
- Re-run local pre-commit checks to validate the fix.

Reference: This was used to triage `scripts/ci/setup-approle.sh` previously; ensure other similar scripts are checked.
