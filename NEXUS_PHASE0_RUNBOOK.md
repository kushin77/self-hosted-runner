# NEXUS Phase 0 — Execution Runbook
## "From Webhook to Discovery" (March 12-April 2, 2026)

---

## 📋 DEPENDENCIES & SEQUENCING

```
┌─────────────────────────────────────────────────────┐
│ CRITICAL PATH (must complete in order)              │
├─────────────────────────────────────────────────────┤
│ 1. PostgreSQL Schema + RLS (Day 1)                  │
│    ↓ [All other tasks depend on this]              │
│ 2. Kafka Topics + Producer/Consumer (Day 2)        │
│    ↓                                                │
│ 3. GitHub webhook normalizer (Day 3)               │
│    ↓                                                │
│ 4. GitLab webhook normalizer (Day 3-4)             │
│    ↓                                                │
│ 5. Idempotency verification (Day 5)                │
│                                                     │
├─────────────────────────────────────────────────────┤
│ PARALLEL TRACKS (independent, can start anytime)    │
├─────────────────────────────────────────────────────┤
│ Track A: Jenkins integration (Day 4-5)             │
│ Track B: Portal API endpoints (Day 3+)            │
│ Track C: Slack bot foundation (Day 5+)            │
│ Track D: Monitoring + alerting (Day 5+)          │
└─────────────────────────────────────────────────────┘
```

---

## 🎯 DAILY BREAKDOWN (Weeks 1-3)

### **WEEK 1: Foundation** (March 12-19)

#### Day 1 (March 12) — Database First
**Goal:** PostgreSQL running, schema applied, RLS tested

