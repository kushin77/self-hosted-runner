# Issue: #2066 — Onboard secrets per environment (operator action)

Status: Draft

Summary:
The auto-provisioning system requires production secrets to be added to credential providers or repository secrets so Phase 2 validation can complete. This issue tracks onboarding per environment (dev/stage/prod).

Action items:
- [ ] Operator: Populate `VAULT_ADDR`, `VAULT_ROLE`, `AWS_ROLE_TO_ASSUME`, `GCP_WORKLOAD_IDENTITY_PROVIDER` in provider(s).
- [ ] CI: Verify provisioning with `make -f Makefile.provisioning provision-fields` and `verify-provisioning`.
- [ ] Ops: Monitor `logs/deployment-provisioning-audit.jsonl` for first run.

Notes:
- For quick set via CLI, see `OPERATOR_ACTION_REQUIRED.md` at repo root.
