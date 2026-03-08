# GCP KMS → GitHub Secrets helper

This document describes a helper to decrypt ciphertext using GCP KMS and write the plaintext to a GitHub Actions repository secret.

Prerequisites
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- The ciphertext to decrypt must be available on the runner, e.g., stored temporarily in the repo workspace or fetched by a prior step (artifact or GSM retrieval).

Quick local usage:

```bash
# decrypt local ciphertext and set secret
./scripts/ops/kms_decrypt.sh --project myproj --location global --keyring my-kr --key my-key --ciphertext-file ./ct.bin --repo kushin77/self-hosted-runner --secret-name SLACK_WEBHOOK_URL
```

Automation via Actions
- We added `.github/workflows/kms-decrypt-run.yml` which can be run manually. Configure the repo secrets for the key identifiers and the ciphertext path before running.

Security notes
- Ensure ciphertext files are ephemeral and removed after use. The included script uses a temp file that is deleted on exit.
- Do not commit plaintext or ciphertext blobs into the repository history.