**Linked Issue:** [#2688 - PostgreSQL + ClickHouse Schema](https://github.com/kushin77/self-hosted-runner/issues/2688)

**Checklist:**
- [ ] `docker-compose up postgres` → PostgreSQL running on localhost:5432
- [ ] `psql -h localhost -U postgres -d nexus < database/migrations/001_init_schema.sql` → schema applied
- [ ] Verify tables exist:
  ```sql
  \d tenants
  \d pipeline_runs
  \d webhooks
  \d events
  ```
- [ ] Test RLS:
  ```sql
  SET app.current_tenant_id = 1;
  INSERT INTO pipeline_runs (...) VALUES (...);
  SELECT * FROM pipeline_runs;  -- Should return 1 row
  
  SET app.current_tenant_id = 2;
  SELECT * FROM pipeline_runs;  -- Should return 0 rows
  ```
- [ ] Insert test tenant + webhook secret
  ```sql
  INSERT INTO tenants (id, name) VALUES (1, 'test-org');
  INSERT INTO webhooks (tenant_id, service, url, secret) 
    VALUES (1, 'github', 'https://../', 'test-secret-123');
  ```
- [ ] Test idempotency:
  ```sql
  INSERT INTO pipeline_runs (source, source_run_id, ...) VALUES ('github', '12345', ...);
  INSERT INTO pipeline_runs (source, source_run_id, ...) VALUES ('github', '12345', ...);  -- Should fail: unique constraint
  ```

**Success Criteria:**
- ✅ PostgreSQL accessible remotely
- ✅ Schema reflects proto messages (pipeline_runs has all fields from discovery.PipelineRun)
- ✅ RLS policies prevent cross-tenant reads
- ✅ Deduplication index prevents duplicate source_run_ids

**Deliverable:**
- Updated [#2688](https://github.com/kushin77/self-hosted-runner/issues/2688) with "schema tested locally" comment + SQL test results

---

#### Day 2 (March 13) — Kafka Setup
**Goal:** Kafka running, topics created, producer/consumer tested

**Linked Issue:** [#2687 - Kafka Ingestion Pipeline](https://github.com/kushin77/self-hosted-runner/issues/2687)

**Checklist:**
- [ ] `docker-compose up kafka zookeeper` → Kafka running on localhost:9092
- [ ] Create topics:
  ```bash
  docker exec nexus-kafka kafka-topics \
    --create \
    --topic nexus.pipeline.raw \
    --partitions 3 \
    --replication-factor 1 \
    --bootstrap-server localhost:9092
  
  docker exec nexus-kafka kafka-topics \
    --create \
    --topic nexus.pipeline.normalized \
    --partitions 3 \
    --replication-factor 1 \
    --bootstrap-server localhost:9092
  ```
- [ ] Verify topics:
  ```bash
  docker exec nexus-kafka kafka-topics \
    --list \
    --bootstrap-server localhost:9092
  ```
- [ ] Test producer:
  ```bash
  make test-producer
  # Should output: "Published 10 messages to nexus.pipeline.raw"
  ```
- [ ] Test consumer:
  ```bash
  make test-consumer
  # Should output: "Received message: {...}" 10 times
  ```
- [ ] Verify message schema via Protobuf:
  ```bash
  make proto-compile
  # Should generate: pkg/proto/*.pb.go
  ```

**Code Changes:**
- `internal/kafka/producer_test.go` — add PublishEvent() happy path test
- `internal/kafka/consumer_test.go` — add ConsumeNormalizedEvents() happy path test
- `Makefile` — add `test-producer` and `test-consumer` targets

**Success Criteria:**
- ✅ Both topics exist
- ✅ Producer publishes 10 messages without error
- ✅ Consumer reads all 10 messages in order
- ✅ Message schema matches proto definition
- ✅ Partitioning verified (messages distributed across 3 partitions)

**Deliverable:**
- Updated [#2687](https://github.com/kushin77/self-hosted-runner/issues/2687) with "Kafka pipeline tested" + test results

---

#### Day 3 (March 14) — GitHub Normalizer ✨
**Goal:** GitHub webhook payloads convert → normalized events

**Linked Issue:** [#2691 - Discovery Normalizer](https://github.com/kushin77/self-hosted-runner/issues/2691)

**Checklist:**
- [ ] Review GitHub webhook payload format (save sample payload to `test-fixtures/github-workflow-run.json`)
- [ ] Implement `internal/normalizer/github.go` → `NormalizeGitHubWorkflow()`
  ```go
  func NormalizeGitHubWorkflow(payload []byte) (*discovery.NormalizedEvent, error) {
    // 1. Unmarshal GitHub webhook JSON
    // 2. Extract: run_id, status, repo, branch, commit_sha, duration_ms
    // 3. Normalize status: "success" → discovery.Status_SUCCESS, etc.
    // 4. Build discovery.PipelineRun
    // 5. Return discovery.NormalizedEvent with metadata
    // 6. Handle errors: invalid JSON, missing fields
  }
  ```
- [ ] Write unit tests:
  ```go
  func TestNormalizeGitHubWorkflow_Success(t *testing.T) {
    payload := loadFixture("test-fixtures/github-workflow-run.json")
    event, err := NormalizeGitHubWorkflow(payload)
    assert.NoError(t, err)
    assert.Equal(t, "github", event.Source)
    assert.Equal(t, discovery.Status_SUCCESS, event.Run.Status)
  }
  
  func TestNormalizeGitHubWorkflow_InvalidJSON(t *testing.T) {
    event, err := NormalizeGitHubWorkflow([]byte("invalid"))
    assert.Error(t, err)
    assert.Nil(t, event)
  }
  
  func TestNormalizeGitHubWorkflow_MissingFields(t *testing.T) {
    // Test with incomplete payload
  }
  ```
- [ ] Create webhook signature verification:
  ```go
  func VerifyGitHubSignature(r *http.Request, secret string) error {
    // 1. Get X-Hub-Signature-256 header
    // 2. Compute HMAC-SHA256(payload, secret)
    // 3. Compare timing-safe
    // 4. Return error if mismatch
  }
  ```
- [ ] Test with real GitHub webhook:
  ```bash
  # Create test GitHub Actions workflow
  # Push to feature branch
  # Webhook fires → ingestion service receives
  # Check logs: "Received GitHub webhook for run_id=..."
  ```

**Code Structure:**
```
internal/normalizer/
├── github.go          (NormalizeGitHubWorkflow → discovery.NormalizedEvent)
├── github_test.go     (unit tests)
├── types.go          (shared error types)
└── fixtures/
    └── github-workflow-run.json
```

**Success Criteria:**
- ✅ Unit tests pass (>90% coverage for github.go)
- ✅ Real GitHub webhook payload normalizes correctly
- ✅ Signature verification prevents spoofing
- ✅ All GitHub status values map to discovery.Status enum
- ✅ source_run_id extracted correctly (used for dedup)

**Deliverable:**
- Updated [#2691](https://github.com/kushin77/self-hosted-runner/issues/2691) with "GitHub normalizer complete + tested"
- Commit message: "feat(normalizer): GitHub workflow normalization with signature verification"

---

#### Day 4 (March 15) — GitLab Normalizer
**Goal:** GitLab webhook payloads convert → normalized events

**Same structure as Day 3, but for GitLab**

**Checklist:**
- [ ] Review GitLab webhook payload format
- [ ] Implement `internal/normalizer/gitlab.go`
- [ ] Write unit tests (same pattern as GitHub)
- [ ] Create GitLab signature verification (X-Gitlab-Token header)
- [ ] Test with real GitLab webhook

**Success Criteria:**
- ✅ Unit tests pass (>90% coverage)
- ✅ Real GitLab webhook normalizes correctly
- ✅ Signature verification prevents spoofing
- ✅ All GitLab status values map correctly

---

#### Day 5 (March 16) — Integration Testing
**Goal:** Full pipeline working: webhook → Kafka → normalizer → PostgreSQL

**Checklist:**
- [ ] Start full stack: `make up`
- [ ] Send GitHub webhook via curl:
  ```bash
  PAYLOAD=$(cat test-fixtures/github-workflow-run.json)
  SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "github-secret" | cut -d' ' -f2)
  
  curl -X POST http://localhost:8080/webhook/github \
    -H "X-Hub-Signature-256: sha256=$SIGNATURE" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
  ```
- [ ] Verify Kafka topic received event:
  ```bash
  docker exec nexus-kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic nexus.pipeline.raw \
    --from-beginning \
    --max-messages 1
  ```
- [ ] Verify PostgreSQL received event:
  ```bash
  psql -h localhost -U postgres -d nexus -c \
    "SELECT source, source_run_id, status FROM pipeline_runs ORDER BY created_at DESC LIMIT 1;"
  ```
- [ ] Test idempotency:
  ```bash
  # Send same webhook 3x
  # PostgreSQL should have exactly 1 row (deduped by source_run_id)
  ```
- [ ] Test via both GitHub + GitLab:
  ```bash
  # Send GitHub webhook
  # Send GitLab webhook
  # Both should appear in pipeline_runs table with different source
  ```

**Success Criteria:**
- ✅ Webhook → Kafka → Database happy path works
- ✅ Idempotency verified (3x same event = 1 DB row)
- ✅ Both GitHub + GitLab events flow correctly
- ✅ Latency < 1 second (webhook → DB)

**Deliverable:**
- Updated [#2692 - Phase 0 Epic](https://github.com/kushin77/self-hosted-runner/issues/2692) with "Week 1 shipped: full pipeline working end-to-end"

---

### **WEEK 2: Integration** (March 19-26)

#### Day 6 (March 19) — Jenkins Integration
**Goal:** Jenkins webhooks normalize → same schema as GitHub/GitLab

**Linked Issue:** [#2687 - Kafka Ingestion Pipeline](https://github.com/kushin77/self-hosted-runner/issues/2687)

**Checklist:**
- [ ] Review Jenkins webhook format
- [ ] Implement `internal/normalizer/jenkins.go`
- [ ] Handle Jenkins status codes (0=success, non-zero=failed)
- [ ] Extract run_id, build_number, job_name, branch
- [ ] Write unit tests
- [ ] Test with curl (no real Jenkins needed yet)

**Success Criteria:**
- ✅ Jenkins payloads convert to discovery.PipelineRun
- ✅ Unit tests pass

---

#### Day 7 (March 20) — Portal API Extensions
**Goal:** Portal can query discovery data

**Linked Issue:** [#2690 - Portal API Integration](https://github.com/kushin77/self-hosted-runner/issues/2690)

**Checklist:**
- [ ] Create `portal/src/routes/discovery.ts`:
  ```typescript
  GET /api/v1/discovery/runs → {
    runs: [{
      id: "abc123",
      source: "github",
      repo: "repo-name",
      status: "success|failed|running|pending",
      startedAt: "2026-03-20T10:30:00Z",
      endedAt: "2026-03-20T10:35:30Z",
      durationMs: 330000,
      branch: "main",
      commitSha: "abc123def456",
      triggeredBy: "push|pull_request|schedule"
    }]
  }
  ```
- [ ] Implement filters:
  - `?source=github` → only GitHub runs
  - `?status=failed` → only failed runs
  - `?limit=50` → last 50 runs
  - `?since=2026-03-20T00:00:00Z` → runs after timestamp
  - `?repo=my-api` → single repo
- [ ] Connect to PostgreSQL (use same RLS tenant_id)
- [ ] Add sorting by `startedAt DESC` (newest first)
- [ ] Write tests

**Code Structure:**
```typescript
// portal/src/routes/discovery.ts
async function getRuns(req: Request, res: Response) {
  const { source, status, limit, since, repo } = req.query;
  const tenantId = req.user.tenantId;  // From auth middleware
  
  let query = `
    SELECT * FROM pipeline_runs 
    WHERE tenant_id = $1
  `;
  const params = [tenantId];
  
  if (source) {
    query += ` AND source = $${params.length + 1}`;
    params.push(source);
  }
  
  // ... more filters ...
  
  query += ` ORDER BY started_at DESC LIMIT ${limit || 50}`;
  
  const result = await pool.query(query, params);
  res.json({ runs: result.rows });
}
```

**Success Criteria:**
- ✅ Portal API returns database records
- ✅ RLS enforced (tenant1 can't see tenant2's runs)
- ✅ Filters work correctly
- ✅ Sorting by timestamp works

**Deliverable:**
- Updated [#2690](https://github.com/kushin77/self-hosted-runner/issues/2690) with "Portal API endpoints live"
- Commit: "feat(portal): discovery API endpoints with filtering"

---

#### Day 8 (March 21) — Slack Bot Foundation
**Goal:** Slack bot listens to /nexus commands, returns status

**Linked Issue:** [#2689 - Basic Slack Bot](https://github.com/kushin77/self-hosted-runner/issues/2689)

**Checklist:**
- [ ] Create Slack app (https://api.slack.com/apps)
- [ ] Set Bearer token as env var: `SLACK_BOT_TOKEN`
- [ ] Create `internal/slack/handler.go`:
  ```go
  func HandleStatusCommand(ctx context.Context, payload *slack.SlashCommandsPayload) error {
    // 1. Get last 10 pipeline_runs from PostgreSQL
    // 2. Count by status: success/failed/running
    // 3. Format Slack message block:
    //    "✅ 45 passed | ❌ 3 failed | ⏳ 2 running"
    // 4. Send via Slack API
    // 5. Return response immediately (no timeout)
  }
  ```
- [ ] Register command as HTTP endpoint: `POST /slack/commands/status`
- [ ] Add Slack signature verification (X-Slack-Request-Timestamp, X-Slack-Signature)
- [ ] Write tests

**Code Structure:**
```go
// internal/slack/handler.go
type CommandHandler struct {
  slackClient *slack.Client
  db          *sql.DB
}

func (h *CommandHandler) HandleStatusCommand(ctx context.Context, cmd *slack.SlashCommandsPayload) error {
  // Get stats from DB
  stats, err := h.db.QueryRow(ctx, `
    SELECT 
      COUNT(*) filter (WHERE status='success') as success,
      COUNT(*) filter (WHERE status='failed') as failed,
      COUNT(*) filter (WHERE status='running') as running,
      COUNT(*) as total
    FROM pipeline_runs 
    WHERE tenant_id = $1 
      AND created_at > NOW() - INTERVAL '24 hours'
  `, getCurrentTenantID()).Scan(&stats)
  
  // Create Slack message
  msg := &slack.Message{
    Blocks: []slack.Block{
      slack.NewSectionBlock(nil, &slack.TextBlockObject{
        Type: slack.PlainTextType,
        Text: fmt.Sprintf("✅ %d passed | ❌ %d failed | ⏳ %d running", stats.Success, stats.Failed, stats.Running),
      }, nil),
    },
  }
  
  // Send response
  _, _, err = h.slackClient.PostMessageContext(ctx, cmd.ChannelID, slack.MsgOptionBlocks(msg.Blocks...))
  return err
}
```

**Success Criteria:**
- ✅ /nexus status returns stats in Slack
- ✅ Signature verification prevents spoofing
- ✅ Runs on Platform with live database connection
- ✅ <3 second response time

---

#### Days 9-10 (March 22-23) — Observability

**Checklist:**
- [ ] Add structured logging (Zap) to all critical paths
- [ ] Add Prometheus metrics:
  - `nexus_webhooks_received` (counter)
  - `nexus_events_normalized` (counter)
  - `nexus_events_stored` (counter)
  - `nexus_normalization_latency_ms` (histogram)
- [ ] Create Grafana dashboard showing:
  - Events per minute by source
  - Normalization latency p50/p95/p99
  - Kafka lag per topic
  - Database query times
  - Error rates by type
- [ ] Set up alerting:
  - Alert if Kafka lag > 10k messages
  - Alert if normalization latency > 5s
  - Alert if error rate > 1%

**Success Criteria:**
- ✅ All critical paths instrumented
- ✅ Grafana dashboard shows real data
- ✅ Alerts configured in PagerDuty or similar

---

### **WEEK 3: Testing & Documentation** (March 26-April 2)

#### Days 11-12 (March 26-27) — End-to-End Testing

**Goal:** Real-world workflow: push → webhook → discovery visible

**Checklist:**
- [ ] Create test GitHub repo: `test-nexus-discovery`
- [ ] Add GitHub Actions workflow that deliberately fails sometimes
- [ ] Push 10 commits, trigger 10 runs
- [ ] Verify all 10 appear in Portal within 30 seconds
- [ ] Verify Slack notifications sent for failures <30s after run ends
- [ ] Test idempotency: webhook retry → still deduped in database
- [ ] Load test: publish 100 events → verify all 100 stored in <10s, no duplicates

**Success Criteria:**
- ✅ Real workflow visible in Portal
- ✅ Real Slack alerts working
- ✅ Deduplication proven
- ✅ Load test < 10s for 100 events

---

#### Days 13-14 (March 28-April 2) — Documentation & Handoff

**Checklist:**
- [ ] Update [nexus-engine/README.md](nexus-engine/README.md) with real test results
- [ ] Create deployment guide (docker-compose → Kubernetes)
- [ ] Document all Slack commands
- [ ] Document all Portal API endpoints
- [ ] Create troubleshooting guide
- [ ] Record video walkthrough (15 min)

**Deliverable:**
- Updated [#2692 - Phase 0 Epic](https://github.com/kushin77/self-hosted-runner/issues/2692) with "Phase 0 COMPLETE ✅"
- All 6 GitHub issues closed
- Ready to start Phase 1 (Studio dashboard)

---

## 🧪 TESTING STRATEGY

### Unit Tests (individual functions)
```bash
make test
# Expected: >80% coverage
```

### Integration Tests (component → component)
```bash
make test-integration
# Expected: all happy paths + sad paths pass
```

### End-to-End Tests (entire pipeline)
```bash
make test-e2e
# Expected: real webhook → portal visible
```

### Load Tests
```bash
make test-load
# Expected: 100 events in <10s, deduped correctly
```

---

## 📊 SUCCESS METRICS (Phase 0 Done)

| Metric | Target | Method |
|--------|--------|--------|
| Unit test coverage | >85% | `make coverage` |
| All GitHub issues closed | 6/6 | GitHub issues panel |
| Real webhook latency | <1s | Send webhook, time DB query |
| Deduplication accuracy | 100% | Send 3x same event, verify 1 DB row |
| Slack integration uptime | 99.9% | Monitor for 1 week |
| Portal API response time | <200ms | `ab -n 1000 http://localhost:3000/api/v1/discovery/runs` |
| Database query accuracy | 100% | Manual spot checks |

---

## 🚨 RISK REGISTER

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Kafka topic lag grows unbounded | Medium | High | Add alerting, increase consumer parallelism |
| PostgreSQL RLS broken (tenant data leaks) | Low | Critical | Write RLS-specific tests, manual audit |
| GitHub/GitLab schema changes | Medium | Medium | Version webhook payloads, handle unknown fields gracefully |
| Slack bot token expires | Low | Medium | Implement token refresh, set calendar reminder |
| Deduplication index broken | Low | Critical | Comprehensive unit + integration tests |

---

## 📝 DEFINITION OF DONE (Phase 0)

Phase 0 is complete when:

✅ All 6 GitHub issues closed  
✅ Real webhooks flowing end-to-end  
✅ Portal shows discovery data  
✅ Slack bot responds to commands  
✅ >85% unit test coverage  
✅ Zero data leaks (RLS enforced)  
✅ Deduplication verified  
✅ <1s latency webhook → database  
✅ Documentation complete  
✅ Team trained + confident  

---

**Next Phase:** Phase 1 — Discovery Dashboard (multi-source unified view with filters)  
**Timeline:** April 2-16, 2026

