# NEXUS Architecture Deep-Dive
## Complete Technical Blueprint (Portal MVP + Phase 0)

---

## 📊 SYSTEM OVERVIEW

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  NEXUS PLATFORM                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────────────────┐                    ┌──────────────────────────┐ │
│  │   EXTERNAL SOURCES      │                    │   NEXUS CONTROL PLANE    │ │
│  ├─────────────────────────┤                    ├──────────────────────────┤ │
│  │ • GitHub Actions        │──┐                 │  Frontend (Portal MVP)   │ │
│  │ • GitLab CI             │  │   Webhooks      │  • React dashboard       │ │
│  │ • Jenkins               │  │   (HTTPS)       │  • Real-time updates     │ │
│  │ • Bitbucket Pipelines   │  │                 │  • Multi-source view     │ │
│  │ • CircleCI (future)     │  └────────┬────────┤                          │ │
│  │ • Travis CI (future)    │           │        │  Backend (Portal API)    │ │
│  └─────────────────────────┘           │        │  • Express.js            │ │
│                                        │        │  • REST endpoints        │ │
│                                        │        │  • WebSocket (real-time) │ │
│                                        ▼        │                          │ │
│                              ┌──────────────────┤  Discovery API           │ │
│                              │ Ingestion Server │  • /discovery/runs       │ │
│                              │ (Go Binary)      │  • /discovery/status     │ │
│                              │ Port 8080        │                          │ │
│                              └────────┬─────────└──────────────────────────┘ │
│                                       │                                       │
│                       ┌───────────────┼───────────────┐                      │
│                       ▼               ▼               ▼                      │
│                  ┌──────────┐  ┌───────────┐  ┌──────────────┐              │
│                  │  Kafka   │  │PostgreSQL │  │ ClickHouse   │              │
│                  │  Broker  │  │  (RLS)    │  │(Analytics)   │              │
│                  │          │  │           │  │              │              │
│                  │ Topics:  │  │ Tables:   │  │ Tables:      │              │
│                  │ • raw    │  │ • tenants │  │ • metrics    │              │
│                  │ • norm'd │  │ • runs    │  │ • cost       │              │
│                  │          │  │ • webhooks│  │ • duration   │              │
│                  └──────────┘  └───────────┘  └──────────────┘              │
│                       ▲               ▲               ▲                      │
│                       │               │               │                      │
│                  ┌────┴───┬──────┬────┴────┬──────┬───┴────┬──────┐         │
│                  │         │      │         │      │        │      │         │
│              ┌───▼──┐ ┌────▼─┐ ┌─▼──┐ ┌────▼─┐ ┌──▼───┐ ┌──▼──┐ │         │
│              │GitHub│ │GitLab│ │Jenkins │ │Bitbucket │ │Slack │ │         │
│              │ Norm │ │ Norm │ │ Norm │ │ Norm  │ │ Bot  │ │         │
│              │      │ │      │ │      │ │       │ │      │ │         │
│              └──┬───┘ └──┬───┘ └──┬───┘ └──┬────┘ └──┬───┘ │         │
│                 │        │        │        │        │      │         │
│              ┌──┴────────┴────────┴────────┴────────┴──────┘         │
│              │                                                        │
│              │   Event Normalizers (Go)                              │
│              │   • Convert source API → canonical schema             │
│              │   • Idempotent (dedup by source_run_id)              │
│              │   • Status normalization                              │
│              │   • Duration calculation                              │
│              └────────────────────────────────────────────────────┐  │
│                                                                    │  │
│         ┌────────────────────────────────────────────────────────┘  │
│         │                                                             │
│         └──────────────────────────────────────────────────────────┘ │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 🏗️ ARCHITECTURAL LAYERS

### Layer 1: Ingestion (Webhook Receiver)
**Purpose:** Accept incoming webhooks from CI/CD systems  
**Location:** `nexus-engine/cmd/ingestion/main.go`  
**Technology:** Go + HTTP

```go
// Receives webhooks on port 8080
POST /webhook/github       → GitHub Actions pushes workflow results
POST /webhook/gitlab       → GitLab CI pushes pipeline status
POST /webhook/jenkins      → Jenkins pushes build completion
POST /webhook/bitbucket    → Bitbucket Pipelines pushes results
GET  /health               → Health check

// Each endpoint:
1. Validates signature (cryptographic verification)
2. Parses source-specific payload format
3. Publishes raw event to Kafka topic "nexus.pipeline.raw"
4. Returns 200 OK immediately (async processing)
5. Handles & logs errors gracefully
```

