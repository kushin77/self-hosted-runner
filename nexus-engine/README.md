# NEXUS Engine — Phase 0 Implementation

**Status:** In Development (Phase 0)  
**Timeline:** March 12-26, 2026  
**Goal:** Kafka-backed event ingestion + discovery normalization + basic Slack integration

---

## 📋 Overview

NEXUS Engine is the intelligence layer that:
1. **Ingests** events from GitHub Actions, GitLab CI, Jenkins, Bitbucket Pipelines
2. **Normalizes** them to a canonical `NexusDiscoveryEvent` schema
3. **Stores** in PostgreSQL + ClickHouse with multi-tenant isolation
4. **Delivers** via Kafka to downstream consumers (dashboards, AI engines, Slack bot)

## 🏗️ Phase 0 Architecture

```
GitHub/GitLab/Jenkins/Bitbucket webhooks
    ↓
Ingestion Service (Go, :8080)
    ├── GitHub normalizer
    ├── GitLab normalizer
    ├── Jenkins normalizer (coming)
    └── Bitbucket normalizer (coming)
    ↓
Kafka nexus.discovery.raw topic
    ↓
PostgreSQL (Aurora/self)         ClickHouse (analytics)
├── runs                          ├── events fact table
├── steps                         └── daily metrics
└── audit_log
```

## 🚀 Quick Start

### Prerequisites
- Go 1.21+
- Docker & Docker Compose
- PostgreSQL 16+ (or use Docker)
- Kafka 7.7+ (or use Docker)

### Step 1: Start Services

```bash
cd nexus-engine
make up
```

This starts:
- Kafka (localhost:9092)
- PostgreSQL (localhost:5432, user: nexus). Password must be provided via a secret manager (GSM/Vault/KMS). Do NOT store real secrets in the repo.
- Redis (localhost:6379)

### Step 2: Apply Database Migrations

```bash
make db-migrate
```

### Step 3: Build & Run Ingestion Service

```bash
make run
```

Service listens on `http://localhost:8080`

### Step 4: Send Test Event

```bash
# GitHub webhook
curl -X POST http://localhost:8080/webhook/github \
  -H "Content-Type: application/json" \
  -d @test/github-webhook.json

# GitLab webhook
curl -X POST http://localhost:8080/webhook/gitlab \
  -H "Content-Type: application/json" \
  -d @test/gitlab-webhook.json
```

### Step 5: Verify in Kafka

```bash
docker exec nexus-engine-kafka-1 kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic nexus.discovery.raw \
  --from-beginning
```

### Step 6: Query PostgreSQL

```bash
psql -h localhost -U nexus -d nexus -c "SELECT * FROM runs;"
```

---

## 📁 Project Structure

```
nexus-engine/
├── cmd/
│   └── ingestion/        # Main webhook receiver service
├── internal/
│   ├── kafka/            # Kafka producer/consumer
│   ├── normalizer/       # GitHub/GitLab/Jenkins/Bitbucket converters
│   ├── db/               # PostgreSQL + RLS helpers
│   └── slack/            # Slack bot integration (Phase 2)
├── pkg/
│   └── discovery/        # Canonical event types
├── database/
│   └── migrations/       # SQL migration files
├── proto/                # Protobuf definitions
├── docker-compose.yml    # Local dev environment
├── go.mod               # Go dependencies
└── Makefile             # Build commands
```

---

## 🔄 Data Flow Example

### What happens when GitHub Actions finishes a run:

1. **Webhook received** at POST `/webhook/github`
   - HMAC verified (phase 2)
   - Rate limited (phase 2)

2. **GitHub normalizer parses** the payload
   - Extracts: repo, branch, status, duration, cost, user, commit
   - Maps GitHub statuses → canonical (e.g., "failure" → "failed")
   - Infers environment from branch name (main → prod, develop → staging)
   - Generates unique ID: `github-<workflow_run_id>-<nanos>`

