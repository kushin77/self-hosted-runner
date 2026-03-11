# Governance: Auto-Removals (2026-03-11)

Automated governance polls removed several releases on 2026-03-11. This document records the audit trail, labels, and the policy that drove the removals.

Summary
- Date: 2026-03-11
- Removed releases: 24
- Audit issue: #2617

Labels used by automation
- `governance/auto-removed`
- `governance/audit`

Policy and operational guarantees
- Immutable: All removal actions are recorded in append-only audit logs and GitHub issues for traceability.
- Ephemeral: Removed releases are cleaned up; runtime artifacts are ephemeral and reproducible from source.
- Idempotent: Automation is safe to run repeatedly; repeated polls do not duplicate removals or corrupt state.
- No-Ops / Hands-off: The governance system operates autonomously; human intervention is not required for routine removals.
- Direct development & Direct deployment: Development commits are pushed directly to the main branch and deployment is performed by the deployment automation (not via GitHub Actions or PR-based release flows).
- No GitHub Actions: Organization policy forbids use of GitHub Actions for deployment or governance-critical workflows.
- No GitHub pull releases: Release automation does not rely on pull-request-based release creation.

Audit & Follow-up
- Canonical audit issue: #2617 aggregates per-release auto-removal issues and links to logs.
- To request reinstatement of a removed release, open an issue in the `governance/audit` category with the release name and reason; include any signed approvals.

Contact
- Ops/Governance team: @kushin77

---

This file was added automatically to document the 2026-03-11 automated governance activity and to provide a single reference for audits and follow-up actions.
