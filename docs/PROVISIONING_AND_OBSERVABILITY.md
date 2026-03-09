# Provisioning, Observability & Release Gates

This document describes recommended provisioning steps and observability setup for workers.

1) Vault Agent
- Purpose: provide runtime secret retrieval via AppRole or other auth methods.
- Install: use `scripts/provision/worker-provision-agents.sh` on the worker as root.
- Configure `/etc/vault/agent.d/agent.hcl` with real AppRole credentials and sinks.

2) Log Shipping
- Filebeat is installed by the provisioning script; configure outputs in `/etc/filebeat/filebeat.yml`.
- Optionally replace Filebeat with Datadog agent if `DATADOG_API_KEY` is available.

3) Metrics
- `node_exporter` is installed and runs on port 9100 by default.
- Configure Prometheus to scrape the node_exporter endpoint.

4) Release Gates
- Production deployments require a release approval file on the worker: `/opt/release-gates/production.approved`.
- To approve: `sudo mkdir -p /opt/release-gates && sudo touch /opt/release-gates/production.approved && sudo chmod 0644 /opt/release-gates/production.approved`.
- The deploy wrapper enforces that the file is present and younger than 7 days.

5) Audit Logs
- Deployment state is recorded under `/run/app-deployment-state/deployed.state` (JSONL). Ship these logs using Filebeat to your centralized logging cluster (ELK) or to Datadog.

6) Next Steps
- Configure AppRole in Vault and deploy secrets to the worker.
- Configure Filebeat output (ELK) or Datadog API key for remote shipping.
