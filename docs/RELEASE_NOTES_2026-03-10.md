# Release: go-live 2026-03-10

Summary:
- Archive of cloud-finalization logs and verification completed.
- Immutable audit entry appended to `logs/deployment/audit.jsonl`.
- `docs/INFRA_ACTIONS_FOR_ADMINS.md` updated with handoff and verifier instructions.
- All automation verified: immutable, ephemeral, idempotent, no-ops, hands-off.
- Credential strategy: GSM primary, Vault secondary, KMS tertiary for secrets.

Artifacts included (local):
- `artifacts-archive/system-install/go-live-finalize-*.log`
- `logs/deployment/audit.jsonl` (appended cloud-finalize entry)

Recommended next steps (manual push / release):
1. Review and push `release/go-live-2026-03-10` to remote and merge to `main`.
2. Create annotated tag `v2026.03.10` and push tag.
3. (Optional) Create GitHub issue noting the release and link audit SHA.

Security notes:
- Sensitive tfvars files are intentionally ignored (`terraform/terraform.tfvars`).
- Never store plaintext credentials in git; use the documented provisioning scripts.

