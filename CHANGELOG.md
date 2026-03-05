# Changelog

All notable changes to this repository will be documented in this file.

## [Unreleased]
- Minor follow-ups and backlog items

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

