# NEXUS Engine Architecture Diagram
**Date:** March 12, 2026  
**Status:** Production Ready  
**Governance:** Immutable, Ephemeral, Idempotent, No-Ops, Hands-Off, Direct-Deploy

---

## System Architecture (draw.io compatible)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GIT COMMIT → DIRECT DEPLOY                         │
│                      (No GitHub Actions, No PR-based releases)               │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   OPERATOR: ./scripts/deploy_direct.sh                       │
│                  (Local: build binary, push image, deploy)                   │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
    ┌──────────────────┐  ┌────────────┐  ┌─────────────────┐
    │  Docker Image    │  │ Container  │  │  Registry Push  │
    │  (nexus-ingestion)  │  Registry  │  │  (GCR / ECR)    │
    └────────┬──────────┘  └────────────┘  └────────┬────────┘
             │                                        │
             └────────────────┬──────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────────────────┐
        │      DEPLOYED SERVICE (Cloud Run / GKE)       │
        │           nexus-ingestion:2026-03-12          │
        └────────────────────┬──────────────────────────┘
                             │
        ┌────────────────────┼────────────────────────┐
        ▼                    ▼                        ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│    HTTP Ingest   │ │    Receive Raw   │ │  Webhook Parser  │
│   POST /ingest   │ │   GitHubWebhook  │ │  (json payload)  │
└────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────────────────┐
        │    KAFKA BROKER (docker-compose / Confluent)   │
        │         nexus.discovery.raw (RawEvent)         │
        └────────────────────┬──────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
    ┌─────────────────────┐     ┌──────────────────────┐
    │  Normalizer Pod 1   │     │  Normalizer Pod N    │
    │ (kubernetes CronJob)│     │ (kubernetes CronJob) │
    │  - GitHubNormalizer │     │ (parallel workers)   │
    │  - AWS/GCP parser   │     │                      │
    │  - normalize()      │     │                      │
    └─────────┬───────────┘     └──────────┬───────────┘
              │                            │
              └────────────────┬───────────┘
                               │
                               ▼
        ┌────────────────────────────────────────────────┐
        │    KAFKA BROKER (Normalized Topic)             │
        │    nexus.discovery.normalized (Event)          │
        └────────────────────┬──────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
    ┌─────────────────────┐     ┌──────────────────────┐
    │  PostgreSQL 15      │     │  ClickHouse (Future) │
    │  (RLS-enabled)      │     │  (Analytics DB)      │
    │  - discovery_events │     │  - event sink        │
    │  - audit_log        │     │  - analytics queries │
    └─────────────────────┘     └──────────────────────┘
              │                            │
              └────────────────┬───────────┘
                               │
                               ▼
        ┌────────────────────────────────────────────────┐
        │    NEXUS OPS PORTAL (React/TypeScript)         │
        │    - Real-time Kafka metrics                   │
        │    - Pipeline status & throughput              │
        │    - Error tracking & alerting (GSM/Vault)     │
        │    - Audit log viewer (PostgreSQL)             │
        │    - Normalizer job status                     │
        │    - draw.io diagrams (inline)                 │
        └────────────────────┬──────────────────────────┘
                             │
        ┌────────────────────┼────────────────────────┐
        ▼                    ▼                        ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  Metrics Export  │ │ Alert Webhook    │ │  Audit Logger    │
│ (Prometheus)     │ │ (Slack/PagerDuty)│ │ (JSONL immutable)│
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

---

## Credential & Security Flow (GSM/VAULT/KMS)

```
┌──────────────────────────────────────────────────────────────┐
│              CREDENTIAL PROVISIONING                         │
│        (Ephemeral, TTL-based, No Hardcoding)                 │
└───────────────────────────┬──────────────────────────────────┘
                            │
         ┌──────────────────┴──────────────────┐
         ▼                                     ▼
    ┌──────────────┐                  ┌──────────────┐
    │   GCP GSM    │                  │  Vault KMS   │
    │ secret-name: │                  │ /secret/db   │
    │  pg-password │                  │ /secret/mq   │
    └──────┬───────┘                  └──────┬───────┘
           │                                 │
           └─────────────────┬───────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
    ┌─────────────────────┐     ┌──────────────────────┐
    │  Ephemeral Secret   │     │  AWS KMS Envelope    │
    │  Env Var Injection  │     │  Encryption          │
    │  (15 min TTL)       │     │                      │
    └────────┬────────────┘     └──────────┬───────────┘
             │                            │
             └────────────────┬───────────┘
                              │
                   ┌──────────┴──────────┐
                   │                     │
                   ▼                     ▼
            ┌────────────────┐   ┌──────────────┐
            │ Service Pods   │   │ CronJob Init │
            │ (Authenticate) │   │ (Fetch creds)│
            └────────────────┘   └──────────────┘
                   │
                   ▼
    ┌─────────────────────────────────────┐
    │  IMMUTABLE AUDIT LOG                │
    │  (JSONL in GCS Object Lock WORM)    │
    │  - All credential access logged     │
    │  - 365-day retention, no deletion   │
    │  - Signed checksums                 │
    └─────────────────────────────────────┘
```

