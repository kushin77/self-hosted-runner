This directory previously contained service private keys. Private keys must never be stored in the repository.

If a key file is present it has been removed and replaced by this README. Immediately rotate/revoke any keys that were present and follow the rotation instructions below.

Rotation checklist:
- Revoke the exposed key (SSH or service account) from the provider console.
- Generate a new key pair or service account key.
- Store the secret in the secure store: GSM, Vault, or GitHub Actions secrets (or better: OIDC + short-lived credentials).
- Update automation/workflows to reference the secret via the secret manager instead of checked-in files.
- Run `scripts/audit-secrets.sh --full` and re-run `gitleaks-scan`.

If you are the owner of this repository and need help rotating keys, follow `SECRETS_EMERGENCY_RESPONSE.md`.
