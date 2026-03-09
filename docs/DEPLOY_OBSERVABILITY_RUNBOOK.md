# Observability Deployment Runbook

This runbook describes how to execute the automated observability deployment for Prometheus rules, Grafana dashboards, and log shipping.

Principles:
- Immutable: artifacts are committed to Git and applied, logs are append-only
- Ephemeral: credentials are fetched at runtime (GSM/Vault/KMS)
- Idempotent: scripts safe to re-run
- No-Ops / Hands-off: automation scripts perform remote operations when run on an operator host

Prerequisites:
- Operator host with network access to Prometheus and Grafana
- SSH access to Prometheus host (if applying rules via SSH)
- `gcloud` (for GSM), `vault` (for Vault) CLIs installed if using those backends

Quick run example (env-based token):
```bash
SECRETS_BACKEND=env GRAFANA_API_TOKEN="${GRAFANA_API_TOKEN}" \
  /home/akushnir/self-hosted-runner/scripts/deploy/auto-deploy-observability.sh \
  --prom-host prometheus.internal --prom-ssh-user promadmin \
  --grafana-host https://grafana.internal:3000 --grafana-token "env:GRAFANA_API_TOKEN"
```

GSM example:
```bash
SECRETS_BACKEND=gsm GSM_PROJECT=my-gcp-project \
  /home/akushnir/self-hosted-runner/scripts/deploy/auto-deploy-observability.sh \
  --prom-host prometheus.internal --prom-ssh-user promadmin \
  --grafana-host https://grafana.internal:3000 --grafana-token "secret:grafana/api-token"
```

Vault example:
```bash
SECRETS_BACKEND=vault VAULT_ADDR=https://vault.internal:8200 \
  /home/akushnir/self-hosted-runner/scripts/deploy/auto-deploy-observability.sh \
  --prom-host prometheus.internal --prom-ssh-user promadmin \
  --grafana-host https://grafana.internal:3000 --grafana-token "vault:secret/grafana#token"
```

Notes:
- The script is deliberately conservative: it requires SSH user for Prometheus host to install rules.
- Filebeat/ELK application is delegated to existing idempotent script `scripts/apply-elk-credentials-to-filebeat.sh`.
