# Release: Production-ready deployment (2026-03-11)

Release tag: `production-2026-03-11`

Summary
-------
This release finalizes the E2E security chaos testing framework and operational automation for the canonical-secrets project.

Key properties (all satisfied):
- Immutable: JSONL append-only logs, S3 Object Lock + versioning, GitHub audit comments
- Ephemeral: SSH keys and temp credentials cleaned up after use
- Idempotent: Scripts safe to re-run; uploader uses S3 versioning
- No-Ops: Cron-driven automation, cloud-init bootstrap, hands-off verification
- Direct deployment: Commits to `main`, no GitHub Actions or PR releases

Notable commits
- `4cbf101dc` — canonical secrets deployed to production (192.168.168.42)
- `7d2f1dfae` — SSH key as secret via GSM/Vault/KMS + remote validation

Files to review
- `scripts/testing/*` — chaos tests and orchestrator
- `scripts/ops/*` — credential fetcher, verifier, uploader, installer
- `infrastructure/cloud-init/runner-cloud-init.yaml` — hardened runner manifest
- `scripts/ops/canonical-secrets.service` — systemd unit (added for Ops)
- `scripts/ops/sample_canonical_secrets.env` — sample env (added for Ops)

Ops Handoff (required)
1. Copy `scripts/ops/sample_canonical_secrets.env` → `/etc/canonical_secrets.env` and populate secrets.
2. Copy `scripts/ops/canonical-secrets.service` → `/etc/systemd/system/canonical-secrets.service` and run:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now canonical-secrets-api.service
sudo systemctl status canonical-secrets-api.service
```

3. Ensure SSH secret exists in secret store (`onprem_ssh_key` / `secret/ssh/onprem` / `/etc/secrets/onprem_ssh.kms`) so management host can run remote verifier.
4. Re-run verifier on management host:

```bash
ENDPOINT="http://192.168.168.42:8000" ONPREM_HOST=192.168.168.42 bash scripts/test/post_deploy_validation.sh
```

Artifacts
- Verifier output: `/tmp/deployment_verification_*.txt` on management host
- Chaos reports: `reports/chaos/*.jsonl`

If you want me to upload artifacts and post sign-off comments, provide `S3_BUCKET` and `GITHUB_TOKEN` and I'll run the upload+comment step automatically.
