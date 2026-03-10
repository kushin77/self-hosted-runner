# Proposed Milestones (5-8) — Organize open issues for triage

This document proposes 6 focused milestones to group similar open issues for efficient triage and execution. Assignments reference local issue files present in the repository.

## Milestone 1: Observability & Provisioning
- Goal: Provision agents, configure log/metric pipelines, validate observability.
- Files / issues:
  - [issues/PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md](issues/PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md)

## Milestone 2: Secrets & Credential Management
- Goal: Ensure credential backends (GSM/Vault/AWS Secrets) are provisioned, rotated, and accessible.
- Files / issues:
  - [ISSUES/PROVISION-AWS-SECRETS.md](ISSUES/PROVISION-AWS-SECRETS.md)
  - [issues/MIGRATION_VERIFICATION_COMPLETE_2026_03_09.md](issues/MIGRATION_VERIFICATION_COMPLETE_2026_03_09.md) (post-validation steps)

## Milestone 3: Deployment Automation & Migration
- Goal: Final canary runs, migration verification, and safe rollback/runbook completion.
- Files / issues:
  - [issues/MIGRATION_VERIFICATION_COMPLETE_2026_03_09.md](issues/MIGRATION_VERIFICATION_COMPLETE_2026_03_09.md)
  - [ISSUE_264_OPERATIONAL_DEPLOYMENT.md](ISSUE_264_OPERATIONAL_DEPLOYMENT.md) (reference of completed automation; regression checks)

## Milestone 4: Governance, CI Enforcement & Branch Protection
- Goal: Harden branch protections, ensure validation/enforcement workflows, and close governance gaps.
- Files / issues:
  - [ISSUE_264_FINAL_READINESS_CHECKLIST.md](ISSUE_264_FINAL_READINESS_CHECKLIST.md)
  - [docs/ISSUE_264_RESOLUTION_SUMMARY.md](docs/ISSUE_264_RESOLUTION_SUMMARY.md)
  - [GITHUB_ISSUES_MANAGEMENT_SUMMARY.md](GITHUB_ISSUES_MANAGEMENT_SUMMARY.md)

## Milestone 5: Documentation & Runbooks
- Goal: Consolidate operational docs, create quick runbooks for provisioning and incident response.
- Files / issues:
  - [docs/AUTOMATION_OPERATIONS_DASHBOARD.md](docs/AUTOMATION_OPERATIONS_DASHBOARD.md)
  - [DEPLOYMENT_VAULT_AGENT_STATUS_FINAL.md](DEPLOYMENT_VAULT_AGENT_STATUS_FINAL.md)

## Milestone 6: Monitoring, Alerts & Post-Deployment Validation
- Goal: Validate metrics/log ingestion, alert rules, and on-call playbooks.
- Files / issues:
  - [monitoring](monitoring)
  - [docs/LOG_SHIPPING_GUIDE.md](docs/LOG_SHIPPING_GUIDE.md)

---
Next steps:
- Review and confirm these milestone names and included issues.
- If approved, I can:
  1) Create these milestones on GitHub and assign existing issues (requires a GitHub token with repo scope), or
  2) Open draft milestone tracking issues locally (one per milestone) and push a PR to apply them.

Recorded: 2026-03-09
