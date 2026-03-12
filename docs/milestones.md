# Milestone conventions and organizer usage

Purpose
- Centralize milestone names, descriptions, and how the `organize_milestones.sh` tool is used.

Milestone names (canonical)
- Observability & Provisioning — Provision agents, configure log/metric pipelines, validate observability.
- Secrets & Credential Management — GSM/Vault/AWS Secrets provisioning, rotation, and access.
- Deployment Automation & Migration — Canary runs, migration verification, and deployment safety checks.
- Governance & CI Enforcement — Branch protection, validation/enforcement workflows, governance gaps.
- Documentation & Runbooks — Consolidate operator guides, runbooks, and docs for operators.
- Monitoring, Alerts & Post-Deploy Validation — Validate metrics/log ingestion, alerts, and post-deploy checks.
- All Untriaged — Catch-all for ambiguous assignments.

Principles
- Immutable: All changes are logged; the organizer is preview-first and idempotent.
- Ephemeral: Tests and fixtures are local and disposable under `scripts/test/`.
- Idempotent: The organizer checks for milestone existence before creating.
- No-Ops / Hands-off: The organizer can be run non-interactively with `gh` auth.
- Credentials: Use GSM, Vault, or KMS for any secrets on CI or runners — do not embed tokens in scripts.
- No GitHub Actions: This repo policy forbids GitHub Actions; use local runners or external CI with OIDC/GSM integration.

Usage
- Preview:

  scripts/utilities/organize_milestones.sh

- Apply to open issues:

  scripts/utilities/organize_milestones.sh --apply

- Apply to closed issues:

  scripts/utilities/organize_milestones.sh --apply --closed

Requirements
- `gh` CLI authenticated with `repo` scope and appropriate permissions.
- `jq` and `python3` available on PATH.

Testing locally (no GH calls)
- See `scripts/test/` for an offline fixture and a local test that validates the heuristic mapping.

If you need me to deploy a runner or external CI that integrates GSM/Vault/KMS for secrets, tell me which provider to target and I will scaffold it.