**Signature Verification:**
- GitHub: `X-Hub-Signature-256: sha256=<hmac_sha256(secret, body)>`
- GitLab: `X-Gitlab-Token: <secret>` (direct comparison)
- Jenkins: `X-Jenkins-Signature: <hmac_sha256(secret, body)>`

---

### Layer 2: Message Queue (Event Backbone)
**Purpose:** Decouple ingestion from processing  
**Technology:** Apache Kafka 7.7.0

```
Kafka Topics:
├── nexus.pipeline.raw
│   └─ Input: Raw vendor webhook payload (JSON bytes)
│      Partitions: 3 (parallel by source)
│      Retention: 7 days
│
└── nexus.pipeline.normalized
    └─ Output: Canonical discovery.NormalizedEvent
       Partitions: 3 (parallel by source)
       Retention: 30 days
```

**Why Kafka?**
- Decouples ingestion (always fast <100ms) from normalization (variable 100ms-2s)
- Allows multiple consumers (PostgreSQL storage + ClickHouse analytics + Slack alerting)
- Built-in replay (reprocess events if logic changes)
- Horizontal scaling (add consumer nodes)

---

### Layer 3: Normalization (Event Schema Converter)
**Purpose:** Convert source-specific format → canonical schema  
**Location:** `nexus-engine/internal/normalizer/`  
**Technology:** Go

**Process:**
```
Raw GitHub Actions payload
  ↓
NormalizeGitHubWorkflow(payload []byte)
  ↓ [extract fields]
  ├─ run_id → discovery.PipelineRun.source_run_id
  ├─ status → discovery.Status enum
  ├─ commit_sha → discovery.PipelineRun.commit_sha
  ├─ duration_ms → discovery.PipelineRun.duration_ms
  └─ ... [other fields]
  ↓
discovery.NormalizedEvent
  ├─ Source: "github"
  ├─ TenantID: 1
  ├─ Run: discovery.PipelineRun{...}
  ├─ Timestamp: now()
  └─ Raw: [original payload]
  ↓
Publish to Kafka "nexus.pipeline.normalized"
```

**Canonical Schema** (Protocol Buffers):
```protobuf
message PipelineRun {
  string id = 1;                      // Unique within system
  string source_run_id = 2;           // GitHub run ID, GitLab pipeline ID, etc.
  string source = 3;                  // "github" | "gitlab" | "jenkins"
  string repo = 4;                    // "org/repo-name"
  string branch = 5;                  // "main", "feature-xyz"
  string commit_sha = 6;              // git commit hash
  Status status = 7;                  // SUCCESS, FAILED, RUNNING, PENDING, CANCELLED
  int64 duration_ms = 8;              // Total run time
  string triggered_by = 9;            // "push" | "pull_request" | "schedule"
  google.protobuf.Timestamp started_at = 10;
  google.protobuf.Timestamp ended_at = 11;
}

enum Status {
  STATUS_UNSPECIFIED = 0;
  PENDING = 1;
  RUNNING = 2;
  SUCCESS = 3;
  FAILED = 4;
  CANCELLED = 5;
}

message NormalizedEvent {
  string id = 1;                      // UUID for this event
  string source = 2;                  // Source system
  int32 tenant_id = 3;                // Multi-tenant isolation
  PipelineRun run = 4;                // Canonical data
  google.protobuf.Timestamp timestamp = 5;
  bytes raw_payload = 6;              // Original for debugging
}
```

---

### Layer 4: Persistent Storage
**Technology:** PostgreSQL 15 (transactional) + ClickHouse (analytics)

