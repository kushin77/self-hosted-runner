# Provision and Observability Tasks (2026-03-09)

Status: OPEN

Tasks performed:
- Created `scripts/provision/worker-provision-agents.sh` to install Vault Agent, Filebeat, and node_exporter.
- Added `docs/PROVISIONING_AND_OBSERVABILITY.md` with configuration and operational guidance.
- Updated `scripts/deploy-idempotent-wrapper.sh` to enforce production release gate file.

Remaining actions for final closure:
1. Run `scripts/provision/worker-provision-agents.sh` on each worker (sudo).
2. Configure Vault AppRole and place credentials on the worker (or configure vault-agent auth backend).
3. Configure Filebeat output to ELK or provide `DATADOG_API_KEY` to install Datadog agent instead.
4. Configure Prometheus scrape targets for the node_exporter endpoints.
5. Validate log shipping and metric ingestion in observability platform.

Close this issue when all workers have been provisioned and observability validated.

Recorded-at: 2026-03-09T15:10:00Z
