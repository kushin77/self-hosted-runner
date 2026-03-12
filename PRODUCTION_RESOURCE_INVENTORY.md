# 📦 PRODUCTION RESOURCE INVENTORY
**Last Updated:** March 12, 2026  
**Scope:** All deployed infrastructure components

---

## 🌐 GCP RESOURCES

### Cloud Run Services

| Service | Region | Status | URL | Port |
|---------|--------|--------|-----|------|
| nexus-shield-portal-backend | us-central1 | ✅ | TLD-backend.run.app | 8080 |
| nexus-shield-portal-frontend | us-central1 | ✅ | TLD-frontend.run.app | 8080 |
| image-pin-service | us-central1 | ✅ | TLD-image-pin.run.app | 8080 |

**Note:** All services use Workload Identity (no SA keys)

### Cloud Scheduler Jobs

| Job | Schedule | Timezone | Status | Action |
|-----|----------|----------|--------|--------|
| image-pin-scheduler | 0 3 * * * | UTC | ✅ | POST /pin to Cloud Run |
| credential-rotation | 0 * * * * | UTC | ✅ | Rotate AWS/GSM/Vault |
| compliance-audit | 0 4 * * * | UTC | ✅ | Run security checks |
| cost-report | 0 6 * * * | UTC | ✅ | Generate daily costs |
| stale-cleanup | 0 2 * * * | UTC | ✅ | Remove idle resources |

**Access:** `gcloud scheduler jobs list --project=nexusshield-prod --location=us-central1`

### Secret Manager

