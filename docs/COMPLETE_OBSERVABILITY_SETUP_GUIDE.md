# Complete Observability Integration & Setup Guide

**Last Updated:** 2026-03-09  
**Status:** ✅ Complete Implementation Ready  

---

## 📊 Overview

This guide provides step-by-step instructions for configuring the complete observability stack:
- **Metrics:** Prometheus (scrape configuration)
- **Logs:** Elasticsearch/ELK OR Datadog (choose one)
- **Dashboards:** Grafana (with pre-built templates)
- **Alerts:** Prometheus alerting rules with notification channels

---

## Part 1: Prometheus Metrics Collection

### 1.1 Prerequisites

- Prometheus server running (with `--web.enable-lifecycle` flag for HTTP reload)
- Runner worker with `node_exporter` on port 9100
- Network connectivity between Prometheus and worker (port 9100)

### 1.2 Verify Node Exporter is Running

```bash
ssh runner-user@192.168.168.42 'curl -s http://localhost:9100/metrics | head -20'
```

Expected output: Prometheus format metrics (lines starting with `#` for comments, then `metric_name{...} value`)

### 1.3 Configure Prometheus Scrape Job

**Option A: Manual Configuration**

1. SSH into Prometheus host
2. Edit `/etc/prometheus/prometheus.yml`
3. Add the following to the `scrape_configs` section:

```yaml
  - job_name: 'runner-worker'
    static_configs:
      - targets: ['192.168.168.42:9100']
        labels:
          role: runner
          environment: production
          service: deployment-automation
```

4. Reload Prometheus:
   ```bash
   curl -X POST http://localhost:9090/-/reload
   # OR restart service:
   sudo systemctl restart prometheus
   ```

5. Verify in Prometheus UI:
   - Visit: http://prometheus-host:9090/targets
   - Look for job `runner-worker` with state `UP`

**Option B: Automated Configuration**

```bash
cd /home/akushnir/self-hosted-runner
./scripts/apply-prometheus-scrape-config.sh \
  --prometheus-host prometheus.internal \
  --worker-target 192.168.168.42:9100
```

### 1.4 Verify Metrics Collection

```bash
# Query Prometheus API (replace PROM_HOST with your Prometheus server)
curl 'http://PROM_HOST:9090/api/v1/query?query=up{job="runner-worker"}'

# Should return JSON with value 1 (up) or 0 (down)

# Query specific metrics
curl 'http://PROM_HOST:9090/api/v1/query?query=node_cpu_seconds_total{instance="192.168.168.42:9100"}' | jq .
```

---

## Part 2: Log Shipping (Choose One)

### 2.1 Option A: Elasticsearch / ELK Stack

#### Prerequisites
- Elasticsearch cluster running (typically on `elk.internal:9200`)
- Optional: Kibana for visualization (typically on `elk.internal:5601`)
- Authentication: API key or username/password

#### Steps

1. **Verify Elasticsearch connectivity from runner:**
   ```bash
   ssh runner-user@192.168.168.42 'curl -v http://elk.internal:9200/'
   ```
   If DNS doesn't resolve, add to `/etc/hosts` or configure DNS.

2. **Get Elasticsearch credentials** from your secrets manager:
   ```bash
   # From Google Secret Manager
   gcloud secrets versions access latest --secret=elk/credentials --project=p4-platform
   
   # OR from HashiCorp Vault
   vault kv get secret/elk/credentials
   ```

3. **Update Filebeat configuration** on the runner:
   ```bash
   # Download the template (if not already present)
   scp docs/filebeat-config-elk.yml runner-user@192.168.168.42:/tmp/filebeat.yml
   
   # SSH and update with correct Elasticsearch host/port/credentials
   ssh runner-user@192.168.168.42
   # Edit /tmp/filebeat.yml and set:
   #   - hosts: ["elk.internal:9200"]
   #   - username: "elastic"
   #   - password: "YOUR_PASSWORD_HERE"
   
   # Copy to system location
   sudo cp /tmp/filebeat.yml /etc/filebeat/filebeat.yml
   sudo chown root:root /etc/filebeat/filebeat.yml
   sudo chmod 0600 /etc/filebeat/filebeat.yml
   
   # Restart Filebeat
   sudo systemctl restart filebeat
   sudo systemctl status filebeat
   ```

