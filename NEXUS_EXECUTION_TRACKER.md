# NEXUS Phase 0 — Master Execution Tracker
## Day-by-Day Task Tracking (March 12 - April 2, 2026)

**Master List:** 42 tracked tasks across 3 weeks | 6 GitHub issues | 3 critical paths

---

## 📅 WEEK 1: Foundation (March 12-19)

### Day 1 (March 12) — DATABASE SETUP
**Goal:** PostgreSQL running, schema applied, RLS tested  
**Assigned to:** Database Engineer  
**GitHub Issue:** [#2688](https://github.com/kushin77/self-hosted-runner/issues/2688)

#### Pre-work
- [ ] **1.1** Read [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) Day 1 section (15 min)
- [ ] **1.2** Review PostgreSQL schema file (5 min)

#### Setup
- [ ] **1.3** Start PostgreSQL: `docker-compose up postgres` (5 min)
- [ ] **1.4** Verify connection: `psql -h localhost -U postgres` (2 min)
- [ ] **1.5** Create database: `createdb -h localhost -U postgres nexus` (1 min)

#### Schema Application
- [ ] **1.6** Apply migrations: `psql -h localhost -U postgres -d nexus < database/migrations/001_init_schema.sql` (2 min)
- [ ] **1.7** Verify tables exist: `\d` command shows 4 tables (2 min)
- [ ] **1.8** Verify indexes: `\d pipeline_runs` shows UNIQUE(source, source_run_id) (2 min)

#### Testing
- [ ] **1.9** Test RLS: Insert as tenant 1, select as tenant 2 (verify no data leak) (10 min)
- [ ] **1.10** Insert test data: 1 tenant, 1 webhook secret (2 min)
- [ ] **1.11** Test idempotency: Send 3x same (source, source_run_id), verify 1 row (5 min)

#### Documentation
- [ ] **1.12** Comment on #2688: "Schema applied + RLS verified" with test results (5 min)
- [ ] **1.13** Create `SCHEMA_TEST_RESULTS.md` file with SQL commands + outputs (10 min)

**Success Criteria:**
- ✅ PostgreSQL accessible on localhost:5432
- ✅ 4 tables created (tenants, pipeline_runs, events, webhooks)
- ✅ RLS policy prevents cross-tenant reads
- ✅ UNIQUE constraint prevents duplicates
- ✅ GitHub issue #2688 updated with results

**Blocker Risk:** Low | **Critical for:** All other tasks

---

### Day 2 (March 13) — KAFKA SETUP
**Goal:** Kafka running, topics created, producer/consumer tested  
**Assigned to:** Backend Engineer (Messaging)  
**GitHub Issue:** [#2687](https://github.com/kushin77/self-hosted-runner/issues/2687)

#### Pre-work
- [ ] **2.1** Review [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) Day 2 section (15 min)
- [ ] **2.2** Read docker-compose.yml Kafka config (5 min)

#### Setup
- [ ] **2.3** Start Kafka stack: `docker-compose up kafka zookeeper` (10 min)
- [ ] **2.4** Wait for Kafka to be ready (check logs) (5 min)
- [ ] **2.5** Verify broker on port 9092: `docker logs nexus-kafka` (2 min)

#### Topic Creation
- [ ] **2.6** Create raw topic: `docker exec nexus-kafka kafka-topics --create --topic nexus.pipeline.raw --partitions 3 --replication-factor 1` (2 min)
- [ ] **2.7** Create normalized topic: `docker exec nexus-kafka kafka-topics --create --topic nexus.pipeline.normalized --partitions 3 --replication-factor 1` (2 min)
- [ ] **2.8** List topics: `docker exec nexus-kafka kafka-topics --list` (verify 2 new topics) (1 min)

#### Code Tests
- [ ] **2.9** Create `internal/kafka/producer_test.go` with TestPublishEvent_Success (20 min)
- [ ] **2.10** Create `internal/kafka/consumer_test.go` with TestConsumeNormalizedEvents_Success (20 min)
- [ ] **2.11** Add Makefile targets: `test-producer` and `test-consumer` (10 min)
- [ ] **2.12** Run tests: `make test-producer` (should publish 10 messages) (5 min)
- [ ] **2.13** Run tests: `make test-consumer` (should receive 10 messages) (5 min)

#### Protobuf Build
- [ ] **2.14** Configure protoc in Makefile (5 min)
- [ ] **2.15** Run `make proto-compile` → generates `pkg/proto/*.pb.go` (2 min)
- [ ] **2.16** Verify proto files: `ls -la pkg/proto/` (1 min)

#### Documentation
- [ ] **2.17** Update #2687 with "Kafka pipeline tested" + test output (5 min)
- [ ] **2.18** Create `KAFKA_TEST_RESULTS.md` with partition assignment + throughput (10 min)

**Success Criteria:**
- ✅ Both Kafka topics exist
- ✅ Producer publishes 10 messages without error
- ✅ Consumer reads all 10 messages in order
- ✅ Protobuf message schema compiled
- ✅ Messages distributed across 3 partitions

**Blocker Risk:** Medium (Kafka setup commonly has timing issues) | **Critical for:** Normalizers, PostgreSQL consumer

**Unblock Plan:** Have schema docker-compose pull timeout; solution = wait 30s and retry

---

### Day 3 (March 14) — GITHUB NORMALIZER
**Goal:** GitHub webhooks convert → normalized events  
**Assigned to:** Backend Engineer (Normalizer)  
**GitHub Issue:** [#2691](https://github.com/kushin77/self-hosted-runner/issues/2691)

#### Pre-work
- [ ] **3.1** Review [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) Day 3 section (15 min)
- [ ] **3.2** Download GitHub webhook sample: [github.com/actions/webhook-payload-examples](https://github.com/actions/webhook-payload-examples) (5 min)
- [ ] **3.3** Save to `test-fixtures/github-workflow-run.json` (1 min)

#### Signature Verification
- [ ] **3.4** Implement `cmd/ingestion/verify_github_signature.go` (30 min)
  - [ ] **3.4a** Extract X-Hub-Signature-256 header
  - [ ] **3.4b** Compute HMAC-SHA256(payload, secret)
  - [ ] **3.4c** Timing-safe comparison
  - [ ] **3.4d** Return error if mismatch
- [ ] **3.5** Unit test: `cmd/ingestion/verify_github_signature_test.go` (15 min)
  - [ ] **3.5a** TestVerifyGitHubSignature_Valid
  - [ ] **3.5b** TestVerifyGitHubSignature_Invalid
  - [ ] **3.5c** TestVerifyGitHubSignature_MissingHeader

#### Normalizer Implementation
- [ ] **3.6** Implement `internal/normalizer/github.go::NormalizeGitHubWorkflow()` (30 min)
  - [ ] **3.6a** Unmarshal GitHub webhook JSON
  - [ ] **3.6b** Extract run_id, status, repo, branch, commit_sha, duration_ms
  - [ ] **3.6c** Map GitHub status → discovery.Status enum
  - [ ] **3.6d** Build discovery.PipelineRun
  - [ ] **3.6e** Return discovery.NormalizedEvent
- [ ] **3.7** Implement `internal/normalizer/github.go::mapGitHubStatus()` (5 min)
  - [ ] **3.7a** GitHub "success" → discovery.Status_SUCCESS
  - [ ] **3.7b** GitHub "failure" → discovery.Status_FAILED
  - [ ] **3.7c** GitHub "in_progress" → discovery.Status_RUNNING

#### Unit Tests
- [ ] **3.8** Create `internal/normalizer/github_test.go` (40 min)
  - [ ] **3.8a** TestNormalizeGitHubWorkflow_Success (load fixture, verify output)
  - [ ] **3.8b** TestNormalizeGitHubWorkflow_InvalidJSON (error handling)
  - [ ] **3.8c** TestNormalizeGitHubWorkflow_MissingFields (partial payload)
  - [ ] **3.8d** TestNormalizeGitHubWorkflow_StatusMapping (all 5 statuses)
- [ ] **3.9** Run tests: `make test` (coverage >90% for github.go) (5 min)
- [ ] **3.10** Fix any test failures (15 min estimate)

#### Integration Test (Curl)
- [ ] **3.11** Start ingestion server: `nexus-engine$ make run` (2 min)
- [ ] **3.12** Send curl request with valid signature:
  ```bash
  PAYLOAD=$(cat test-fixtures/github-workflow-run.json)
  SECRET=$(echo 'github-secret-123' | base64)
  SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | cut -d' ' -f2)
  curl -X POST http://localhost:8080/webhook/github \
    -H "X-Hub-Signature-256: sha256=$SIGNATURE" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
  ``` (5 min)
- [ ] **3.13** Check server logs: "Published message to Kafka" (2 min)
- [ ] **3.14** Consume from Kafka: `docker exec nexus-kafka kafka-console-consumer...` (verify message received) (3 min)

#### Documentation
- [ ] **3.15** Update #2691 with "GitHub normalizer complete + tested" (5 min)
- [ ] **3.16** Create `GITHUB_NORMALIZER_TEST_RESULTS.md` (10 min)
- [ ] **3.17** Commit: `feat(normalizer): GitHub workflow normalization with signature verification` (2 min)

**Success Criteria:**
- ✅ Unit tests >90% coverage
- ✅ Real GitHub webhook payload normalizes correctly
- ✅ Signature verification prevents spoofing
- ✅ All GitHub status values map to discovery enum
- ✅ source_run_id extracted correctly (for dedup)
- ✅ Curl test returns 200 OK

**Blocker Risk:** Medium (signature verification has timing-safe edge cases) | **Critical for:** End-to-end test

---

### Day 4 (March 15) — GITLAB NORMALIZER
**Goal:** GitLab webhooks convert → normalized events  
**Assigned to:** Backend Engineer (same as Day 3 or different)  
**GitHub Issue:** [#2691](https://github.com/kushin77/self-hosted-runner/issues/2691)

#### Same Structure as Day 3
- [ ] **4.1-4.4** Pre-work (review, download sample payload) (20 min)
- [ ] **4.5-4.7** Signature verification (implement + test) (30 min)
- [ ] **4.8-4.10** Normalizer implementation (implement + test) (45 min)
- [ ] **4.11-4.14** Integration test (curl + Kafka) (15 min)
- [ ] **4.15-4.17** Documentation + commit (15 min)

**Key Differences from GitHub:**
- GitLab endpoint: `POST /webhook/gitlab`
- GitLab signature: `X-Gitlab-Token` header (simple string comparison, not HMAC)
- GitLab status field location: `pipeline.status` (not `run.status`)
- GitLab ID: `pipeline.id` (different format than GitHub run_id)

**Success Criteria:**
- ✅ Unit tests >90% coverage
- ✅ Real GitLab webhook payload normalizes correctly
- ✅ Signature verification works (X-Gitlab-Token)
- ✅ All GitLab status values map correctly
- ✅ source_run_id = pipeline_id (for dedup)

**Blocker Risk:** Low (similar to GitHub) | **Critical for:** Multi-source support

---

### Day 5 (March 16) — END-TO-END INTEGRATION TEST
**Goal:** Full pipeline working: webhook → Kafka → normalizer → PostgreSQL  
**Assigned to:** QA / Test Engineer (or backend lead)  
**GitHub Issue:** [#2692 - Phase 0 Epic](https://github.com/kushin77/self-hosted-runner/issues/2692)

#### Pre-work
- [ ] **5.1** Verify all Day 1-4 tasks complete (check GitHub issues) (5 min)
- [ ] **5.2** Review [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) Day 5 section (10 min)

#### Full Stack Start
- [ ] **5.3** Ensure PostgreSQL running (from Day 1) (1 min)
- [ ] **5.4** Ensure Kafka running (from Day 2) (1 min)
- [ ] **5.5** Start ingestion service: `make run` (2 min)

#### Test 1: GitHub Happy Path
- [ ] **5.6** Load GitHub test fixture (1 min)
- [ ] **5.7** Send curl request with valid signature (2 min)
- [ ] **5.8** Verify Kafka received event: `docker exec nexus-kafka kafka-console-consumer...` (2 min)
- [ ] **5.9** Verify PostgreSQL received event: `psql -c "SELECT * FROM pipeline_runs ORDER BY created_at DESC LIMIT 1;"` (1 min)
- [ ] **5.10** Verify fields match: source='github', status matches, duration_ms correct (2 min)

#### Test 2: GitLab Happy Path
- [ ] **5.11** Load GitLab test fixture (1 min)
- [ ] **5.12** Send curl request with valid signature (2 min)
- [ ] **5.13** Verify PostgreSQL received event (same as 5.9) (1 min)
- [ ] **5.14** Verify source='gitlab' (different from GitHub) (1 min)

#### Test 3: Idempotency
- [ ] **5.15** Send same GitHub webhook 3x (delay 2s between) (3 min)
- [ ] **5.16** Query PostgreSQL: `SELECT COUNT(*) FROM pipeline_runs WHERE source_run_id='<github-id>'` (1 min)
- [ ] **5.17** Verify count = 1 (deduplicated) (1 min)
- [ ] **5.18** Try INSERT duplicate directly: `INSERT ... (source, source_run_id) VALUES (...)` (1 min)
- [ ] **5.19** Verify UNIQUE constraint violation (expected) (1 min)

#### Test 4: Latency Measurement
- [ ] **5.20** Send webhook with curl, measure time to PostgreSQL insert (5 min)
  - Acceptable: <1 second from webhook → database queryable
  - Target: <500ms
- [ ] **5.21** Document: "Webhook received at T=0, PostgreSQL insert at T=<Xms>" (2 min)

#### Test 5: Multi-source Mixed
- [ ] **5.22** Send 10 GitHub events (spread across 5 seconds) (5 min)
- [ ] **5.23** Send 5 GitLab events (spread across 3 seconds) (3 min)
- [ ] **5.24** Query PostgreSQL: `SELECT COUNT(*), source FROM pipeline_runs GROUP BY source;` (1 min)
- [ ] **5.25** Verify: GitHub=10, GitLab=5 (no interleaving issues) (1 min)

#### Documentation
- [ ] **5.26** Update #2692 with "Week 1 complete: full pipeline working end-to-end" (5 min)
- [ ] **5.27** Create `E2E_TEST_RESULTS.md` with all test results (15 min)
- [ ] **5.28** Commit: `test(e2e): end-to-end webhook → PostgreSQL pipeline verified` (2 min)

**Success Criteria:**
- ✅ Webhook → Kafka → Database happy path works
- ✅ Idempotency verified (3x same event = 1 DB row)
- ✅ Both GitHub + GitLab events flow correctly
- ✅ Latency < 1 second
- ✅ No cross-source contamination

**Blocker Risk:** Low (all pieces should be working from Days 1-4) | **Critical for:** Moving to Week 2

---

## 📅 WEEK 2: Integration (March 19-26)

### Day 6 (March 19) — JENKINS INTEGRATION
**Goal:** Jenkins webhooks normalize → same schema  
**Assigned to:** Backend Engineer (Normalizer)  
**GitHub Issue:** [#2687](https://github.com/kushin77/self-hosted-runner/issues/2687)

#### Pre-work
- [ ] **6.1** Review Jenkins webhook format (10 min)
- [ ] **6.2** Save sample Jenkins payload to `test-fixtures/jenkins-webhook.json` (2 min)

#### Implementation
- [ ] **6.3** Implement `internal/normalizer/jenkins.go` (similar to Day 3-4) (40 min)
- [ ] **6.4** Implement Jenkins signature verification (if needed) (10 min)
- [ ] **6.5** Create unit tests (20 min)
- [ ] **6.6** Pass: `make test` (5 min)
- [ ] **6.7** Integration test: curl → Kafka → PostgreSQL (10 min)

#### Documentation
- [ ] **6.8** Update #2687 with Jenkins integration complete (5 min)

**Success Criteria:**
- ✅ Jenkins payloads convert to discovery.PipelineRun
- ✅ Unit tests pass
- ✅ Real Jenkins webhook normalizes correctly

---

### Day 7 (March 20) — PORTAL API EXTENSIONS
**Goal:** Portal can query discovery data  
**Assigned to:** Backend Engineer (API) + Frontend Engineer (integration)  
**GitHub Issue:** [#2690](https://github.com/kushin77/self-hosted-runner/issues/2690)

#### Pre-work
- [ ] **7.1** Review Portal structure (portal/src/) (15 min)
- [ ] **7.2** Review PostgreSQL connection pattern (10 min)

#### Backend Implementation
- [ ] **7.3** Create `portal/src/routes/discovery.ts` (50 min)
  - [ ] **7.3a** GET /api/v1/discovery/runs endpoint
  - [ ] **7.3b** GET /api/v1/discovery/stats endpoint
  - [ ] **7.3c** Query PostgreSQL (with RLS tenant filtering)
  - [ ] **7.3d** Add filtering: source, status, limit, since, repo
  - [ ] **7.3e** Response schema with metadata + pagination
- [ ] **7.4** Implement RLS enforcement in API layer (10 min)
  - [ ] **7.4a** Extract tenant_id from JWT token
  - [ ] **7.4b** Set `SET app.current_tenant_id = $1` before each query
- [ ] **7.5** Create unit tests: `portal/src/routes/discovery.test.ts` (30 min)
- [ ] **7.6** Run tests: `npm test` (5 min)

#### Frontend Integration
- [ ] **7.7** Create `portal/src/components/DiscoveryView.tsx` (60 min)
  - [ ] **7.7a** List runs with columns: source, repo, status, timestamp, duration
  - [ ] **7.7b** Filter controls: source dropdown, status dropdown
  - [ ] **7.7c** Real-time updates via WebSocket (if possible, else polling)
  - [ ] **7.7d** Click run → show details
- [ ] **7.8** Add route: `portal/src/App.tsx` (5 min)
- [ ] **7.9** Style with Tailwind CSS (20 min)

#### Testing
- [ ] **7.10** Manual test: Portal loads, shows real pipeline runs (10 min)
- [ ] **7.11** Test filters: GitHub-only, failed-only, last 10 runs (5 min)
- [ ] **7.12** Test RLS: Creates 2nd tenant, verifies data isolation (10 min)

#### Documentation
- [ ] **7.13** Update #2690 with "Portal API endpoints live" (5 min)
- [ ] **7.14** Create `PORTAL_API_SPEC.md` with endpoint docs (15 min)

**Success Criteria:**
- ✅ Portal API returns database records
- ✅ RLS enforced (tenant1 can't see tenant2's runs)
- ✅ Filters work correctly
- ✅ Sorting by timestamp works
- ✅ Frontend displays real data

**Blocker Risk:** Medium (coordinates backend + frontend) | **Critical for:** Dashboard visibility

---

### Day 8 (March 21) — SLACK BOT FOUNDATION
**Goal:** Slack bot listens to /nexus commands, returns status  
**Assigned to:** Full-Stack Engineer  
**GitHub Issue:** [#2689](https://github.com/kushin77/self-hosted-runner/issues/2689)

#### Pre-work
- [ ] **8.1** Create Slack app at https://api.slack.com/apps (10 min)
- [ ] **8.2** Set permissions: `commands`, `chat:write` (5 min)
- [ ] **8.3** Install app to workspace (2 min)
- [ ] **8.4** Copy `SLACK_BOT_TOKEN` to `.env` (1 min)
- [ ] **8.5** Create command: `/nexus` (5 min)
  - Endpoint: `http://localhost:8080/slack/commands/nexus`
  - Callback ID: `slash_nexus_status`

#### Backend Implementation
- [ ] **8.6** Create `internal/slack/handler.go` (40 min)
  ```go
  func HandleStatusCommand(ctx context.Context, payload *slack.SlashCommandsPayload) error {
    // 1. Query PostgreSQL for last 10 runs
    // 2. Count by status
    // 3. Format Slack message block
    // 4. Send via Slack API
  }
  ```
- [ ] **8.7** Implement Slack signature verification (15 min)
  - X-Slack-Request-Timestamp
  - X-Slack-Signature
- [ ] **8.8** Add HTTP endpoint: `POST /slack/commands/status` in main.go (5 min)
- [ ] **8.9** Test: `curl -X POST http://localhost:8080/slack/commands/status ...` (5 min)

#### Unit Tests
- [ ] **8.10** Create `internal/slack/handler_test.go` (20 min)
  - [ ] **8.10a** TestHandleStatusCommand_Success
  - [ ] **8.10b** TestHandleStatusCommand_NoRuns
  - [ ] **8.10c** TestVerifySlackSignature_Valid
  - [ ] **8.10d** TestVerifySlackSignature_Invalid

#### Manual Testing
- [ ] **8.11** In Slack workspace, type `/nexus status` (2 min)
- [ ] **8.12** Verify response: "✅ 45 passed | ❌ 3 failed | ⏳ 2 running" (2 min)
- [ ] **8.13** Try multiple times, verify response accurate (5 min)

#### Documentation
- [ ] **8.14** Update #2689 with "Slack bot foundation working" (5 min)
- [ ] **8.15** Create `SLACK_BOT_SETUP.md` with token setup instructions (10 min)

**Success Criteria:**
- ✅ /nexus status returns stats in Slack
- ✅ Signature verification prevents spoofing
- ✅ <3 second response time
- ✅ Accurate data from PostgreSQL

---

### Days 9-10 (March 22-23) — MONITORING & OBSERVABILITY
**Goal:** Instrumentation complete, dashboards working, alerts configured  
**Assigned to:** DevOps / SRE  
**GitHub Issue:** [#2692 - Phase 0 Epic](https://github.com/kushin77/self-hosted-runner/issues/2692)

#### Prometheus Metrics (Day 9 AM)
- [ ] **9.1** Add Prometheus client to go.mod (2 min)
- [ ] **9.2** Add metrics middleware to HTTP handlers (20 min)
  - [ ] **9.2a** `nexus_webhooks_received` (counter)
  - [ ] **9.2b** `nexus_events_normalized` (counter)
  - [ ] **9.2c** `nexus_events_stored` (counter)
  - [ ] **9.2d** `nexus_normalization_latency_ms` (histogram)
- [ ] **9.3** Expose Prometheus endpoint: `GET /metrics` (5 min)
- [ ] **9.4** Test: `curl http://localhost:8080/metrics` (2 min)

#### Logging (Day 9 PM)
- [ ] **9.5** Replace standard logging with Zap (20 min)
  - [ ] **9.5a** Structured logging for critical paths
  - [ ] **9.5b** JSON output for log aggregation
- [ ] **9.6** Add logs to all error paths (15 min)
- [ ] **9.7** Test: `docker logs nexus-ingestion | jq` (2 min)

#### Grafana Dashboard (Day 10 AM)
- [ ] **9.8** Deploy Grafana (docker-compose or managed) (10 min)
- [ ] **9.9** Configure Prometheus data source (5 min)
- [ ] **9.10** Create dashboard: Real-time ingestion (30 min)
  - Graphs: events/min by source, success/failure rate
- [ ] **9.11** Create dashboard: System health (20 min)
  - Graphs: Kafka lag, DB query latency, error rates
- [ ] **9.12** Test dashboards with live data (10 min)

#### Alerting (Day 10 PM)
- [ ] **9.13** Set up alerting tool (PagerDuty, Slack, or builtin) (15 min)
- [ ] **9.14** Create alerts:
  - [ ] **9.14a** Kafka lag > 10k messages
  - [ ] **9.14b** Normalization latency > 5s
  - [ ] **9.14c** Error rate > 1%
- [ ] **9.15** Test alert: trigger artificially (5 min)

#### Documentation
- [ ] **9.16** Create `MONITORING_SETUP.md` (15 min)
- [ ] **9.17** Create `GRAFANA_DASHBOARD_EXPORT.json` (backup) (2 min)

**Success Criteria:**
- ✅ All critical paths instrumented
- ✅ Grafana dashboard shows real data
- ✅ Alerts configured + tested
- ✅ Logs streamable to central service

---

## 📅 WEEK 3: Testing & Documentation (March 26-April 2)

### Days 11-12 (March 26-27) — END-TO-END REAL-WORLD TESTING
**Goal:** Real-world workflow: push → webhook → discovery visible  
**Assigned to:** QA Lead  
**GitHub Issue:** [#2692 - Phase 0 Epic](https://github.com/kushin77/self-hosted-runner/issues/2692)

#### Setup (Day 11 AM)
- [ ] **11.1** Create test GitHub repo: `test-nexus-discovery` (5 min)
- [ ] **11.2** Add GitHub Actions workflow (deliberately flaky) (10 min)
  ```yaml
  name: Test Workflow
  on: [push]
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - run: |
            if [ $RANDOM -gt 20000 ]; then exit 0; else exit 1; fi
  ```
- [ ] **11.3** Configure webhook: GitHub repo → https://your-instance:8080/webhook/github (5 min)
- [ ] **11.4** Add webhook secret to PostgreSQL (2 min)
- [ ] **11.5** Start NEXUS services: `make up` (2 min)

#### Testing (Day 11 PM - 12 AM)
- [ ] **11.6** Perform 10 pushes to test repo (trigger 10 runs) (30 min)
  ```bash
  for i in {1..10}; do
    echo "push $i" >> README.md
    git add README.md
    git commit -m "Test push $i"
    git push
  done
  ```
- [ ] **11.7** Within 30s of each webhook, verify PostgreSQL has entry (check manually) (30 min)
- [ ] **11.8** View Portal dashboard: /discovery/runs (should show all 10) (5 min)
- [ ] **11.9** Test Portal filters:
  - [ ] **11.9a** Filter by status=failed (should show ~5)
  - [ ] **11.9b** Filter by repo=test-nexus-discovery (should show 10)
  - [ ] **11.9c** Sort by duration (verify oldest last)
- [ ] **11.10** Test Slack bot: `/nexus status` (should show "10 total, 5 passed, 5 failed") (2 min)
- [ ] **11.11** Test webhook retry: GitHub resends webhook → verify deduped (no duplicate row) (5 min)

#### Load Testing (Day 12)
- [ ] **12.1** Create script to send 100 webhook payloads in parallel (30 min)
  ```bash
  # Send 100 events simultaneously
  for i in {1..100}; do
    curl -X POST http://localhost:8080/webhook/github ... &
  done
  wait
  ```
- [ ] **12.2** Measure: Total time to process all 100 (target: <10s) (5 min)
- [ ] **12.3** Query PostgreSQL: Verify 100 rows inserted (1 min)
- [ ] **12.4** Verify deduplication: Re-send same 100 → still 100 rows, not 200 (5 min)
- [ ] **12.5** Check monitoring: Kafka lag, latency, error rate (5 min)

#### Stress Testing
- [ ] **12.6** Send 1000 events over 1 hour (gradual ramp) (60 min background)
- [ ] **12.7** Monitor system: CPU, memory, connection pools (observe behavior) (60 min)
- [ ] **12.8** Verify Portal still responsive (search, filters) (5 min)
- [ ] **12.9** Document findings: "System comfortable with 10 events/sec, no degrade" (10 min)

#### Documentation
- [ ] **12.10** Create `E2E_REAL_WORLD_TEST_RESULTS.md` (15 min)
- [ ] **12.11** Create `LOAD_TEST_RESULTS.md` (15 min)
- [ ] **12.12** Update #2692 with "Real-world testing complete, all metrics green" (5 min)

**Success Criteria:**
- ✅ Real workflow visible in Portal <1s after webhook
- ✅ Real Slack alerts working
- ✅ Deduplication proved
- ✅ Load test: 100 events in <10s
- ✅ System stable under 1000 event/hour load

---

### Day 13 (March 28) — OPERATIONAL READINESS
**Goal:** Deployment guide, runbooks, team trained  
**Assigned to:** Tech Lead + DevOps  

#### Documentation
- [ ] **13.1** Update [nexus-engine/README.md](nexus-engine/README.md) with real test results (20 min)
- [ ] **13.2** Create deployment guide (docker-compose → Kubernetes) (40 min)
- [ ] **13.3** Document all Slack commands + usage (10 min)
- [ ] **13.4** Document all Portal API endpoints (10 min)
- [ ] **13.5** Create troubleshooting guide (15 min)
  - How to debug: check logs, metrics, database
  - Common issues: Kafka lag, signature mismatch, RLS blocking

#### Team Training (Day 13 PM)
- [ ] **13.6** Record 15-min video walkthrough (screen recording) (30 min)
- [ ] **13.7** Conduct team training session (30 min)
  - Explain architecture
  - Demo Portal + Slack bot
  - Q&A
- [ ] **13.8** Document Q&A answers (10 min)

#### Final Checklist
- [ ] **13.9** All tests passing: `make test` (2 min)
- [ ] **13.10** All GitHub issues ready to close (review) (10 min)
- [ ] **13.11** Code review completed (all files reviewed) (20 min)

**Success Criteria:**
- ✅ All documentation complete
- ✅ Team trained + confident
- ✅ Deployment runbook executable
- ✅ Video training recorded

---

### Day 14 (April 2) — PHASE 0 COMPLETION & HANDOFF
**Goal:** Close all issues, prepare for Phase 1  
**Assigned to:** Project Manager + Tech Lead  

#### Final Verification
- [ ] **14.1** Run complete test suite one more time (10 min)
  - [ ] `make test` (unit tests)
  - [ ] `make test-integration` (integration tests)
  - [ ] `make test-e2e` (end-to-end)
- [ ] **14.2** Verify all metrics in Grafana (5 min)
- [ ] **14.3** Verify Portal shows real data (5 min)
- [ ] **14.4** Verify Slack bot working (5 min)

#### GitHub Issues
- [ ] **14.5** Close #2687 (Kafka Ingestion) (1 min)
- [ ] **14.6** Close #2688 (PostgreSQL Schema) (1 min)
- [ ] **14.7** Close #2689 (Slack Bot) (1 min)
- [ ] **14.8** Close #2690 (Portal API) (1 min)
- [ ] **14.9** Close #2691 (Normalizer) (1 min)
- [ ] **14.10** Update #2692 (Epic): "Phase 0 COMPLETE ✅" (5 min)

#### Final Documentation
- [ ] **14.11** Create `PHASE_0_COMPLETION_SUMMARY.md` (20 min)
  - Lines of code written
  - Tests created
  - Issues closed
  - Team feedback
- [ ] **14.12** Create branch for archive: `git tag phase0-complete-2026-04-02` (2 min)

#### Handoff to Phase 1
- [ ] **14.13** Create GitHub issue #XXXX: Phase 1 — Studio Dashboard (30 min)
  - Requirements
  - Rough timeline
  - New team members needed
- [ ] **14.14** Schedule Phase 1 kickoff meeting (1 min)

#### Celebration 🎉
- [ ] **14.15** Shipping celebration! (unlimited)

**Success Criteria:**
- ✅ All 6 GitHub issues closed
- ✅ All tests green
- ✅ Complete summary document
- ✅ Phase 1 issue created

---

## 📊 SUMMARY & TRACKING

### Task Counts by Category

| Category | Total | Completed | % |
|----------|-------|-----------|---|
| **Setup & Config** | 8 | 0 | 0% |
| **Implementation** | 18 | 0 | 0% |
| **Testing** | 12 | 0 | 0% |
| **Documentation** | 4 | 0 | 0% |
| **TOTAL** | **42** | **0** | **0%** |

### Critical Path

1. **Day 1:** PostgreSQL schema → ✅ Day 1 complete
2. **Day 2:** Kafka topics → ✅ Day 2 complete
3. **Day 3:** GitHub normalizer → ✅ Day 3 complete
4. **Day 4:** GitLab normalizer → ✅ Day 4 complete
5. **Day 5:** Integration test → ✅ Day 5 complete
6. **Days 6-14:** Parallel tasks + testing + docs → ✅ Phase 0 complete

### Risk Management

| Task | Blockers | Mitigation |
|------|----------|-----------|
| Day 1 (Database) | None (independent) | Minimal risk |
| Day 2 (Kafka) | Depends on Day 1 | Have Day 1 doc ready |
| Day 3 (GitHub) | Requires Kafka (Day 2) | Test signature verification early |
| Day 5 (E2E) | Requires Days 1-4 | Have fallback test data |
| Days 6-10 | Parallel, no blockers | Assign sufficient engineers |
| Days 11-12 | Real GitHub access | Use test repo not production |

### Weekly Goals

| Week | MVP | Success Criteria |
|------|-----|------------------|
| **1** | Foundation | PostgreSQL + Kafka + normalizers working |
| **2** | Integration | Portal API + Slack bot + monitoring |
| **3** | Validation | Real-world testing + documentation |

---

## 🎯 EXECUTION NOTES

**For Project Manager:**
- Track progress daily (use GitHub issues as source of truth)
- Unblock Day 1 (database) within 2 hours of start
- Daily 15-min standup to catch blockers
- Celebrate daily wins (even small ones)

**For Team:**
- Read runbook for your assigned day before starting
- Commit after every successful test
- Document blockers immediately in GitHub issue comments
- Help teammates debug (share knowledge)

**For Tech Lead:**
- Verify test coverage >85% daily
- Do code review same day (don't let commits pile up)
- Ensure documentation stays in sync with code
- Call out technical debt immediately

---

**Ready to execute? Start with Week 1, Day 1. Good luck! 🚀**

