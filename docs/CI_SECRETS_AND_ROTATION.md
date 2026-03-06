CI secrets and deploy-key rotation

Purpose
- Document required GitLab CI/CD protected variables and recommended rotation practices for deploy keys and Vault credentials.

Required protected CI variables (set in GitLab: Project/Group → Settings → CI/CD → Variables)
- `GITHUB_MIRROR_SSH_KEY` (protected, masked) — private SSH key used by the mirror job to push to GitHub.
- `GITHUB_MIRROR_REPO` (protected) — target GitHub repo path (e.g. `org/repo`).
- `S3_BUCKET` or `RESTORE_S3_BUCKET` (protected) — S3 bucket URL for encrypted backups.
- `SOPS_KMS` / `AGE_KEY` (protected) — decryption key material or KMS config for `sops` or `age`.
- `GITLAB_API_TOKEN` (protected, masked) — token for API-driven project creation during restore (store at group-level if used).

Rotation guidelines
- Rotate deploy keys quarterly or immediately after personnel changes.
- Use separate keys per runner or service account to allow scoped revocation.
- Store decryption keys offline (two vault custodians) and rotate according to org policy.

How to add an SSH deploy key securely
1. Generate an ed25519 key pair on an admin machine: `ssh-keygen -t ed25519 -C "mirror-key-$(date -u +%Y%m%d)"`
2. Add the public key as a GitHub deploy key (write access) to the backup repo.
3. Add the private key to GitLab CI variables as `GITHUB_MIRROR_SSH_KEY` (protected+masked).

Audit and automation
- Record key rotation events in secure audit log (GCP KMS/AWS CloudTrail or internal change log).
- Consider an automated rotation job that generates new keys, updates GitHub deploy key via API, and rotates the CI variable (requires high-trust automation and is a one-off advanced task).