4. **Verify log ingestion:**
   ```bash
   # Check Filebeat is running
   ssh runner-user@192.168.168.42 'sudo systemctl status filebeat'
   
   # Check Elasticsearch for new index
   curl http://elk.internal:9200/_cat/indices | grep -i runner
   
   # Expected output: deployment-audit-* or similar index
   
   # Query recent logs
   curl http://elk.internal:9200/deployment-audit-*/_search | jq '.hits.hits[0]'
   ```

#### Automated Setup (Idempotent)

```bash
cd /home/akushnir/self-hosted-runner

# This script handles credentials from GSM/Vault and applies to Filebeat
./scripts/apply-elk-credentials-to-filebeat.sh \
  --elk-host elk.internal \
  --elk-port 9200 \
  --require-auth
```

### 2.2 Option B: Datadog Agent

#### Prerequisites
- Datadog account with API key
- Datadog region set (e.g., `datadoghq.com` or `datadoghq.eu`)

#### Steps

1. **Get Datadog API key:**
   ```bash
   # From secrets manager
   DATADOG_API_KEY=$(gcloud secrets versions access latest --secret=datadog/api-key --project=p4-platform)
   # OR from Vault
   DATADOG_API_KEY=$(vault kv get -field=api_key secret/datadog)
   ```

2. **Run installation script on runner:**
   ```bash
   ssh runner-user@192.168.168.42
   
   # With environment variable
   sudo DATADOG_API_KEY="$DATADOG_API_KEY" \
        bash /home/akushnir/self-hosted-runner/scripts/provision/install-datadog-agent.sh \
        datadoghq.com
   
   # Verify
   sudo systemctl status datadog-agent
   ```

3. **Configure log collection:**
   ```bash
   # Edit Datadog agent config
   sudo cat > /etc/datadog-agent/conf.d/deployment-audit.d/conf.yaml <<'EOF'
logs:
  - type: file
    path: /run/app-deployment-state/deployed.state
    service: deployment-automation
    source: custom
    tags:
      - env:production
EOF
   
   # Restart agent
   sudo systemctl restart datadog-agent
   ```

4. **Verify in Datadog UI:**
   - Navigate to Logs → Live Tail
   - Filter: `source:custom service:deployment-automation`
   - Should see deployment audit logs within 2 minutes

---

## Part 3: Grafana Dashboards

### 3.1 Add Prometheus Data Source

1. Open Grafana (typically on `grafana.internal:3000`)
2. Navigate to **Configuration → Data Sources**
3. Click **Add data source**
4. Select **Prometheus**
5. Set URL: `http://prometheus.internal:9090`
6. Click **Save & Test**

### 3.2 Import Pre-built Dashboards

#### Dashboard 1: Deployment Metrics
```bash
# Copy dashboard to Grafana
curl -X POST http://grafana.internal:3000/api/dashboards/db \
  -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana-dashboard-deployment-metrics.json
```

Expected panels:
- Total Deployments (24h)
- Deployment Success Rate
- Failed Deployments
- Deployment Duration (avg)
- Worker Node Status  
- Deployments per Worker
- Timeline of deployments
- Audit log ingestion rate
- Most common errors

#### Dashboard 2: Infrastructure Health
```bash
curl -X POST http://grafana.internal:3000/api/dashboards/db \
  -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana-dashboard-infrastructure.json
```

Expected panels:
- Node status
- CPU usage
- Memory usage
- Disk usage
- Network I/O
- Load average
- System services status
- Process count
- Filesystem I/O

### 3.3 Create Custom Dashboards

Follow Grafana documentation: https://grafana.com/docs/grafana/latest/dashboards/

Key metrics to visualize:
- `deployment_total` — Total deployments by status
- `deployment_duration_seconds` — Deployment timing
- `audit_events_total` — Audit log volume
- `node_cpu_seconds_total` — CPU utilization
- `node_memory_MemAvailable_bytes` — Memory available
- `node_filesystem_avail_bytes` — Disk space

---

## Part 4: Prometheus Alerting Rules

### 4.1 Load Alerting Rules

1. **Copy alert rules to Prometheus:**
   ```bash
   sudo cp monitoring/prometheus-alerting-rules.yml /etc/prometheus/rules/
   sudo chown prometheus:prometheus /etc/prometheus/rules/prometheus-alerting-rules.yml
   ```

2. **Update Prometheus config** (`/etc/prometheus/prometheus.yml`):
   ```yaml
   rule_files:
     - "/etc/prometheus/rules/*.yml"
   
   alerting:
     alertmanagers:
       - static_configs:
           - targets: ['alertmanager.internal:9093']
   ```

