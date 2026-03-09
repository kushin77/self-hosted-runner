# Changelog

All notable changes to this repository will be documented in this file.

## [Unreleased]
- Minor follow-ups and backlog items

### 2026-03-07 — Resilience loader rollout
- Applied idempotent resilience loader to all GitHub Actions workflows (111/111). Loader: `source .github/scripts/resilience.sh || true`.
- Ensures retry/backoff, idempotence, and noop-safety across CI/CD workflows.
- Draft issues: #1246 and subsequent direct commits; final wrapper and wrapper fixes applied to `main`.
- Automation: background watcher and post-merge verification ran; rollout archived at `/tmp/rollout-archive.tgz`.


## [0.1.1-eiq-nexus] - 2026-03-05
### Added
- Postgres-backed persistence for the Pipeline Repair Engine with migrations
- NDJSON file-based telemetry fallback for air-gapped or ephemeral runs
- CI workflow to run Postgres migrations and integration tests (.github/workflows/pipeline-repair-postgres-ci.yml)
- API and service consolidation: merged repair persistence, migrations, and orchestrator scaffolds


## [0.1.0-eiq-nexus] - 2026-03-05
### Added
- Governance and branding docs for EIQ Nexus
- ADRs: Autonomous Repair, Multi-Cloud Runner, API-First, Sovereign Control Plane
- Nexus v1 API scaffolding: `src/api/nexus/v1`
- Autonomous repair engine scaffolding: `src/services/nexus/repair`
- Multi-cloud runner controller scaffolding: `src/services/nexus/runners`