---

## Idempotency & Ephemeralness

| Component | Idempotency | Ephemeralness | Governance |
|-----------|------------|---------------|-----------|
| **HTTP Ingestion** | Deduplicates on webhook ID | 24h cleanup of stale requests | Kubernetes Pod lifecycle |
| **Kafka Topics** | Single-partition with dedup key | Manual retention policy (7 days) | Confluent Kafka config |
| **Normalizer** | CronJob restartable at any time (no state loss) | Pods auto-delete after job completion | Kubernetes CronJob spec |
| **PostgreSQL** | RLS + row version tracking | Migrated to GCP SQL (managed) | PITR 7-day backup |
| **Credentials** | Secret versioning (GSM/Vault) | Auto-rotate every 15 min | Lease/TTL enforcement |
| **Deploy Script** | `terraform plan` shows zero drift before apply | Container images immutable (SHA256) | GCR/ECR image pinning |

---

## Direct Development & Deployment Workflow

**NO GitHub Actions. NO PR-based releases.**

1. **Operator clones repo** → Has `scripts/deploy_direct.sh`
2. **Operator runs locally** (or on gitops-enabled CI):
   ```bash
   cd nexus-engine
   IMAGE=gcr.io/my-project/nexus-ingestion TAG=2026-03-12 ./scripts/deploy_direct.sh
   ```
3. **Script does**:
   - Fetches creds from GSM (via authenticated gcloud/vault)
   - Builds Go binary locally
   - Builds Docker image
   - Pushes to registry
   - Prints deployment command for operator's infra tool
4. **Operator deploys** (uses their own infra, Cloud Run, GKE, etc.):
   ```bash
   gcloud run deploy nexus-ingestion --image $IMAGE:$TAG --region us-central1
   ```
5. **Result**: Immutable, versioned service running; audit logged; credentials never in repo

---

## Hands-Off Automation (No-Ops)

**Scheduled via Cloud Scheduler / Kubernetes CronJob:**

| Task | Schedule | Automation | Notes |
|------|----------|-----------|-------|
| **Normalizer batch** | Every 10 min | Kubernetes CronJob | Drain kafka.discovery.raw → normalize → kafka.discovery.normalized |
| **Secret rotation** | Every 15 min | GCP Cloud Function + Vault | Ephemeral TTL enforcement |
| **Health checks** | Every 5 min | Prometheus + Grafana alerts | Page on-call if normalizer lag > 5 min |
| **Audit log snapshot** | Daily 00:00 UTC | Cloud Scheduler | Export JSONL immutable copy to GCS Object Lock |
| **Cleanup expired resources** | Daily 06:00 UTC | Cloud Scheduler → Cloud Function | Delete pods > 24h old, vacuum logs |

---

## Integration Points (Extensibility)

- **Custom Normalizers**: Add `internal/normalizer/{provider}.go` → register in `main()` → auto-wired to Kafka pipeline
- **New Providers**: Extend `proto/discovery.proto` → run `protoc` → regenerate code
- **Monitoring Hooks**: Emit metrics to Prometheus via `/metrics` endpoint (Kubernetes sidecar scrapes)
- **Alert Destinations**: Configure webhook URLs in ops portal UI → send alerts to Slack/PagerDuty/email via GSM secrets

---

## Deployment Checklist (for Operator)

- [ ] Registry login: `gcloud auth configure-docker gcr.io` or `aws ecr get-login`
- [ ] Vault/GSM authenticated: `vault login` or `gcloud auth application-default login`
- [ ] Clone repo: `git clone https://github.com/kushin77/self-hosted-runner.git`
- [ ] Navigate: `cd nexus-engine`
- [ ] Set image env var: `export IMAGE=gcr.io/my-project/nexus-ingestion TAG=2026-03-12`
- [ ] Run deploy script: `./scripts/deploy_direct.sh`
- [ ] Follow printed deployment command for your infra (Cloud Run, GKE, etc.)
- [ ] Monitor ops portal for normalizer pipeline status
- [ ] Check audit logs for credential access

---

## References

- [DEPLOYMENT_DIRECT.md](./DEPLOYMENT_DIRECT.md) - Operator runbook
- [scripts/deploy_direct.sh](./scripts/deploy_direct.sh) - Direct deploy automation
- [scripts/create_kafka_topics.sh](./scripts/create_kafka_topics.sh) - Kafka setup
- [scripts/compile_protos.sh](./scripts/compile_protos.sh) - Proto generation
- [GOVERNANCE_ENFORCEMENT_STATUS_2026_03_11.md](../GOVERNANCE_ENFORCEMENT_STATUS_2026_03_11.md) - Repo-wide governance