3. **Reload Prometheus:**
   ```bash
   sudo systemctl reload prometheus
   # OR via HTTP
   curl -X POST http://localhost:9090/-/reload
   ```

### 4.2 Verify Alerts Are Loaded

```bash
curl http://prometheus:9090/api/v1/rules | jq '.data.groups[] | select(.file | contains("alerting")) | .rules[] | {alert: .alert, expr: .expr}'
```

Expected output: List of alerts (deployment failures, high CPU, disk space, etc.)

### 4.3 Configure Alert Notifications

Configure AlertManager to send alerts to:
- **Slack:** Add webhook URL
- **Email:** Configure SMTP
- **PagerDuty:** Add integration key
- **Opsgenie:** Add API key

Example AlertManager config (`/etc/alertmanager/config.yml`):
```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'instance']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

receivers:
  - name: 'default'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#platform-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ .GroupLabels.instance }} — {{ .CommonAnnotations.summary }}'
```

---

## Part 5: Complete Verification Checklist

After setup, verify all components:

### Metrics Collection ✅
```bash
#  Should show UP
curl 'http://PROM_HOST:9090/api/v1/query?query=up{job="runner-worker"}' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'

# Should return 2700+ metrics
curl 'http://PROM_HOST:9090/api/v1/label/__name__/values?match={job="runner-worker"}' | jq '.data | length'
```

### Log Ingestion ✅
**ELK:**
```bash
curl 'http://elk.internal:9200/deployment-audit-*/_search?size=1' | jq '.hits.total'
# Should show count > 0
```

**Datadog:**
```bash
# Navigate to Logs → Live Tail
# Filter: source:custom service:deployment-automation
# Should see recent entries
```

### Dashboards ✅
- Grafana dashboards accessible
- Metrics displaying in real-time
- No errors in datasource connection

### Alerts ✅
- Alert rules loaded in Prometheus
- AlertManager configured
- Test alert fires correctly:
  ```bash
  # Trigger a test alert
  curl -X POST http://alertmanager:9093/api/v1/alerts \
    -H "Content-Type: application/json" \
    -d '[{"labels": {"alertname": "test"}}]'
  ```

---

## Part 6: Success Metrics

All items below should show ✅:

- [ ] Prometheus scrape job `runner-worker` shows `UP`
- [ ] 2700+ node_exporter metrics available in Prometheus
- [ ] Elasticsearch index `deployment-audit-*` contains recent logs (ELK only)
- [ ] Datadog Logs UI shows deployment-automation entries (Datadog only)
- [ ] Grafana dashboards display real-time data from Prometheus
- [ ] Prometheus alerting rules loaded (verify via `/api/v1/rules`)
- [ ] AlertManager receives alerts and forwards to notification channel
- [ ] Manual test alert successfully triggers notification

---

## Part 7: Operational Runbooks

### Troubleshooting Node Exporter Down
```bash
ssh runner-user@192.168.168.42
sudo systemctl status node_exporter
sudo systemctl restart node_exporter
# Check metrics: curl http://localhost:9100/metrics
```

### Troubleshooting Filebeat Not Shipping Logs
```bash
# Check service
sudo systemctl status filebeat

# Check logs
sudo tail -f /var/log/filebeat/filebeat

# Test Elasticsearch connectivity
curl -v http://elk.internal:9200/

# Verify config
sudo cat /etc/filebeat/filebeat.yml | grep -A 5 "elasticsearch:"
```

### Troubleshooting Prometheus Not Scraping
```bash
# Check Prometheus logs
sudo tail -f /var/log/prometheus/prometheus.log

# Test connectivity to worker
curl -v http://192.168.168.42:9100/metrics

# Reload and verify
curl -X POST http://localhost:9090/-/reload
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[]'
```

---

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Elasticsearch Filebeat Guide](https://www.elastic.BASE64_BLOB_REDACTED-overview.html)
- [Datadog Agent Documentation](https://docs.datadoghq.com/agent/)
- [AlertManager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

---

## Support & Escalation

- **Prometheus Setup:** Platform/SRE team
- **Filebeat/ELK:** Storage/Logging team
- **Datadog:** Observability team
- **Grafana Dashboards:** Monitoring/Observability team

Questions? See the individual documentation files:
- `docs/LOG_SHIPPING_GUIDE.md`
- `docs/PROMETHEUS_SCRAPE_CONFIG.yml`
- `docs/filebeat-config-elk.yml`
