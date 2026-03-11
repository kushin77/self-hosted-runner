**Secrets Remediation Runbook (safe, auditable)**

Purpose: coordinate removal of leaked secrets from git history, rotate exposed credentials, and harden repo so all credentials live in GSM/Vault/KMS.

Quick overview:
- Create backup branch and mirror; do local rewrites only (no push) until approved.
- Sanitize working tree, commit, then prepare replacement rules (`scripts/remediation/redact.txt`).
- Run `git filter-repo` in a mirror and verify.
- Rotate any exposed credentials (GSM, Vault, AWS, GitHub PATs) and provision new secrets into GSM/Vault/KMS.

Files added:
- `scripts/remediation/redact.txt` — replacement rules for git-filter-repo
- `scripts/remediation/run_filter_repo.sh` — mirror + dry-run/apply helper

Rotation checklist (per provider):
- GSM (Google Secret Manager):
  - Identify exposed GCP SA keys; disable old keys, create new SA + key if needed, store base64 JSON into GSM with replication=automatic.
  - Grant `roles/secretmanager.secretAccessor` to automator SA.

- Vault (HashiCorp):
  - Revoke old tokens, generate AppRole secret_id/role_id pair, store both in GSM.
  - Confirm AppRole login and rotate any wrapped tokens.

- AWS / KMS:
  - Identify exposed access key IDs; deactivate & delete old keys, create new IAM user/role and attach least-privilege policy.
  - If using KMS keys, rotate key or create new key; re-encrypt artifacts as needed.

- GitHub PATs / Tokens:
  - Revoke any exposed PATs immediately. Create new short-lived tokens if needed and store in GSM.

Operational safety:
- DO NOT force-push until maintenance window and contributor notification done.
- After rewrite and rotation, update repo docs with required direct-deploy instructions and new secret names.

Next actions (automated):
1. Run `bash scripts/remediation/run_filter_repo.sh` to preview matches (dry-run).
2. If results look correct, run `bash scripts/remediation/run_filter_repo.sh --apply` locally to rewrite mirror.
3. Coordinate force-push (not automated here). See detailed push steps in coordination section.