#### PostgreSQL Schema (Multi-Tenant RLS)
```sql
CREATE TABLE tenants (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE pipeline_runs (
  id SERIAL PRIMARY KEY,
  tenant_id INT NOT NULL REFERENCES tenants(id),
  source VARCHAR(50) NOT NULL,          -- "github" | "gitlab" | "jenkins"
  source_run_id VARCHAR(255) NOT NULL,  -- Dedup key
  repo VARCHAR(255),
  branch VARCHAR(255),
  commit_sha VARCHAR(40),
  status VARCHAR(50),                    -- "success" | "failed" | "running"
  duration_ms INT,
  trigger_type VARCHAR(50),              -- "push" | "pull_request"
  started_at TIMESTAMP,
  ended_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(source, source_run_id),         -- Idempotency guarantee
  FOREIGN KEY(tenant_id) REFERENCES tenants(id)
);

CREATE TABLE events (
  id SERIAL PRIMARY KEY,
  tenant_id INT NOT NULL,
  event_type VARCHAR(100),
  payload_json JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY(tenant_id) REFERENCES tenants(id)
);

CREATE TABLE webhooks (
  id SERIAL PRIMARY KEY,
  tenant_id INT NOT NULL,
  service VARCHAR(50),                   -- "github" | "gitlab"
  url VARCHAR(500),
  secret VARCHAR(500),
  last_used_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY(tenant_id) REFERENCES tenants(id)
);

-- Row-Level Security (RLS) - Enforced at database level
ALTER TABLE pipeline_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON pipeline_runs
  USING (tenant_id = current_setting('app.current_tenant_id')::int);
```

**Why PostgreSQL?**
- ACID transactions (consistency for dedup)
- Row-Level Security (multi-tenant isolation enforced at DB)
- JSONB support (flexible for new fields)
- UNIQUE constraint on (source, source_run_id) prevents duplicates

#### ClickHouse Schema (Analytics)
```sql
CREATE TABLE pipeline_metrics (
  tenant_id UInt32,
  date Date,
  source String,
  status String,
  duration_ms UInt32,
  count UInt64
) ENGINE = SummingMergeTree()
ORDER BY (tenant_id, date, source, status);
```

**Why ClickHouse?**
- Optimized for time-series aggregations
- Cost tracking queries (sum(duration_ms) by source)
- Analysis dashboards (failure trends, duration distribution)
- Horizontal scaling (separate from transactional data)

---

### Layer 5: API Layer (Query Interface)
**Technology:** Express.js (Portal MVP) + Go (future)

#### Portal API Endpoints (Portal MVP)
```javascript
// Discovery Endpoints (added Phase 0)
GET /api/v1/discovery/runs
  Query params:
    - source=github|gitlab|jenkins (filter by source)
    - status=success|failed|running (filter by status)
    - limit=50 (default: 50, max: 500)
    - since=2026-03-20T00:00:00Z (filter by time)
    - repo=my-api (filter by repository)
  
  Response:
  {
    "runs": [{
      "id": "abc123",
      "source": "github",
      "repo": "org/repo-name",
      "status": "success",
      "startedAt": "2026-03-20T10:30:00Z",
      "endedAt": "2026-03-20T10:35:30Z",
      "durationMs": 330000,
      "branch": "main",
      "commitSha": "abc123def456",
      "triggeredBy": "push"
    }],
    "metadata": {
      "total": 1024,
      "pageSize": 50,
      "hasMore": true
    }
  }

GET /api/v1/discovery/stats
  Response:
  {
    "stats": {
      "totalRuns": 1024,
      "successCount": 920,
      "failureCount": 104,
      "successRate": 0.898,
      "avgDurationMs": 285000,
      "bySource": {
        "github": { "count": 600, "successRate": 0.92 },
        "gitlab": { "count": 424, "successRate": 0.87 }
      }
    }
  }
```

**Authentication:**
- JWT in `Authorization: Bearer <token>` header
- Tenant extracted from token (enforces RLS)
- Slack bot gets its own service account

---

### Layer 6: Notification & Integration
**Technology:** Slack Bolt for Go

```go
// POST /slack/commands/status
// User: /nexus status
// Response: Block Kit message with stats
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "✅ *45* passed | ❌ *3* failed | ⏳ *2* running"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "Last 24 hours | Success rate: 93.8%"
      }
    }
  ]
}

// POST /slack/events
// Automatic notifications:
// - Pipeline failure → send Slack message to #failures
// - Flaky test detected → send to #flaky-tests
// - Cost spike → send to #cost-alerts
```

---

## 🔄 DATA FLOW SEQUENCES

