# Phase P3.4: Alerting Rules & Notification

This document describes alerting strategy for the self-hosted runner platform.

## Alert Rules

Rules are defined in `/alerts/provisioner-alerts.yml` and can be extended for
other services.

### Current Alerts
- **ProvisionerHighErrorRate** – >10% job failures over 2m
- **ProvisionerQueueBackup** – queue depth >20 for 1m
- **ProvisionerVaultDisconnected** – vault_connected==0 for 1m
- **ProvisionerJobStoreError** – jobstore_operational==0 for 1m
- **ProvisionerLatencySLO** – p95 latency >3s for 5m

Each rule includes `severity` label and annotations for `summary` and
`description` (used by Alertmanager integrations).

## Alertmanager Config Example

```yaml
route:
  receiver: 'slack-critical'
  routes:
    - match:
        severity: warning
      receiver: 'slack-warning'
receivers:
  - name: 'slack-critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/TOKEN'
        channel: '#alerts'
  - name: 'slack-warning'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/TOKEN'
        channel: '#warnings'
```

## Testing Alerts

The smoke and integration suites include helpers to simulate metrics.
Example (in `/tests/smoke/run-smoke-tests.sh`):

```bash
# fail rate >10%
echo "# HELP provisioner_jobs_failed_total" > /tmp/metrics

echo "provisioner_jobs_failed_total 5" >> /tmp/metrics

echo "provisioner_jobs_processed_total 10" >> /tmp/metrics
# run alert evaluation tool (not implemented)
```

Add similar scenarios to validate alert firing and notification delivery.

## Next Steps

1. Deploy alerts file to Prometheus configuration.  
2. Configure Alertmanager with desired receiver endpoints.  
3. Extend rules for managed-auth and vault-shim metrics.  
4. Add dashboard annotations to correlate alerts with visuals.

---

*Document Version: 2026-03-05*