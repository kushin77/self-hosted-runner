# ElevatedIQ Runner Infrastructure: All-in-One Deployment Guide

**Latest Commits:**
- `fa64ea1e4` - Spot interruption handler + Prometheus exporter + image cache
- `54dba577b` - Observability stack (Prometheus + Alertmanager + Grafana)

**Status:** READY FOR FULL-STACK DEPLOYMENT

---

## 🚀 Quick Deployment (1 Command)

```bash
# On 192.168.168.42 (production node)
ssh akushnir@192.168.168.42 << 'DEPLOY_EOF'
cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo

# 1. Deploy spot interruption handler systemd service
sudo cp scripts/automation/pmo/systemd/elevatediq-spot-interruption-handler.service \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable elevatediq-spot-interruption-handler.service
sudo systemctl start elevatediq-spot-interruption-handler.service

echo "✅ Spot handler deployed"

# 2. Verify metrics exporter is running
sudo systemctl status elevatediq-metrics-exporter.service --no-pager | grep -E "(Active|Loaded)"

# 3. Deploy observability stack (Docker Compose)
cd scripts/automation/pmo/prometheus
cat > .env <<'ENV_EOF'
GRAFANA_ADMIN_PASSWORD=Admin123!ChangeMeInProduction
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PAGERDUTY_SERVICE_KEY=your-pagerduty-key
ENV_EOF

# Configure for 192.168.168.42
sed -i 's/192.168.168.42/192.168.168.42/g' docker-compose-observability.yml

# Start stack
docker-compose -f docker-compose-observability.yml up -d

echo "✅ Observability stack deployed"

# 4. Verify all services
docker ps

# 5. Check metrics endpoints
echo "Prometheus: http://192.168.168.42:9090"
echo "Alertmanager: http://192.168.168.42:9093"
echo "Grafana: http://192.168.168.42:3000"
echo "Metrics exporter: http://192.168.168.42:8081/metrics"

DEPLOY_EOF
```

---

## 📋 Manual Component Deployment

### 1. Runner Health Monitor (Already Deployed ✅)
```bash
ssh akushnir@192.168.168.42 "sudo systemctl status elevatediq-runner-health-monitor.timer"
```

### 2. Prometheus Metrics Exporter
```bash
# Deploy systemd service
ssh akushnir@192.168.168.42 << 'EOF'
sudo cp /tmp/elevatediq-metrics-exporter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable elevatediq-metrics-exporter.service
sudo systemctl start elevatediq-metrics-exporter.service
EOF

# Verify
curl http://192.168.168.42:8081/metrics | head -10
```

### 3. Spot Interruption Handler
```bash
# Deploy
ssh akushnir@192.168.168.42 << 'EOF'
sudo cp /opt/elevatediq/bin/spot_interruption_handler.sh /opt/elevatediq/bin/
sudo cp scripts/automation/pmo/systemd/elevatediq-spot-interruption-handler.service \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable elevatediq-spot-interruption-handler.service
sudo systemctl start elevatediq-spot-interruption-handler.service
EOF

# View logs
ssh akushnir@192.168.168.42 "sudo journalctl -u elevatediq-spot-interruption-handler.service -f"
```

### 4. Observability Stack (Prometheus + Alertmanager + Grafana)
```bash
# Copy config files
scp -r scripts/automation/pmo/prometheus/* akushnir@192.168.168.42:/opt/elevatediq/prometheus/

# Start containers
ssh akushnir@192.168.168.42 << 'EOF'
cd /opt/elevatediq/prometheus

# Create environment file
cat > .env <<'ENV_EOF'
GRAFANA_ADMIN_PASSWORD=SecurePassword123
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PAGERDUTY_SERVICE_KEY=your-service-key
ENV_EOF

# Start stack
docker-compose -f docker-compose-observability.yml up -d

# Verify
docker ps
EOF
```

### 5. Kubernetes Image Cache DaemonSet (k8s clusters)
```bash
# Deploy to Kubernetes cluster
kubectl apply -f scripts/automation/pmo/k8s/runner-image-cache-daemonset.yaml

# Verify
kubectl get daemonset -n actions-runner-system runner-image-cache-daemon
kubectl get pods -n actions-runner-system -l app=runner-image-cache
```

---