### Sequence 1: Happy Path (Webhook → Storage)
```
GitHub Action completes
  ↓
1. GitHub sends webhook payload to https://nexus.io/webhook/github
2. Ingestion server receives (100ms), verifies signature
3. Raw payload published to Kafka "nexus.pipeline.raw" (500μs)
4. Normalizer consumer reads from "nexus.pipeline.raw"
5. NormalizeGitHubWorkflow() converts to discovery.NormalizedEvent
6. Normalized event published to "nexus.pipeline.normalized" (1ms)
7. PostgreSQL consumer reads from "nexus.pipeline.normalized"
8. INSERT INTO pipeline_runs (...) (idempotent on source_run_id)
9. ClickHouse consumer reads for analytics (async, lower priority)

Total latency: 100-500ms (from webhook to queryable in Portal)
```

**Timeline visualization:**
```
Time →
0ms    100ms          150ms  200ms           300ms  350ms  400ms  500ms
│      │              │      │               │      │      │      │
└──────┴──────────────┴──────┴───────────────┴──────┴──────┴──────┘
       webhook     signature  publish to       normalize  postgres  query
       arrives      verified   kafka           completes  insert    ready
```

### Sequence 2: Idempotency (Duplicate Webhook)
```
Same webhook sent twice (webhook retry)
  ↓
Time 0:00 - First webhook processed
  → INSERT INTO pipeline_runs(source='github', source_run_id='12345', ...)

Time 0:05 - Same webhook retried (Kafka rebalance, etc.)
  → INSERT INTO pipeline_runs(source='github', source_run_id='12345', ...)
  → UNIQUE constraint violation on (source, source_run_id)
  → INSERT rejected
  → No duplicate in database

Query shows: 1 run (deduped correctly)
```

### Sequence 3: Multi-Tenant Isolation (RLS)
```
Tenant 1: INSERT INTO pipeline_runs(...) WHERE tenant_id=1
  ↓
SET app.current_tenant_id = 1;
SELECT * FROM pipeline_runs;  ✅ Returns rows WHERE tenant_id=1

SET app.current_tenant_id = 2;
SELECT * FROM pipeline_runs;  ❌ Returns nothing (RLS policy)
```

---

## 🔐 SECURITY ARCHITECTURE

### Authentication
- **Webhook Verification:** HMAC-SHA256 signatures (prevents spoofing)
- **API Authentication:** JWT tokens (stateless)
- **Service Accounts:** Slack bot uses dedicated service principal

### Authorization
- **Row-Level Security (RLS):** PostgreSQL enforces `tenant_id` filtering
- **Role-Based Access Control:** Future (Phase 2+)
- **Scope Restrictions:** Slack bot can only read/write own tenant's data

### Data Protection
- **Encryption in Transit:** TLS 1.3 for all webhooks
- **Encryption at Rest:** PostgreSQL with disk encryption
- **Secrets Management:** Webhook secrets stored in database (hashed with bcrypt)
- **GDPR Compliance:** Raw payloads can be archived/purged per retention policy

---

## 📈 SCALABILITY ARCHITECTURE

### Horizontal Scaling (Kafka + Parallelism)
```
3 Kafka partitions
  ↓
Normalizer Consumer Group (3 instances)
  ├─ Instance 1 → Partition 0 (GitHub + Jenkins events)
  ├─ Instance 2 → Partition 1 (GitLab + Bitbucket events)
  └─ Instance 3 → Partition 2 (Future sources)

Each instance processes independently:
✓ Throughput scales linearly (3x events → 3x processing)
✓ Partition leader rebalances if instance fails
✓ No shared state (idempotent by design)
```

### Vertical Scaling (Connection Pooling)
```
PostgreSQL
  ├─ Max connections: 100
  ├─ Pool size: 20 (intake service)
  ├─ Pool size: 20 (Portal API)
  ├─ Pool size: 20 (Slack bot)
  └─ Remaining: 40 (headroom for adhoc queries)

ClickHouse
  ├─ Max connections: 50
  └─ Async consumer (doesn't block critical path)
```

### Monitoring & Observability
```
Prometheus Metrics:
  ├─ nexus_webhooks_received (counter)
  ├─ nexus_events_normalized (counter)
  ├─ nexus_events_stored (counter)
  ├─ nexus_normalization_latency_ms (histogram)
  ├─ nexus_kafka_lag (gauge per topic)
  └─ nexus_database_query_duration_ms (histogram)

Grafana Dashboards:
  ├─ Real-time ingestion (events/min by source)
  ├─ Pipeline health (success rate, MTTR)
  ├─ System health (Kafka lag, DB connections)
  └─ Cost analysis (duration trends, most expensive repos)

Alerts:
  ├─ Kafka lag > 10k messages → PagerDuty
  ├─ Normalization latency > 5s → Slack #alerts
  ├─ Error rate > 1% → PagerDuty
  └─ Database query > 500ms → Slack #performance
```

