# Issue #2275 — Monthly Credential Rotation & Validation (OPEN)

Status: OPEN

Schedule: 2nd Friday of each month

Purpose: Validate GSM→Vault→KMS rotation and fallback chain; verify no secrets in repo.

Checks:
- `provision-multi-layer-secrets.sh` rotation test
- Audit JSONL logs for credential operations
- `.gitignore` contains credential patterns
- No plaintext secrets in `git grep -n "KEY\|PASSWORD\|SECRET"`

Remediation: Trigger rotation script and validate service reconnects; escalate if any secret exposure found.
