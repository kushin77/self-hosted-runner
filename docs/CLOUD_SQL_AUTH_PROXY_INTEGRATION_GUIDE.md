# Cloud SQL Auth Proxy Integration Guide

**Status:** Ready for deployment (org policy exception pending)

## Overview

This guide walks through integrating Cloud SQL with the NexusShield backend using Cloud SQL Auth Proxy. The proxy runs as a sidecar container alongside the backend, eliminating the need for VPC peering and allowing keyless authentication via service account IAM.

## Prerequisites

- Backend Cloud Run service deployed (✅ Already deployed)
- Backend service account with appropriate IAM roles (✅ Set up)
- Cloud SQL instance provisioned in same project (⏳ Requires org policy exception #2345)
- Terraform module `cloud_sql_proxy.tf` initialized (✅ Ready)

## Architecture

```
GitHub Actions (OIDC token)
    ↓
Workload Identity Exchange (AWS STS / GCP)
    ↓
Backend Service Account (prod-deployer-sa-v3)
    ↓
Cloud Run Backend + Cloud SQL Proxy (sidecars)
    ├─ Node.js backend (port 8080, localhost)
    └─ cloud-sql-proxy (port 5432, localhost)
         ↓
    Cloud SQL Database (private, no VPC peering needed)
```

## 1. Enable Cloud SQL Proxy Module

### Step 1: Add to terraform.tfvars.production

```hcl
# Cloud SQL Auth Proxy configuration
enable_cloud_sql_proxy = true
cloud_sql_instance_connection_name = "nexusshield-prod:us-central1:migration-db"
cloud_sql_proxy_port = 5432
backend_sa_email = "prod-deployer-sa-v3@nexusshield-prod.iam.gserviceaccount.com"
```

### Step 2: Apply Terraform

```bash
cd terraform/
terraform plan -input=false -out=tfplan
terraform apply tfplan
```

**What this does:**
- ✅ Grants `roles/cloudsql.client` to backend service account
- ✅ Outputs Cloud SQL proxy configuration for Cloud Run deployment

## 2. Update Backend Cloud Run Service

### Option A: Using gcloud CLI (Quick)

```bash
gcloud run deploy backend \
  --region=us-central1 \
  --project=nexusshield-prod \
  --image=gcr.io/nexusshield-prod/backend:latest \
  --set-env-vars=DATABASE_URL="postgresql://user:password@localhost:5432/migration_db" \
  --add-cloudsql-instances=nexusshield-prod:us-central1:migration-db
```

### Option B: Update Terraform cloud_run.tf (Recommended)

In `terraform/cloud_run.tf`, update the backend service to include the proxy sidecar:

```hcl
resource "google_cloud_run_v2_service" "backend" {
  name            = "backend"
  location        = var.gcp_region
  project         = var.gcp_project
  launch_stage    = "GA"
  ingress         = "INGRESS_TRAFFIC_ALL"
  protocol        = "h2c"

  template {
    service_account = var.backend_sa_email
    timeout         = "3600s"

    # Main backend container
    containers {
      image = var.cloudrun_image
      ports {
        container_port = var.container_port
      }
      env {
        name  = "DATABASE_URL"
        value_from {
          secret_key_ref {
            secret = "postgres-connection-string"
            version = "latest"
          }
        }
      }
      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
      }
    }

    # Cloud SQL proxy sidecar (optional, enabled when configured)
    dynamic "containers" {
      for_each = local.cloud_sql_proxy_container
      content {
        image = containers.value.image
        args  = containers.value.args
        ports = containers.value.ports
        resources = containers.value.resources
        liveness_probe  = containers.value.liveness_probe
        readiness_probe = containers.value.readiness_probe
      }
    }
  }
}
```

After updating, apply Terraform:

```bash
terraform apply -var-file=terraform.tfvars.production
```

## 3. Update Backend Connection String

### In Secret Manager

```bash
gcloud secrets versions add postgres-connection-string \
  --project=nexusshield-prod \
  --data-file=<(cat <<EOF
postgresql://USERNAME:PASSWORD@localhost:5432/migration_db?sslmode=disable&connect_timeout=10&statement_timeout=30000
EOF
)
```

**Key points:**
- **Host:** `localhost` (not Cloud SQL instance hostname)
- **Port:** `5432` (matches proxy sidecar port)
- **Database:** Use your actual database name
- **SSL mode:** `disable` (proxy handles encryption)
- **Connection timeout:** `10s` (Cloud SQL proxy startup)
- **Statement timeout:** `30s` (reasonable default for migrations)

### In Prisma Schema (if using Prisma ORM)

```env
# .env.production
DATABASE_URL="postgresql://USERNAME:PASSWORD@localhost:5432/migration_db?sslmode=disable&connect_timeout=10&statement_timeout=30000"
```

## 4. Deploy Database + Schema

### Create Database

```bash
# Using Cloud SQL Admin API
gcloud sql databases create migration_db \
  --instance=migration-db \
  --project=nexusshield-prod \
  --charset=utf8mb4 \
  --collation=utf8mb4_unicode_ci
```

### Run Migrations

```bash
# Option 1: Via Prisma
npm run migrate:deploy

# Option 2: Via SQL script
gcloud sql connect migration-db \
  --user=migration_app \
  --project=nexusshield-prod \
  < schema.sql
```

## 5. Test Connectivity

### Health Check

```bash
# Backend /health endpoint should report database connection
curl https://backend.example.com/health -v

# Response should include:
# {
#   "status": "healthy",
#   "database": "connected",
#   "timestamp": "2026-03-12T12:00:00Z"
# }
```

### Direct Proxy Verification (from within Cloud Run)

```bash
gcloud run exec backend --region=us-central1 --project=nexusshield-prod -- \
  sh -c "nc -zv localhost 5432 && echo 'Cloud SQL proxy reachable'"
```

## 6. Monitoring & Observability

### Cloud SQL Audit Logs

```bash
gcloud logging read \
  "resource.type=\"cloudsql_database\" AND jsonPayload.user_account=\"migration_app\"" \
  --project=nexusshield-prod \
  --limit=50 \
  --format=json
```

### Cloud Run Logs

```bash
# Sidecar logs
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"backend\" AND jsonPayload.container=\"cloud-sql-proxy\"" \
  --project=nexusshield-prod \
  --limit=100

# Main container logs
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"backend\" AND severity=\"ERROR\"" \
  --project=nexusshield-prod \
  --limit=50
```

### Metrics (Prometheus / Cloud Monitoring)

**Cloud SQL Proxy metrics:**
- `cloudsql_proxy_open_connections` — Active connections
- `cloudsql_proxy_dial_failures_total` — Connection failures
- `cloudsql_proxy_dial_latency_seconds` — Connection time

**Enable in Prometheus scrape config:**

```yaml
- job_name: 'cloud-sql-proxy'
  static_configs:
    - targets: ['localhost:8090']  # Proxy health check port
```

## 7. Troubleshooting

### Issue: "Connection refused" on localhost:5432

**Diagnosis:**
```bash
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND textPayload=~\"dial.*connection refused\"" \
  --project=nexusshield-prod
```

**Solutions:**
1. Verify Cloud SQL instance is running: `gcloud sql instances describe migration-db --project=nexusshield-prod`
2. Check service account has `roles/cloudsql.client`: `gcloud projects get-iam-policy nexusshield-prod --flatten="bindings[].members" --filter="bindings.role:(roles/cloudsql.client)"`
3. Restart Cloud Run service: `gcloud run services update-traffic backend --to-revisions LATEST --region=us-central1 --project=nexusshield-prod`

### Issue: High latency on database connections

**Diagnosis:**
```bash
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND jsonPayload.duration_ms>1000" \
  --project=nexusshield-prod \
  --limit=20
```

**Solutions:**
1. Increase proxy connection timeout: Edit `cloud_sql_proxy.tf`, increase `max-connections`
2. Enable connection pooling in Prisma PrismaClient config:
   ```javascript
   new PrismaClient({
     datasources: {
       db: {
         url: process.env.DATABASE_URL,
       },
     },
   })
   ```
3. Scale Cloud Run for additional connection slots: `gcloud run services update backend --max-instances=10 --region=us-central1`

### Issue: Service account lacks cloudsql.client role

**Fix:**
```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:prod-deployer-sa-v3@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

## 8. Operational Checklist

- [ ] Terraform module initialized and validated
- [ ] Cloud SQL instance provisioned (admin action)
- [ ] Backend service account has `roles/cloudsql.client`
- [ ] Cloud Run service includes proxy sidecar
- [ ] DATABASE_URL secret in Secret Manager
- [ ] Database created and schema migrated
- [ ] / Health check endpoint verified
- [ ] Monitoring dashboards set up
- [ ] Backup strategy implemented (daily snapshots)
- [ ] Connection pooling tuned for workload

## 9. Rollback (if needed)

If issues arise after deployment:

```bash
# Disable proxy sidecar temporarily
terraform apply -var enable_cloud_sql_proxy=false

# Verify backend still runs without database
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"backend\"" \
  --project=nexusshield-prod

# Investigate logs
gcloud run services describe backend --region=us-central1 --project=nexusshield-prod
```

## References

- [Cloud SQL Proxy Documentation](https://cloud.google.com/sql/docs/mysql/sql-proxy)
- [Cloud Run with Cloud SQL](https://cloud.google.com/run/docs/tutorials/cloudsql)
- [Workload Identity for Cloud SQL](https://cloud.google.com/sql/docs/mysql/iam-overview)
- [Terraform Cloud SQL Resources](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database)

---

**Status:** ✅ Ready for deployment when Cloud SQL instance is available
**Last Updated:** March 12, 2026
**Maintainer:** NexusShield DevOps Team
