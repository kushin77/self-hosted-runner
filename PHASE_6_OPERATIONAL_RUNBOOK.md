# Phase 6 Operational Runbook

**Status:** ✅ PRODUCTION LIVE (2026-03-10)  
**Deployment Host:** 192.168.168.42  
**Architecture:** Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off, Direct Deployment (Main Branch Only)

---

## 1. Quick Start (Hands-Off Deployment)

### One-Liner Deployment
```bash
cd /home/akushnir/self-hosted-runner && \
docker-compose -f docker-compose.phase6.yml down -v && \
docker-compose -f docker-compose.phase6.yml up -d --build && \
echo "✓ Phase 6 stack deployed" && \
docker-compose -f docker-compose.phase6.yml ps
```

### Service Status Check
```bash
ssh akushnir@192.168.168.42 "cd /home/akushnir/self-hosted-runner && docker-compose -f docker-compose.phase6.yml ps"
```

### Health Validation (All Services)
```bash
# Frontend (port 13000)
curl -f http://192.168.168.42:13000/ && echo "✓ Frontend OK"

# API (port 18080)
curl -f http://192.168.168.42:18080/health && echo "✓ API OK"

# Database (port 15432)
pg_isready -h 192.168.168.42 -p 15432 -U portal_user && echo "✓ Database OK"

# Redis (port 16379)
redis-cli -h 192.168.168.42 -p 16379 -a ${REDIS_PASSWORD} ping && echo "✓ Redis OK"

# Prometheus (port 19090)
curl -f http://192.168.168.42:19090/-/healthy && echo "✓ Prometheus OK"

# Grafana (port 13001)
curl -f http://192.168.168.42:13001/api/health && echo "✓ Grafana OK"

# Loki (port 3100, container internal)
curl -f http://192.168.168.42:3100/ready && echo "✓ Loki OK"

# Jaeger (port 26686 host, 16686 container)
curl -f http://192.168.168.42:26686/ && echo "✓ Jaeger OK"
```

---

## 2. Service Endpoints

| Service        | Host Port | Container Port | URL                          |
|----------------|-----------|----------------|------------------------------|
| Frontend       | 13000     | 80             | http://192.168.168.42:13000  |
| API            | 18080     | 3000           | http://192.168.168.42:18080  |
| Database       | 15432     | 5432           | postgresql://192.168.168.42:15432/portal_db |
| Redis          | 16379     | 6379           | redis://192.168.168.42:16379 |
| RabbitMQ AMQP  | 25672     | 5672           | amqp://192.168.168.42:25672  |
| RabbitMQ UI    | 15672     | 15672          | http://192.168.168.42:15672  |
| Prometheus     | 19090     | 9090           | http://192.168.168.42:19090  |
| Grafana        | 13001     | 3000           | http://192.168.168.42:13001  |
| Loki           | 3100      | 3100           | http://192.168.168.42:3100   |
| Jaeger UI      | 26686     | 16686          | http://192.168.168.42:26686  |
| Adminer (DB)   | 18081     | 8080           | http://192.168.168.42:18081  |

---

## 3. Credential Management (Immutable, No-Hardcoded Secrets)

All credentials use a 4-tier fallback (no hardcoded secrets in compose):

1. **Google Secret Manager (GSM)** - Live credentials, highest priority
2. **HashiCorp Vault** - Fallback if GSM unavailable
3. **AWS KMS/Secrets Manager** - DR fallback
4. **Environment Variables** - Local testing only

### Current `.env.phase6` Structure
```bash
# Database (credentials stored in GSM/Vault/KMS)
DATABASE_HOST_PORT=15432

# Redis (credentials stored in GSM/Vault/KMS)
CACHE_HOST_PORT=16379

# Frontend/API Ports
FRONTEND_HOST_PORT=13000
API_HOST_PORT=18080

# Monitoring
PROMETHEUS_HOST_PORT=19090
GRAFANA_HOST_PORT=13001
# Grafana admin password stored in GSM/Vault/KMS
```