3. **Event published** to Kafka `nexus.discovery.raw`
   - Key: `github-<run_id>` (for partitioning + idempotency)
   - Value: JSON-serialized `NexusDiscoveryEvent`

4. **Discovery consumer** reads from Kafka
   - Deduplicates by ID (Kafka key ensures idempotent writes)
   - Inserts into PostgreSQL `runs` table
   - Inserts into ClickHouse for analytics

5. **Downstream consumers** (Phase 1+)
   - Studio dashboard queries PostgreSQL
   - Slack bot reads latest runs
   - AI engines read from ClickHouse for pattern analysis

---

## 🧪 Testing

### Unit Tests
```bash
make test
```

Covers:
- GitHub normalizer (various conclusions)
- GitLab normalizer (various statuses)
- Kafka producer/consumer
- Deduplication logic

### Integration Tests
```bash
make test-integration
```

Covers:
- Real Kafka cluster
- Real PostgreSQL
- End-to-end webhook → DB flow

---

## 📊 Metrics & Observability

Every service logs structured JSON:
```
{"level":"info","msg":"published discovery event","source":"github","repo":"company/frontend","status":"success","duration_ms":180000,"timestamp":"2026-03-12T10:30:00Z"}
```

### Key metrics to monitor:
- Webhook latency (P50, P95, P99)
- Normalization errors per source
- Kafka lag (discovery-consumer)
- PostgreSQL insert rate
- Deduplication rate

---

## ⚙️ Configuration

### Environment Variables

```bash
# Kafka
KAFKA_BROKERS=localhost:9092          # Comma-separated brokers

# PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_USER=nexus
# Provide DB password via secret manager and reference in runtime envs (e.g., set `DB_PASSWORD` from GSM/Vault).
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=nexus

# Ingestion service
PORT=8080
LOG_LEVEL=info                        # debug|info|warn|error
```

### GitHub App Setup (Phase 2)

```
Organization: <your-org>
Webhook URL: https://<domain>/webhook/github
Events: workflow_runs
Permissions: read (workflows)
```

### GitLab Integration (Phase 2)

```
System Hooks or Project Hooks
URL: https://<domain>/webhook/gitlab
Trigger: Pipeline events
Secret token: store the webhook secret in GSM/Vault and expose to the runtime via an env var (e.g., `GITLAB_WEBHOOK_SECRET`). Do NOT commit secrets.
```

---

## 🚨 Known Limitations (Phase 0)

- ❌ No webhook signature verification yet (Phase 2)
- ❌ No rate limiting (Phase 2)
- ❌ Jenkins/Bitbucket normalizers not implemented (Phase 1)
- ❌ Cost estimation very rough (will be refined with real data)
- ❌ Slack notifications not implemented (Phase 2)
- ❌ No dead-letter queue for unparseable events (will add)

---

## 🎯 Phase 0 Success Criteria

- [ ] All services run via `make up` without crashes
- [ ] Test events flow: GitHub → Kafka → PostgreSQL → readable
- [ ] Unit + integration tests pass with >80% coverage
- [ ] Documentation complete for Phase 1 team
- [ ] Zero data loss across service restarts
- [ ] Deduplication verified (send same event 3x, 1 DB row)

---

## 📞 Support

**Issues?** Check:
1. Are services running? `docker ps`
2. Are logs clean? `docker logs nexus-engine-ingestion-1`
3. Can you connect to PostgreSQL? `psql -U nexus -d nexus -c "SELECT 1;"`
4. Is Kafka running? `docker logs nexus-engine-kafka-1`

---

## 🔗 Next Steps (Phase 1)

- [ ] Studio discovery dashboard (unified view)
- [ ] Real-time WebSocket updates
- [ ] Failure reason grouping + analysis
- [ ] Cost attribution per pipeline/repo
- [ ] Environmental awareness (dev/staging/prod)
- [ ] Pipeline DAG visualization

---

**Created:** March 12, 2026  
**Version:** 0.1.0-alpha  
**Status:** In Development