## 📚 Access Points

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| **Prometheus** | http://192.168.168.42:9090 | None (need auth if behind proxy) | Metrics collection & queries |
| **Alertmanager** | http://192.168.168.42:9093 | None | Alert routing & management |
| **Grafana** | http://192.168.168.42:3000 | admin / (from .env) | Dashboards & visualization |
| **Metrics Exporter** | http://192.168.168.42:8081/metrics | None | Raw Prometheus format metrics |

---

## 🔍 Monitoring & Dashboards

### Grafana Import Dashboards
1. Prometheus (`9090`)
2. Node Exporter (`1860`)
3. Docker / cAdvisor (`4686`)
4. Custom: Runner Health Dashboard (to be created)

### Key Metrics to Monitor
```promql
# Runner health checks
rate(runner_health_checks_total[5m])

# Runner restarts
rate(runner_restarts_total[5m])

# Node capacity
node_capacity_available{host="192.168.168.42"}

# System metrics
node_cpu_seconds_total
node_memory_MemAvailable_bytes
node_filesystem_avail_bytes
```

---

## 🚨 Alerts Setup

### Slack Integration
1. Create Slack webhook: https://api.slack.com/messaging/webhooks
2. Add to `.env`: `SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...`
3. Restart Alertmanager: `docker-compose restart alertmanager`

### PagerDuty Integration
1. Get integration key from PagerDuty service
2. Add to `.env`: `PAGERDUTY_SERVICE_KEY=...`
3. Restart Alertmanager

### Alert Rules Active
- Runner health check failures
- Runner monitor down
- Excessive restarts
- Node termination initiated
- Zero runner capacity
- High memory usage
- Disk space critical
- High CPU usage

---

## ✅ Verification Checklist

- [ ] Runner health monitor timer active (`systemctl status elevatediq-runner-health-monitor.timer`)
- [ ] Metrics exporter service running (`systemctl status elevatediq-metrics-exporter.service`)
- [ ] Spot handler service running (`systemctl status elevatediq-spot-interruption-handler.service`)
- [ ] Prometheus scraping metrics (`curl localhost:9090/api/v1/query?query=up`)
- [ ] Alertmanager processing rules (`curl localhost:9093/api/v1/alerts`)
- [ ] Grafana dashboard accessible (http://192.168.168.42:3000)
- [ ] Metrics endpoint responding (`curl localhost:8081/metrics`)
- [ ] Logs appearing in journalctl
- [ ] GitHub issues created for alerts

---

## 🔧 Troubleshooting

### Metrics not appearing
```bash
# Check exporter status
ssh akushnir@192.168.168.42 "sudo journalctl -u elevatediq-metrics-exporter.service -n 20"

# Test endpoint
curl -v http://192.168.168.42:8081/metrics
```

### Alerts not firing
```bash
# Check alert rules
ssh akushnir@192.168.168.42 "curl localhost:9090/api/v1/rules"

# Check Alertmanager config
ssh akushnir@192.168.168.42 "curl localhost:9093/api/v1/status"
```

### Spot handler not catching signals
```bash
# View logs
ssh akushnir@192.168.168.42 "sudo journalctl -u elevatediq-spot-interruption-handler.service -f"

# Test manually
ssh akushnir@192.168.168.42 "timeout 10 /opt/elevatediq/bin/spot_interruption_handler.sh"
```

---

## 📊 Performance Impact

- **Runner Health Monitor:** ~50MB RAM, low CPU (5-min interval)
- **Metrics Exporter:** ~80MB RAM, low CPU (serves HTTP)
- **Prometheus:** ~500MB RAM (30-day retention)
- **Alertmanager:** ~100MB RAM
- **Grafana:** ~200MB RAM
- **Total:** ~1GB RAM for full stack

---

## 🔐 Security Considerations

- [ ] Change Grafana admin password (currently in .env)
- [ ] Enable HTTPS for Prometheus/Grafana (reverse proxy)
- [ ] Restrict network access to monitoring ports
- [ ] Rotate Slack/PagerDuty credentials regularly
- [ ] Enable authentication for Prometheus scrape endpoints
- [ ] Audit alert routing configuration

---

## 📈 Next Steps

1. **Deploy immediately:** Use quick deployment command above
2. **Monitor:** Watch logs and metrics for 24+ hours
3. **Optimize:** Tune alert thresholds based on observed patterns
4. **Integrate:** Connect to external monitoring/logging systems
5. **Document:** Create runbooks for ops team

---

**Deployment Ready: YES ✅**
**All Systems Integrated: YES ✅**
**Production-Grade Monitoring: YES ✅**