### Retrieve Live Credentials (No Manual Steps)
```bash
gcloud secrets versions access latest --secret="nxs-portal-db-password" --project=nexusshield-prod
gcloud secrets versions access latest --secret="nxs-portal-redis-password" --project=nexusshield-prod
```

---

## 4. Common Issues & Resolutions

### Issue: Frontend Returns 503/Unhealthy

**Cause:** API service not responding.

**Fix:**
```bash
ssh akushnir@192.168.168.42 "cd /home/akushnir/self-hosted-runner && \
docker-compose -f docker-compose.phase6.yml logs api | tail -50"

# If API logs show errors, restart API
docker-compose -f docker-compose.phase6.yml restart api
```

**Idempotent redeploy:**
```bash
docker-compose -f docker-compose.phase6.yml up -d --force-recreate api && \
sleep 5 && \
curl -f http://192.168.168.42:18080/health
```

### Issue: Database Connection Refused

**Cause:** Postgres container not running or port not mapped.

**Fix:**
```bash
# Check container status
docker-compose -f docker-compose.phase6.yml ps | grep database

# Check port binding
ss -tlnp | grep 15432

# Redeploy database only
docker-compose -f docker-compose.phase6.yml up -d --force-recreate database
```

### Issue: Loki Failing to Start (Config Errors)

**Status:** Fixed in commit [COMMIT_SHA] - `monitoring/loki-config.yml` updated with compatible schema.

**If recurrence:**
```bash
docker logs nexusshield-loki | tail -100
# If config errors, pull latest `monitoring/loki-config.yml` from main branch
git checkout main -- monitoring/loki-config.yml
docker-compose -f docker-compose.phase6.yml up -d --force-recreate loki
```

### Issue: High Memory Usage (Container OOM Kill)

**Fix:**
1. Check memory allocation in `docker-compose.phase6.yml`
2. Scale down non-critical services (Jaeger, Loki)
3. Increase Docker VM memory (if applicable)

**Restart service:**
```bash
docker-compose -f docker-compose.phase6.yml restart <service>
```

### Issue: Prometheus Targets Down

**Check:**
```bash
curl -s http://192.168.168.42:19090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, state: .health}'
```

**Fix:** Verify services are running and health-check endpoints are correct.

---

## 5. Monitoring & Alerting

### Prometheus Scrape Configuration
- Default scrape interval: **30s**
- Alert evaluation: **30s**
- Retention: **30 days**

### Alert Rules
All alerts defined in `monitoring/prometheus-alerts.yml` and automatically loaded by Prometheus.

**Key Alerts:**
- `ServiceDown`: Service unavailable > 2 min → Critical
- `APIHighErrorRate`: 5xx rate > 10% → Critical
- `PostgresHighConnections`: Connections > 50 → Warning
- `RedisDiskSpaceLow`: Memory > 90% → Warning
- `RabbitMQQueueBackup`: Queue > 10k messages → Warning

### Grafana Dashboards
Pre-configured dashboards (auto-provisioned in `monitoring/grafana/provisioning/`):
- System Overview (CPU, memory, disk)
- API Performance (latency, errors, throughput)
- Database (connections, slow queries)
- Message Queue (RabbitMQ depth)
- Logs (Loki integration)

**Access:** http://192.168.168.42:13001 (admin / password from `.env.phase6`)

---

## 6. Logging & Tracing

### Loki Log Aggregation
- Logs collected from all containers
- Accessible in Grafana (Loki datasource pre-configured)
- Query prefix: `{job="<service>"}` e.g. `{job="api"}`

### Jaeger Distributed Tracing
- Jaeger all-in-one runs on port 16686 (container 16686, host 26686)
- Trace sampling: 100% for dev/Phase 6
- Access: http://192.168.168.42:26686

### Direct Container Logs
```bash
ssh akushnir@192.168.168.42 "docker logs -f nexusshield-api | head -100"
docker logs nexusshield-frontend | tail -50
```

---

## 7. Database Maintenance

