# Log Shipping Configuration Guide

This document describes how to ship deployment audit logs to centralized logging platforms (ELK Stack or Datadog).

## Option 1: Elasticsearch (ELK Stack)

### Prerequisites
- Elasticsearch cluster running and accessible
- Filebeat binary installed on worker (or install via provisioning script)

### Setup

1. **Update Filebeat configuration on worker:**

```bash
scp docs/filebeat-config-elk.yml akushnir@192.168.168.42:/tmp/
ssh akushnir@192.168.168.42 << 'EOF'
sudo cp /tmp/filebeat-config-elk.yml /etc/filebeat/filebeat.yml
# Edit with your Elasticsearch hosts:
sudo sed -i "s/elasticsearch.example.com:9200/YOUR_ES_HOST:9200/g" /etc/filebeat/filebeat.yml
sudo systemctl restart filebeat
EOF
```

2. **Verify logs are flowing:**

```bash
# Check Filebeat status
ssh akushnir@192.168.168.42 'sudo journalctl -u filebeat -n 20 --no-pager'

# Query Elasticsearch for logs
curl -u elastic:password http://ES_HOST:9200/deployment-audit-*/_search?size=10
```

3. **Create Kibana dashboard** (optional):
   - Index pattern: `deployment-audit-*`
   - Visualizations:
     - Deployment count by environment
     - Deployments by deployer
     - Deployment timeline

### Filebeat Configuration Details

- **Index:** `deployment-audit-YYYY.MM.DD` (daily indices)
- **Log source:** `/run/app-deployment-state/deployed.state`
- **Fields parsed:**
  - `timestamp` — RFC3339 UTC
  - `env` — Environment (staging/production)
  - `deployer` — Unix username of deployer
  - `log_type` — deployment_audit
  - `host` — Worker hostname

---

## Option 2: Datadog

### Prerequisites
- Datadog account with API key
- Worker has internet access (or proxy configured)

### Setup

1. **Run installation script on worker:**

```bash
DATADOG_API_KEY="your-api-key-here"
DATADOG_SITE="datadoghq.com"  # or "datadoghq.eu"

scp scripts/provision/install-datadog-agent.sh akushnir@192.168.168.42:/tmp/
ssh akushnir@192.168.168.42 \
  "sudo bash /tmp/install-datadog-agent.sh $DATADOG_API_KEY $DATADOG_SITE"
```

2. **Verify logs in Datadog:**
   - Navigate to: Logs → All Logs
   - Filter: `source:custom service:deployment-audit`
   - Should see deployment records appearing in real-time

3. **Create Datadog dashboard** (optional):
   - Metric queries:
     - `avg:deployment.count` by `env`
     - `count_unique:deployer` by `env`
   - Log patterns:
     - `source:custom service:deployment-audit`

### Datadog Configuration Details

- **Service:** `deployment-audit`
- **Source:** `custom`
- **Tags:** `env:production`, `service:deployment`, `log_type:deployment_audit`
- **Log path:** `/run/app-deployment-state/deployed.state`

---

## Log Query Examples

### Elasticsearch / Kibana

```bash
# Get all production deployments in the last 24 hours
GET deployment-audit-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "env": "production" } },
        { "range": { "timestamp": { "gte": "now-24h" } } }
      ]
    }
  }
}

# Deployments by deployer (aggregation)
GET deployment-audit-*/_search
{
  "size": 0,
  "aggs": {
    "by_deployer": {
      "terms": { "field": "deployer.keyword" }
    }
  }
}
```

### Datadog

```
# Query deployment audit logs
source:custom service:deployment-audit env:production

# Count deployments by environment
stats count by env
```

---

## Monitoring & Alerting

### Elasticsearch Alerting (Watcher)

```json
PUT _watcher/watch/deployment_failure_alert
{
  "trigger": {
    "schedule": { "interval": "5m" }
  },
  "input": {
    "search": {
      "request": {
        "indices": ["deployment-audit-*"],
        "body": {
          "query": {
            "bool": {
              "must": [
                { "range": { "timestamp": { "gte": "now-5m" } } }
              ]
            }
          }
        }
      }
    }
  },
  "condition": {
    "compare": {
      "ctx.payload.hits.total.value": { "gte": 0 }
    }
  },
  "actions": {
    "email": {
      "email": {
        "to": "ops@example.com",
        "subject": "Deployment detected",
        "body": "{{ctx.payload.hits.hits}}"
      }
    }
  }
}
```

### Datadog Monitors

```python
# Create alert: No deployments in 24 hours
{
  "name": "No deployments in 24 hours",
  "type": "log alert",
  "query": "source:custom service:deployment-audit",
  "alert_condition": "absence",
  "threshold": 3600,  # seconds
  "notify_list": ["@ops-team"]
}

# Create alert: Production deployment spike
{
  "name": "High deployment rate",
  "type": "event alert",
  "query": "source:custom service:deployment-audit env:production",
  "alert_condition": "more than 5 times in 5m",
  "notify_list": ["@ops-team", "@slack-channel"]
}
```

---

## Maintenance & Troubleshooting

### Check Filebeat Status

```bash
# SSH to worker
ssh akushnir@192.168.168.42 << 'EOF'

# Service status
sudo systemctl status filebeat

# Logs
sudo journalctl -u filebeat -f

# Config validation
sudo filebeat test config

# Dry-run: show what would be sent
sudo filebeat test output

EOF
```

### Check Datadog Agent Status

```bash
# SSH to worker
ssh akushnir@192.168.168.42 << 'EOF'

# Service status
sudo systemctl status datadog-agent

# Check connectivity to Datadog
sudo systemctl status datadog-trace-agent

# Logs
sudo journalctl -u datadog-agent -f

EOF
```

### Debugging Log Shipping

```bash
# Tail deployment audit logs locally
ssh akushnir@192.168.168.42 'tail -f /run/app-deployment-state/deployed.state'

# Manually test Elasticsearch connectivity
ssh akushnir@192.168.168.42 << 'EOF'
curl -X GET "http://elasticsearch.example.com:9200/_cat/indices?v" \
  -H "Content-Type: application/json"
EOF

# Manually test Datadog connectivity
ssh akushnir@192.168.168.42 << 'EOF'
curl -X POST "https://api.datadoghq.com/api/v2/logs" \
  -H "DD-API-KEY: YOUR_API_KEY" \
  -d '{"message":"test"}'
EOF
```

---

## Next: Integration Instructions

Once logs are flowing:

1. **Set up dashboards** (Kibana or Datadog)
2. **Configure alerts** for deployment failures or anomalies
3. **Create runbooks** referencing log queries
4. **Share dashboards** with ops/devops team
5. **Monitor for 24–48 hours** to verify reliability

---

**Last Updated:** 2026-03-09  
**Templates Available:**
- `docs/filebeat-config-elk.yml` — Elasticsearch configuration
- `scripts/provision/install-datadog-agent.sh` — Datadog installation script
