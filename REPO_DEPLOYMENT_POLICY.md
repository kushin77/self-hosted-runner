Repository Deployment Policy
==========================

Summary:
- GitHub Actions and PR-based automated releases are disabled for this repository.
- Direct development and direct deployment are permitted for authorized admins/operators.
- All credentials must be provided via GSM / HashiCorp Vault / KMS (no hard-coded keys).
- Immutable audit trail: all deployments must append a JSONL audit entry to `nexusshield/logs/*.jsonl`.
- Deployments must be idempotent and documented; use `scripts/direct-deploy-production.sh` for production.

Operational rules:
- Never commit service account keys, vault tokens, SSH private keys, or terraform state files.
- Use the `nexusshield/ops/deploy_bundle` for out-of-band installs when needed.
- Install the local git hooks to prevent accidental workflow additions (`scripts/install-githooks.sh`).

Contacts:
- Repo owner: @kushin77
- Security: see issue #2210 for credential rotation and history purge.
