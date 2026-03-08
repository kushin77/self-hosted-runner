# Operator Deployment Guide — Secrets Orchestration

This guide describes the operator steps to provision cloud trusts and enable the repository's automated secrets orchestration.

Prerequisites
- Access to the organization/project cloud consoles (GCP, AWS) and Vault admin.
- `gh` CLI configured with a user that can create repository secrets and issues.

Quick steps
1. Review `infra/` Terraform templates and `infra/setup-secrets-orchestration.sh`.
2. Run the `infra/setup-secrets-orchestration.sh` in a secure operator environment (one-time, idempotent):

```bash
cd $(git rev-parse --show-toplevel)/infra
chmod +x ./setup-secrets-orchestration.sh
./setup-secrets-orchestration.sh
```

3. Confirm outputs and add repository secrets (the script will attempt this when possible):
- `GCP_PROJECT_ID`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `VAULT_ADDR` (and follow secure Vault provisioning/unseal)
- `AWS_KMS_KEY_ID`

4. After provisioning, trigger the health check on `main`:

```bash
gh workflow run 'secrets-health-multi-layer.yml' --ref main
```

5. Monitor the run, collect artifacts, and confirm health is green. If green, close incident issues and merge the PR.

Notes
- The `setup-secrets-orchestration.sh` is idempotent and safe to re-run.
- If you need assistance, reference `SECRETS_REMEDIATION_STATUS_MAR8_2026.md`.

Contacts
- Automation owner: ops@example.com