---

## 🧪 TESTING ARCHITECTURE

### Unit Tests (Function Level)
```
nexus-engine/internal/normalizer/github_test.go
  ├─ TestNormalizeGitHubWorkflow_Success
  ├─ TestNormalizeGitHubWorkflow_InvalidJSON
  ├─ TestNormalizeGitHubWorkflow_MissingFields
  └─ TestNormalizeGitHubWorkflow_StatusMapping

Coverage: >85%
Run: make test
```

### Integration Tests (Component Level)
```
nexus-engine/internal/kafka/producer_test.go
  ├─ TestPublishEvent_Success (Kafka running locally)
  ├─ TestPublishEvent_RetryOnFailure
  └─ TestTopicCreation

nexus-engine/internal/database/postgres_test.go
  ├─ TestInsertPipelineRun_Idempotent
  ├─ TestRLS_TenantIsolation
  └─ TestIndexes_SourceRunIDUnique

Run: make test-integration
Stack: docker-compose.yml (Kafka + PostgreSQL)
```

### End-to-End Tests (Full Pipeline)
```
Create test GitHub repo
  ↓
1. Configure test workflow (deliberately fail sometimes)
2. Push commits, trigger runs
3. Webhook fires → ingestion server
4. Event stored in PostgreSQL
5. Portal API returns event
6. Slack notification sent
7. Query Portal, verify dedup

Success: "Webhook → Portal visible in <1 second"

Run: make test-e2e
Duration: 5-10 minutes (depends on GitHub)
```

### Load Tests
```
Send 100 events to ingestion server simultaneously
  ↓
Measure:
  ├─ Throughput: 100 events processed
  ├─ Latency: p50, p95, p99
  ├─ Errors: 0 (all stored correctly)
  └─ Dedup: 100 unique rows (no duplicates)

Target: 100 events in <10s, zero duplicates

Run: make test-load
```

---

## 🚀 DEPLOYMENT ARCHITECTURE

### Local Development
```
make up
  ↓
docker-compose.yml starts:
  ├─ Kafka broker (port 9092)
  ├─ Zookeeper (port 2181)
  ├─ PostgreSQL (port 5432)
  ├─ ClickHouse (port 8123)
  └─ Ingestion service (port 8080)

All services ready in 30 seconds
```

### Staging (Cloud Run + Cloud SQL)
```
Phase 1 (TBD)

GCP Cloud Run:
  ├─ nexus-ingestion service (3 instances)
  ├─ nexus-normalizer consumer (3 instances)
  └─ nexus-slack-bot service (1 instance)

GCP Cloud SQL:
  └─ PostgreSQL 15 (HA replica)

Confluent Cloud (Kafka):
  └─ Managed Kafka (3 brokers, 3 topics)

Monitoring:
  ├─ Cloud Logging (centralized)
  ├─ Cloud Monitoring (Prometheus ingestion)
  └─ Cloud Trace (latency analysis)
```

### Production (Kubernetes)
```
Phase 2+ (TBD)

Kubernetes Deployments:
  ├─ nexus-ingestion (3 replicas, HPA: min 3, max 10)
  ├─ nexus-normalizer (3 replicas, HPA: min 3, max 10)
  ├─ nexus-slack-bot (2 replicas, no HPA)
  └─ nexus-portal-api (3 replicas, HPA: min 3, max 5)

Kubernetes StatefulSets:
  └─ PostgreSQL operator (for HA + auto-failover)

Kubernetes Services:
  ├─ LoadBalancer for ingestion (multi-region)
  └─ ClusterIP for internal services

ConfigMaps:
  ├─ Database connection strings
  ├─ Kafka broker list
  └─ Feature flags

Secrets:
  ├─ GitHub signing secret
  ├─ GitLab token
  ├─ Slack token
  └─ Database credentials

Service Mesh (Istio):
  ├─ Traffic policies (canary deployments)
  ├─ Circuit breakers (fail fast)
  └─ Distributed tracing
```

---

## 📊 COST MODELING

### Infrastructure Costs (Monthly Estimate for 100k runs/month)

