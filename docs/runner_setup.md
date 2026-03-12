# Self-hosted runner / external job setup (no GitHub Actions)

Purpose
- Provide guidance to provision a scheduled job or self-hosted runner that executes `scripts/automation/run_milestone_organizer.sh` on a secure host using OIDC→GSM/Vault/KMS for credentials.

Requirements
- A host where you control the runtime (VM, Kubernetes job, or on-prem server).
- `gh`, `jq`, `python3`, and the repo checked out on the host.
- Credential integration: use GSM, Vault, or KMS to provide `GH_TOKEN` to the job via a minimal credential helper. Do NOT store tokens in plaintext in the repo.

Recommended architecture
- Provision a small ephemeral VM or Kubernetes CronJob that:
  - Boots with minimal image (Ephemeral)
  - Mounts a short-lived secret (GH token) fetched from GSM/Vault/KMS
  - Runs `scripts/automation/run_milestone_organizer.sh` on schedule (cron or systemd timer)
  - Writes audit artifacts to an append-only object store (GCS/S3) or to the `artifacts/milestones-assignments/` path and copies to secure archival storage.
    Optionally configure archival by setting `ARCHIVE_S3_BUCKET` (S3) or `ARCHIVE_GCS_BUCKET` (GCS) in the runner environment; the wrapper will upload artifacts and a SHA-256 checksum for each file.

Credential flow examples
- GSM (GCP Secret Manager): use a service account with access to the secret; job fetches the secret at runtime and exports `GH_TOKEN` for `gh auth login --with-token`.
- Vault: use AppRole or Kubernetes auth to fetch the secret at runtime; export `GH_TOKEN`.
- KMS: encrypt a token blob in secure storage and decrypt at runtime; do not persist decrypted token on disk.

Security notes
- Principle of least privilege: token must only have `repo` scope and be restricted to the specific repository.
- Rotate tokens regularly and use short-lived tokens where possible.
- Audit logs must be retained externally (GCS/S3) for immutability.

- Scheduling
- Use `cron` or `systemd` timers to run the script at a cadence (daily/nightly) appropriate for your workflow.

No GitHub Actions
- This project policy forbids GitHub Actions. Use the above local/external runner approach.

Archival and retention
- The wrapper uploads artifacts with a timestamped filename and creates a corresponding `.sha256` checksum. After upload, configure bucket lifecycle policies or object lock to enforce immutability/retention per your compliance needs.
