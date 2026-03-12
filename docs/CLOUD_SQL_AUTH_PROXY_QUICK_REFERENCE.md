# Cloud SQL Auth Proxy - Quick Reference

## One-Liner Commands

### Enable Proxy in Terraform
```bash
cd terraform && terraform apply -var enable_cloud_sql_proxy=true
```

### Deploy Updated Backend with Proxy Sidecar
```bash
gcloud run deploy backend \
  --region=us-central1 \
  --project=nexusshield-prod \
  --image=gcr.io/nexusshield-prod/backend:latest \
  --add-cloudsql-instances=nexusshield-prod:us-central1:migration-db
```

### Verify Proxy Health
```bash
gcloud logging read "container_name=\"cloud-sql-proxy\" AND severity=\"ERROR\"" \
  --project=nexusshield-prod --limit=5
```

### Grant IAM Role
```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:prod-deployer-sa-v3@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

### Update Connection String
```bash
gcloud secrets versions add postgres-connection-string \
  --project=nexusshield-prod \
  --data-file=/path/to/connection.string
```

### Test Database Connectivity (from Cloud Run)
```bash
gcloud run exec backend --region=us-central1 --project=nexusshield-prod -- \
  psql -h localhost -U migration_app -d migration_db -c "SELECT NOW();"
```

## Environment Variables

| Variable | Value |
|----------|-------|
| `DATABASE_URL` | `postgresql://user:pass@localhost:5432/migration_db?sslmode=disable` |
| `CLOUD_SQL_INSTANCE` | `nexusshield-prod:us-central1:migration-db` |
| `DB_POOL_SIZE` | `20` |
| `DB_STATEMENT_TIMEOUT_MS` | `30000` |

## Terraform Configuration

### Enable in terraform.tfvars.production
```hcl
enable_cloud_sql_proxy              = true
cloud_sql_instance_connection_name  = "nexusshield-prod:us-central1:migration-db"
cloud_sql_proxy_port                = 5432
backend_sa_email                    = "prod-deployer-sa-v3@nexusshield-prod.iam.gserviceaccount.com"
```

## Monitoring Query (CloudWatch)

```json
{
  "metrics": [
    {
      "name": "cloudsql_proxy_open_connections",
      "namespace": "custom/sql",
      "stat": "Average"
    }
  ],
  "period": 300,
  "stat": "Average"
}
```

## Health Check Endpoint

**Test:** `curl https://backend.example.com/health`

**Expected Response (200 OK):**
```json
{
  "status": "healthy",
  "database": "connected",
  "poolSize": 20,
  "openConnections": 3,
  "uptime": 3600
}
```

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| "Connection refused" | Proxy not running | Check `gcloud logging read` for errors |
| "Permission denied" | Missing `roles/cloudsql.client` | Run `gcloud projects add-iam-policy-binding` |
| "Connection timeout" | Cloud SQL instance down | Restart instance: `gcloud sql instances restart` |
| High latency (>1s per query) | Connection pool exhausted | Increase `max-connections` or scale Cloud Run |

## Deployment Checklist

- [ ] Terraform module initialized: `terraform init`
- [ ] IAM role granted: `gcloud projects get-iam-policy` (verify role present)
- [ ] Cloud SQL instance exists: `gcloud sql instances list --project=nexusshield-prod`
- [ ] Database created: `gcloud sql databases list --instance=migration-db --project=nexusshield-prod`
- [ ] Connection string in Secret Manager: `gcloud secrets describe postgres-connection-string --project=nexusshield-prod`
- [ ] Cloud Run service deployed: `gcloud run services describe backend --region=us-central1`
- [ ] Health endpoint returns 200: `curl https://backend.example.com/health`
- [ ] Logs show no proxy errors: `gcloud logging read "severity=ERROR" --limit=5`

## Logs to Monitor

### Proxy Startup (first deploy)
```bash
gcloud logging read "container_name=\"cloud-sql-proxy\" AND textPayload=~\"listening.*5432\"" \
  --project=nexusshield-prod --limit=1
```

### Connection Errors
```bash
gcloud logging read "container_name=\"cloud-sql-proxy\" AND severity=\"ERROR\"" \
  --project=nexusshield-prod --limit=10 --format=json | jq '.[]"Message"
```

### Database Query Logs
```bash
gcloud logging read "resource.type=\"cloudsql_database\"" \
  --project=nexusshield-prod --limit=50
```

## Performance Tuning

### Connection Pool Size (Prisma)
```javascript
const prisma = new PrismaClient({
  log: ['error', 'warn'],
  // Max 100 connections per Cloud Run instance
  // Adjust pool size based on concurrency needs
})
```

### Proxy Max Connections
```hcl
# In cloud_sql_proxy.tf
args = [
  var.cloud_sql_instance_connection_name,
  "--port=${var.cloud_sql_proxy_port}",
  "--max-connections=100",  # ← Adjust based on workload
  "--use-http-health-check",
]
```

### Cloud Run Instance Scaling
```bash
# Allow more parallel connections
gcloud run services update backend \
  --max-instances=50 \
  --region=us-central1 \
  --project=nexusshield-prod
```

---

**Last Updated:** March 12, 2026  
**Status:** Ready for deployment ✅