| Component | Qty | Unit Cost | Total |
|-----------|-----|-----------|-------|
| PostgreSQL (Cloud SQL) | 1 | $300 | $300 |
| ClickHouse (Managed) | 1 | $200 | $200 |
| Kafka (Confluent Cloud) | 3 brokers | $200/ea | $600 |
| Cloud Run (ingestion) | 3 instances | $50/mo | $150 |
| Cloud Run (normalizer) | 3 instances | $50/mo | $150 |
| Cloud Run (Portal API) | 3 instances | $75/mo | $225 |
| Monitoring (Datadog) | 1 | $400 | $400 |
| **Total** | | | **$2,025/month** |

**Cost per event:** $2,025 / 100,000 events = $0.020 per run  
**Scaling:** Roughly linear (2x events = 2x cost)

---

## 🎯 PHASE 0 SUCCESS CRITERIA

### Functional
- ✅ Real webhooks from GitHub + GitLab flowing end-to-end
- ✅ Events normalized to canonical schema
- ✅ Events stored in PostgreSQL (searchable)
- ✅ RLS enforced (no cross-tenant reads)
- ✅ Idempotency verified (duplicates rejected)
- ✅ Portal API returns discovery data
- ✅ Slack bot responds to commands

### Non-Functional
- ✅ Unit test coverage >85%
- ✅ Webhook → PostgreSQL latency <1 second
- ✅ Kafka lag <10k messages
- ✅ Zero data leaks under multi-tenant load test
- ✅ Idempotency 100% (3x same event = 1 row)
- ✅ System throughput >100 events/second

### Documentation
- ✅ All architecture decisions documented
- ✅ Run books for deployment + monitoring
- ✅ API documentation (Portal + Slack bot)
- ✅ Team training videos recorded

---

## 🔮 FUTURE ARCHITECTURE (Phases 1-4)

### Phase 1: Dashboard
```
Add: Frontend component for multi-source discovery view
Impact: Zero code changes to ingestion/storage layer
  ✓ Query portal API
  ✓ Render filters + results
  ✓ WebSocket real-time updates
```

### Phase 2: Slack Command Center
```
Add: /nexus tools (retry, explain, trace)
Impact: New agent services (explain engine, trace engine)
  ✓ LLM integration for plain-English explanations
  ✓ Historical correlation analysis
  ✓ Auto-diagnosis recommendations
```

### Phase 3: Auto-Fix Arsenal
```
Add: Narrow auto-fixes for common failures
Impact: New execution service (safe-mode auto-remediation)
  ✓ Env var suggestion (from successful runs)
  ✓ Flaky test quarantine (probability-based)
  ✓ Resource limit increase (from timing data)
  ✓ All fixes require approval before merge
```

### Phase 4: Sovereign Product
```
Add: Terraform modules for self-hosted deployment
Impact: Portable, runnable on any Kubernetes
  ✓ Cloud-agnostic (AWS, GCP, Azure, on-prem)
  ✓ Single-tenant (not SaaS)
  ✓ Draw.io visual pipeline editor
  ✓ Multi-chat support (Teams, Discord, Mattermost)
```

---

## 📚 APPENDIX: TECHNOLOGY CHOICES

| Component | Choice | Why |
|-----------|--------|-----|
| **Language** | Go 1.21 | Fast, compiled, native concurrency, cloud-native |
| **Message Queue** | Kafka | Industry-standard, proven at scale, replay capability |
| **Transactional DB** | PostgreSQL 15 | ACID, RLS for multi-tenant, JSONB flexibility |
| **Analytics DB** | ClickHouse | Built for time-series, compressed storage, fast aggregations |
| **Frontend** | React + TypeScript | Type-safe, large ecosystem, familiar to teams |
| **Backend Framework** | Express.js | Lightweight, async, WebSocket support |
| **IaC** | Terraform | Cloud-agnostic, version-controlled, no vendor lock-in |
| **Container** | Docker | Industry standard, works everywhere |
| **Orchestration** | Kubernetes | Future-proof, multi-region ready, CNCF standard |
| **Schema** | Protocol Buffers | Language-neutral, versioning, compact binary |
| **Slack** | Bolt for Go | Official library, idiomatic Go, maintained by Slack |

---

**Status:** 🟢 ARCHITECTURE COMPLETE  
**Ready for:** Phase 0 development (March 12-April 2)  
**Questions?** Refer to [NEXUS_DOCUMENTATION_INDEX.md](NEXUS_DOCUMENTATION_INDEX.md)

