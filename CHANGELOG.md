# Changelog

## 2026-03-11 - secrets-orchestrator operator deployed (operator-run)
- Operator-driven provisioning and verification completed (no GitHub Actions).
- Service account `secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com` created and IAM bound.
- Terraform references applied for Workload Identity / KMS crypto key (existing key ring referenced).
- Final health-check run in `--apply` mode; `azure-client-id` mirrored to Azure Key Vault.
- Immutable audit logs and artifacts saved under `artifacts/`:
  - `artifacts/OPERATOR_PROVISIONING_COMPLETE.md`
  - `artifacts/terraform/`
  - `artifacts/local_secrets_health/`
  - `artifacts/secret_mirror/`
  - `artifacts/verify/`
- Rollback playbook added: `scripts/rollback/rollback_secrets_orchestrator.sh` (dry-run by default).
- CI-free smoke test and hourly systemd timer added: `scripts/verify/smoke_check.sh`, `scripts/verify/smoke_check.timer`.

Notes: This change was applied directly by operator automation and validated green. For rollback or further automation, see `scripts/rollback/` and `artifacts/OPERATOR_PROVISIONING_COMPLETE.md`.
