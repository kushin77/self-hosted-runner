Refactor & Consolidation Summary — 2026-03-11

Summary:
- Consolidated duplicate Terraform pin updater implementations into canonical `tools/terraform_pin_updater.py`.
- Replaced `scripts/utilities/terraform_pin_updater.py` with a thin shim that delegates to the canonical script.
- Added `backend/lib/utils.js` and migrated shared helpers (`generateId`, `generateToken`, `logAuditEntry`, `auditTrail`) to that module.
- Updated `backend/server.js` and `backend/index.js` to import and use `backend/lib/utils.js` and to use an immutable JSONL audit trail.

Goals met:
- Immutable: Audit entries append-only to `logs/portal-api-audit.jsonl` and `.phase2-image-pin/image_pin.jsonl`.
- Idempotent: Terraform updater uses idempotent update patterns and creates `.bak` backups before writes.
- Ephemeral: no long-lived state added; in-memory maps are intentionally ephemeral.
- No-Ops / Hands-Off: Changes favor automation and direct commit to `main` (script requires being on `main` branch).
- Secrets: backend keeps GSM/KMS integrations for credential storage (server.js helpers retained).
- Direct development/deployment: scripts are designed for direct local commits (no GitHub Actions or PRs).

Next recommended steps (manual or automated):
- Verify runtime on a staging environment: start `backend/server.js` and run smoke health checks.
- Create GitHub issue(s) to track further consolidation: Dashboard component merge, monitoring duplicate handler removal, stale docs replacement.
- Optionally open a PR (if using central workflow) or push changes directly to main (per direct-deploy policy).

Files changed:
- Added: `backend/lib/utils.js`
- Updated: `backend/server.js`, `backend/index.js`, `tools/terraform_pin_updater.py`, `scripts/utilities/terraform_pin_updater.py`

If you want, I can now:
- Run quick local smoke tests (start backend, curl /health).
- Create the GitHub issues automatically (provide repo owner/name and permission to create issues).
- Continue consolidating frontend `Dashboard_v2.tsx` and duplicate monitoring handler.
