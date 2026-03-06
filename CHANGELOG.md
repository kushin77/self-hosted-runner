# Changelog

All notable changes to this repository will be documented in this file.

## [Unreleased]
- No unreleased changes.

## [0.1.2] - 2026-03-06
### Added / Changed
- Hardened self-hosted runner installer and service flows:
  - Added Vault retrieval retries and robust parsing for registration tokens (`scripts/ci/setup-self-hosted-runner.sh`).
  - Optional `RUNNER_VERSION` pin and download retries for reproducible installs.
  - Ansible playbook updates to include `libssl3` fallback for newer distros.
  - Docker compose compatibility wrapper and updates to provisioner deploy script.
  - Systemd unit hardening for runner services and docker-compose units (timeouts, limits, env file support).
  - Quick shell-syntax PR checks added to CI (`.github/workflows/pr-checks.yml`).

- OIDC -> Vault authentication prototype and rotation tooling:
  - `scripts/ci/vault_oidc_auth.sh`, `scripts/ci/get-runner-token.sh`, and `scripts/ci/rotate-runner.sh` added to support OIDC-based Vault auth and runner token retrieval.
  - Vault policy example and Terraform user-data template to demonstrate bootstrap flow.
  - Integration tests using a Vault dev harness and a GitHub Actions workflow to validate token retrieval.

- Runner rotation automation and observability:
  - `scripts/ci/auto_rotate_runners.sh` to iterate and rotate runners from a config file.
  - Systemd service/timer templates and Terraform/example for deploying auto-rotation.
  - `docs/ROTATION_RUNBOOK.md` describing operational procedures.
  - Prometheus textfile metrics emitted by rotation script and a `PrometheusRule` alert for rotation failures.
  - Ansible playbook to deploy rotation automation to staging hosts.

### Security
- Avoid printing secrets in logs; scripts favor secure parsing and avoid exposing tokens in stdout.
- Added example Vault policy and guidance for OIDC role usage. Do not commit real policies or secrets.

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