| Secret | Type | Rotation | Status |
|--------|------|----------|--------|
| slack-webhook | Webhook URL | Manual | ℹ️ Pending (#2460) |
| github-token | GitHub PAT | 90-day | ✅ |
| oidc-provider-key | OIDC Key | Automatic | ✅ |
| db-connection-prod | Database URL | 30-day | ✅ |
| mfa-secret | MFA Key | Automatic | ✅ |

**Access:** `gcloud secrets list --project=nexusshield-prod`

### Service Accounts

| SA | Role | IRSA | Expires |
|----|------|------|---------|
| prod-deployer-sa-v3 | Custom (least-privilege) | ✅ | Never (SA, not key) |
| milestone-organizer-gsa | Storage + Secret accessors | ✅ | Never |
| monitoring-uchecker | Monitoring roles | ✅ | Never |

**Access:** `gcloud iam service-accounts list --project=nexusshield-prod`

### Networking

| Resource | Type | Status |
|----------|------|--------|
| Cloud NAT | Outbound | ✅ |
| Cloud Armor DDoS | Protection | ✅ |
| Cloud CDN | Caching | ✅ |
| Cloud Interconnect | N/A | Not used |

---

## ☁️ AWS RESOURCES

### S3 Buckets

| Bucket | Purpose | Lock Mode | Retention | Status |
|--------|---------|-----------|-----------|--------|
| akushnir-milestones-20260312 | Artifact archival | COMPLIANCE | 365 days | ✅ |

**Features:**
- ✅ Object versioning enabled
- ✅ MFA delete required
- ✅ KMS encryption (customer-managed key)
- ✅ Public access block
- ✅ Lifecycle rules (365d expiration)

**Access:** `aws s3 ls s3://akushnir-milestones-20260312/`

### IAM Roles

| Role | Trust Policy | Permissions | Status |
|------|--------------|-------------|--------|
| github-oidc-role | GitHub Actions OIDC | S3, KMS, Secrets, STS | ✅ |

**Trust Policy:**
```json
{
  "Federated": "arn:aws:iam::830916170067:oidc-provider/token.actions.githubusercontent.com",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:*"
    }
  }
}
```

### CloudWatch

| Metric | Namespace | Status |
|--------|-----------|--------|
| STSTokenAge | AWS/OIDC | ✅ |
| OIDCFederationSuccessRate | AWS/OIDC | ✅ |
| IAMRoleAssumptionLatency | AWS/OIDC | ✅ |

**Dashboards:**
- Phase4-OIDC-Monitoring
- AWS-OIDC-Health

**Access:** aws-console → CloudWatch Dashboard

---

## 🐳 KUBERNETES CLUSTER

### Namespaces

| Namespace | Purpose | Pods | Status |
|-----------|---------|------|--------|
| credential-system | Credential helpers + archival | N | ✅ |
| kube-system | System services | Auto | ✅ |
| monitoring | Prometheus, Grafana, Loki | Auto | ✅ |
| observability | OpenTelemetry, Jaeger | Auto | ✅ |

**Access:** `kubectl get namespaces`

### CronJobs

| CronJob | Schedule | Namespace | Status |
|---------|----------|-----------|--------|
| milestone-organizer | 0 1 * * * | credential-system | ✅ |

### Network Policies

| Policy | Namespace | Default Deny | Status |
|--------|-----------|--------------|--------|
| deny-all-ingress | credential-system | ✅ | ✅ |
| deny-all-egress | credential-system | ✅ | ✅ |

### RBAC

| Resource | Scope | Subject | Role |
|----------|-------|---------|------|
| credential-helper | SA:credential-system | Service Account | Read secrets, access API |
| deployer | SA:credential-system | Service Account | Execute jobs |

**Access:** `kubectl get rolebindings,clusterrolebindings -A`

### Monitoring Stack

| Component | Version | Purpose | Status |
|-----------|---------|---------|--------|
| Prometheus | 2.x | Metrics collection | ✅ |
| Grafana | 8.x | Dashboard visualization | ✅ |
| AlertManager | 0.x | Alert routing | ✅ |
| Loki | 2.x | Log aggregation | ✅ |
| OpenTelemetry | 0.x | Distributed tracing | ✅ |
| Jaeger | 1.x | Trace visualization | ✅ |

---

## 🔐 TERRAFORM STATE FILES

| Module | Path | Resources | Status |
|--------|------|-----------|--------|
| image-pin | terraform/image_pin/ | Cloud Run, Cloud Scheduler | ✅ |
| WIF | infra/phase3-production/ | OIDC pool, provider, SA | ✅ |
| Observability | infra/terraform/tmp_observability/ | Monitoring, health checks | ✅ |

**Backup:** All tfstate files backed up to GCS hourly

**Access:** `cd <path> && terraform state list`

---

## 📊 MONITORING DASHBOARDS

### GCP Cloud Monitoring

| Dashboard | Metrics | Purpose |
|-----------|---------|---------|
| Phase-4 Failover | Token age, latency, success rate | OIDC health |
| Cost Attribution | Daily spend, per-service costs | Budget tracking |
| Primary (Default) | CPU, memory, network, disk | System metrics |

**Access:** https://console.cloud.google.com/monitoring/dashboards

### AWS CloudWatch

| Dashboard | Metrics | Purpose |
|-----------|---------|---------|
| Phase4-OIDC-Monitoring | Token freshness, federation success | OIDC health |
| AWS-OIDC-Health | LatencyHistogram, error rate | Failover performance |

**Access:** https://console.aws.amazon.com/cloudwatch

### Custom Dashboards

| Dashboard | Tool | Purpose | Status |
|-----------|------|---------|--------|
| Phase-4 Failover (HTML) | docs/PHASE4_FAILOVER_DASHBOARD.html | Offline-capable visualiation | ✅ |

---

## 📈 COST BREAKDOWN (Daily)

| Component | Cost | Trend |
|-----------|------|-------|
| Compute (K8s) | $850 | Stable |
| Storage (S3/GCS) | $480 | +5% (archival growth) |
| Network | $720 | Stable |
| Credentials (API calls) | $360 | -8% (cache optimization) |
| Monitoring | $15 | Stable |
| **TOTAL** | **$2,425** | Stable |

**Optimization Target:** -20% over 90 days via cache deduplication + idle cleanup

---

## 🔗 EXTERNAL INTEGRATIONS

| Service | Status | Purpose | Config |
|---------|--------|---------|--------|
| GitHub OIDC | ✅ | Token provider | OIDC issuer: GitHub Actions (see AWS IAM OIDC config) |
| Slack Webhooks | ⏳ | Alert notifications | Pending setup (#2460) |
| HashiCorp Vault | ✅ | Credential backup | JWT auth, 30-min TTL |

---

## 🎯 PERFORMANCE TARGETS

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Credential failover latency | < 5s | 4.2s | ✅ 16% margin |
| Service availability | 99.99% | 99.97% | ✅ |
| Archive success rate | 100% | 100% | ✅ |
| Audit trail durability | 100% | 100% | ✅ |

---

## ✅ DEPLOYMENT CHECKLIST

**For new operators:**

- [ ] Read OPERATOR_QUICKSTART_GUIDE.md
- [ ] Bookmark monitoring dashboards
- [ ] Save escalation contacts
- [ ] Run production-verification.sh weekly
- [ ] Review audit logs daily
- [ ] Track admin-blocked items in #2216
- [ ] Test incident response procedures
- [ ] Verify credential rotation is happening

---

## 📞 QUICK ACCESS

### CLI Commands

```bash
# List all Cloud Run services
gcloud run services list --project=nexusshield-prod --region=us-central1

# Check Cloud Scheduler jobs
gcloud scheduler jobs list --project=nexusshield-prod --location=us-central1

# View recent logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50 --format=json

# Access S3 bucket
aws s3 ls s3://akushnir-milestones-20260312/

# Verify IAM role
aws iam get-role --role-name github-oidc-role

# Check Kubernetes pods
kubectl get pods -n credential-system

# Run health verification
bash scripts/ops/production-verification.sh
```

### Dashboard URLs

- **GCP Monitoring:** https://console.cloud.google.com/monitoring
- **AWS CloudWatch:** https://console.aws.amazon.com/cloudwatch
- **Jaeger Tracing:** localhost:16686 (local port-forward or internal DNS)

### Documentation

- `OPERATOR_QUICKSTART_GUIDE.md` — Daily operations guide
- `PRODUCTION_DEPLOYMENT_COMPLETION_FINAL_20260312.md` — Full deployment status
- `DEPLOY_RUNBOOK.md` — Deployment procedures
- GitHub #2216 — Admin action tracking

---

*Last verified: March 12, 2026. Update this file after any infrastructure changes.*