### Backup (Manual for Now)
```bash
ssh akushnir@192.168.168.42 "docker exec nexusshield-database \
  pg_dump -U portal_user -d portal_db -Fc > /tmp/portal_db_$(date +%Y%m%d_%H%M%S).dump"
```

### Restore
```bash
docker exec -i nexusshield-database \
  pg_restore -U portal_user -d portal_db < /tmp/portal_db_<timestamp>.dump
```

### Connection Validation
```bash
docker exec nexusshield-database psql -U portal_user -d portal_db -c "SELECT version();"
```

---

## 8. Scaling & Resource Limits

No resource limits currently set. To add (if needed):
```yaml
services:
  api:
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 2G
        reservations:
          cpus: "0.5"
          memory: 1G
```

---

## 9. Immutability & Audit Trail

### Deployment History (Git)
All changes committed to `main` branch with immutable audit trail:
```bash
git log --oneline | head -20
```

### Execution Logs (JSONL)
Deployment executions logged to `logs/` with timestamps:
- `deployment-full-*.log`
- `complete-production-deployment-*.jsonl`

Example query:
```bash
grep -c '"status":"success"' logs/complete-production-deployment-*.jsonl
```

### Rollback to Last Known Good
```bash
git revert --no-edit <commit_sha>
docker-compose -f docker-compose.phase6.yml down -v
docker-compose -f docker-compose.phase6.yml up -d --build
```

---

## 10. Emergency Procedures

### Full Stack Reset (Destructive)
```bash
# ⚠️  WARNING: Deletes all volumes, caches, databases
ssh akushnir@192.168.168.42 "cd /home/akushnir/self-hosted-runner && \
docker-compose -f docker-compose.phase6.yml down -v && \
docker system prune -f && \
docker-compose -f docker-compose.phase6.yml up -d --build"

# Verify all services healthy
docker-compose -f docker-compose.phase6.yml ps
```

### Emergency Service Stop (Keep Data)
```bash
docker-compose -f docker-compose.phase6.yml stop
```

### Emergency Service Restart
```bash
docker-compose -f docker-compose.phase6.yml start
```

### Credential Rotation (No-Ops)
```bash
# Update credential in GSM, then re-run deployment
gcloud secrets versions add nxs-portal-db-password --data-file=- <<< "$NEW_PASSWORD"

# Trigger redeploy
cd /home/akushnir/self-hosted-runner && \
docker-compose -f docker-compose.phase6.yml up -d
```

---

## 11. Escalation Path

| Issue                       | Severity | Owner        | Escalation                                   |
|-----------------------------|----------|--------------|----------------------------------------------|
| Single service down         | High     | Ops          | DNS/network team, infrastructure team        |
| Multiple services down      | Critical | Ops          | Incident commander, security team           |
| Data loss/corruption        | Critical | DBA          | Infrastructure, backup/recovery team        |
| Credential breach           | Critical | Security     | CISO, incident response                      |
| Performance degradation     | Medium   | Eng/Ops      | Database team, cache team                    |
| Alerting system down        | High     | Monitoring   | On-call, notification channels               |

---

## 12. Configuration Files Reference

- **Compose:** `docker-compose.phase6.yml` (main service definitions)
- **Environment:** `.env.phase6` (ports, fallback credentials)
- **Prometh Rules:** `monitoring/prometheus-alerts.yml` (alerting rules)
- **Loki Config:** `monitoring/loki-config.yml` (log ingestion/storage)
- **Grafana Provisioning:** `monitoring/grafana/provisioning/` (dashboards & datasources)

---

## 13. Support & Troubleshooting Contact

- **On-Call Ops:** See PagerDuty escalation policy
- **Deployment Issues:** Check git history, JSONL audit logs, and `docker-compose logs`
- **Monitoring Issues:** Alert rules in `prometheus-alerts.yml`, Prometheus UI at port 19090
- **Database Issues:** Check Postgres logs, Adminer UI at port 18081

---

**Last Updated:** 2026-03-10  
**Architecture Review:** Immutable ✓ | Ephemeral ✓ | Idempotent ✓ | No-Ops ✓ | Hands-Off ✓ | GSM/Vault/KMS ✓
