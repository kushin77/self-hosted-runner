# Migration Complete: Disable PR Workflows & Move to Direct Deploys

Status: Completed — 2026-03-09 UTC

Summary
- Pull-request-driven automation and scheduled workflows have been disabled or set to manual-only `workflow_dispatch`.
- `CODEOWNERS` auto-assignment was archived to `.github/.disabled/CODEOWNERS` to prevent automatic reviewer assignment.
- Dependabot and other automation were archived to `.github/.disabled/` where present.
- A migration note (`MIGRATION_AWAY_FROM_WORKFLOWS.md`) was added to the repo root.

Operational guarantees
- Immutable: deploy artifacts and logs must be recorded with SHA256 and immutable storage.
- Ephemeral: runners and intermediate resources are ephemeral and cleaned up after runs.
- Idempotent: deployment scripts updated to be safe to run repeatedly (`deploy.sh`, `orchestrate_production_deployment.sh`).
- No-Ops & Hands-off: default behavior is manual dispatch to authorized operators; secrets use GSM/VAULT/KMS.

Next steps
- Validate secret backends (GSM / Vault / KMS) are configured for all operators and runners.
- Run a canary manual dispatch for core workflows to verify manual run experience.
- Update operator runbooks and `CONTRIBUTING.md` to document the new direct-deploy workflow.

If rollback is needed, move files from `.github/.disabled/` back to their original locations and restore schedule/triggers.
