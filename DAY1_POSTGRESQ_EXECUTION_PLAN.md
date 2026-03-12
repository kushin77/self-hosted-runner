# 🚀 DAY 1 EXECUTION PLAN — PostgreSQL Schema Setup
**Date:** March 12, 2026  
**Target Completion:** TODAY (EOD March 12)  
**Owner:** Database Engineer / Full-Stack Engineer  
**GitHub Issue:** [#2688 - PostgreSQL + ClickHouse Schema](https://github.com/kushin77/self-hosted-runner/issues/2688)  
**Blocker Impact:** CRITICAL — Blocks all other Phase 0 tasks

---

## 📋 TASK CHECKLIST

**Complete in this order. Each task ~5-10 minutes.**

### Task 1.1 ✅ Start PostgreSQL Container
```bash
cd /home/akushnir/self-hosted-runner/nexus-engine
docker-compose up -d postgres
```

**Expected Output:**
```
Creating nexus-engine_postgres_1 ... done
```

**Verification:**
```bash
docker-compose ps postgres
# Should show: "Up X seconds"
```

**If Port Conflict:**
```bash
# Check what's using port 5432
lsof -i :5432
# OR kill existing container
docker-compose down postgres
docker-compose up -d postgres
```

**Estimated Time:** 30 seconds + 30 seconds startup

---

### Task 1.2 ✅ Verify PostgreSQL Connection
```bash
# Test connection with psql
psql -h localhost -U postgres -c "SELECT version();"
```

**Expected Output:**
```
PostgreSQL 15.2 (Debian 15.2-1.pgdg120+1) on x86_64-pc-linux-gnu, ...
```

**If Connection Fails:**
- PostgreSQL might still be starting → wait 10 more seconds, retry
- Port might not be exposed → check docker-compose.yml `ports: ["5432:5432"]`
- Wrong password → check .env file for `POSTGRES_PASSWORD`

**Estimated Time:** 10-20 seconds (including startup wait)

---

### Task 1.3 ✅ Create nexus Database
```bash
psql -h localhost -U postgres -c "CREATE DATABASE nexus;"
```

**Expected Output:**
```
CREATE DATABASE
```

**If Already Exists:**
```
ERROR: database "nexus" already exists
```
→ That's OK, run: `psql -h localhost -U postgres -d nexus -c "SELECT COUNT(*) FROM information_schema.tables;"`  
→ If tables > 0, schema already applied (skip Tasks 1.4-1.6)

**Estimated Time:** 5 seconds

---

### Task 1.4 ✅ Apply PostgreSQL Schema (CRITICAL)
```bash
# Navigate to migration file
cd /home/akushnir/self-hosted-runner/nexus-engine

# Apply schema
psql -h localhost -U postgres -d nexus < database/migrations/001_init_schema.sql
```

**Expected Output:**
```
CREATE EXTENSION
CREATE TABLE
CREATE POLICY
CREATE INDEX
CREATE TABLE
CREATE POLICY
CREATE INDEX
... (15-20 lines of SQL commands)
```

**If File Not Found:**
```
psql: error: could not open file "database/migrations/001_init_schema.sql": No such file or directory
```
→ Check if file exists: `ls -la database/migrations/001_init_schema.sql`  
→ If missing, pull latest from git: `git pull origin main`

**Estimated Time:** 10 seconds

---

### Task 1.5 ✅ Verify Tables Created
```bash
psql -h localhost -U postgres -d nexus -c "\dt"
```

**Expected Output:**
```
                List of relations
 Schema |         Name          | Type  | Owner
--------+-----------------------+-------+----------
 public | events                | table | postgres
 public | pipeline_runs         | table | postgres
 public | tenants               | table | postgres
 public | webhooks              | table | postgres
(4 rows)
```

**If Tables Missing:**
→ Re-run Task 1.4 (schema application) and check for errors

**Estimated Time:** 5 seconds

---

### Task 1.6 ✅ Verify Unique Index (Deduplication Key)
```bash
psql -h localhost -U postgres -d nexus -c "\d pipeline_runs"
```

**Look for this line in output:**
```
Indexes:
    "pipeline_runs_source_source_run_id_key" UNIQUE CONSTRAINT, btree (source, source_run_id)
```

**This proves:** Insert 3x same (source, source_run_id) → only 1 row in database (idempotent)

**Estimated Time:** 5 seconds

---

## 🔐 Task 1.7 ✅ Test Row-Level Security (RLS) — Multi-Tenant Isolation

**This is CRITICAL for security. Must verify before moving to Day 2.**

### Step 1: Insert Test Tenant
```sql
psql -h localhost -U postgres -d nexus << 'EOF'
INSERT INTO tenants (name) VALUES ('Tenant-A');
INSERT INTO tenants (name) VALUES ('Tenant-B');
SELECT * FROM tenants;  -- Should show both
EOF
```

**Expected Output:**
```
 id |   name    |       created_at
----+-----------+---------------------
  1 | Tenant-A  | 2026-03-12 15:30:00
  2 | Tenant-B  | 2026-03-12 15:30:01
(2 rows)
```

### Step 2: Insert Test Data as Tenant-A
```sql
psql -h localhost -U postgres -d nexus << 'EOF'
-- Set session to Tenant-A (id=1)
SET app.current_tenant_id = '1';

-- Insert a pipeline run for Tenant-A
INSERT INTO pipeline_runs (tenant_id, source, source_run_id, repo, branch, status)
VALUES (1, 'github', 'run-12345', 'org/repo-a', 'main', 'success');

-- Query should return data
SELECT source, source_run_id, repo FROM pipeline_runs;
EOF
```

**Expected Output:**
```
 source | source_run_id |    repo
--------+---------------+----------
 github |   run-12345   | org/repo-a
(1 row)
```

### Step 3: Verify Tenant-B CANNOT See Tenant-A's Data (RLS Working!)
```sql
psql -h localhost -U postgres -d nexus << 'EOF'
-- Switch to Tenant-B session
SET app.current_tenant_id = '2';

-- Query should return NOTHING (RLS blocks cross-tenant reads)
SELECT source, source_run_id, repo FROM pipeline_runs;
EOF
```

**Expected Output:**
```
 source | source_run_id | repo
--------+---------------+------
(0 rows)  -- EMPTY! That's correct!
```

**If You See Data:**
```
❌ FAILURE: RLS policy not working, Tenant-B can see Tenant-A data
→ Check: ALTER TABLE pipeline_runs ENABLE ROW LEVEL SECURITY;
→ Check: ALTER ENABLE POLICY ... ON pipeline_runs;
→ Re-run schema application
```

**Estimated Time:** 1-2 minutes

---

## ✨ Task 1.8 ✅ Test Idempotency (Deduplication)

**Verify:** Inserting the same (source, source_run_id) 3x yields only 1 row

```sql
psql -h localhost -U postgres -d nexus << 'EOF'
-- Reset to clean state
SET app.current_tenant_id = '1';
DELETE FROM pipeline_runs WHERE source = 'github' AND source_run_id = 'idempotent-test-1';

-- Insert 1st time
INSERT INTO pipeline_runs (tenant_id, source, source_run_id, repo, branch, status)
VALUES (1, 'github', 'idempotent-test-1', 'org/repo-test', 'main', 'success');

-- Insert 2nd time (same values)
INSERT INTO pipeline_runs (tenant_id, source, source_run_id, repo, branch, status)
VALUES (1, 'github', 'idempotent-test-1', 'org/repo-test', 'main', 'success');

-- Insert 3rd time (same values)
INSERT INTO pipeline_runs (tenant_id, source, source_run_id, repo, branch, status)
VALUES (1, 'github', 'idempotent-test-1', 'org/repo-test', 'main', 'success');

-- Count rows (should be exactly 1)
SELECT COUNT(*) FROM pipeline_runs WHERE source_run_id = 'idempotent-test-1';
EOF
```

**Expected Output:**
```
ERROR:  duplicate key value violates unique constraint "pipeline_runs_source_source_run_id_key"
DETAIL:  Key (source, source_run_id)=(github, idempotent-test-1) already exists.
```

**Then the 2nd and 3rd inserts fail gracefully** (application handles ON CONFLICT IGNORE):

```sql
-- Insert with ON CONFLICT DO NOTHING (idempotent)
INSERT INTO pipeline_runs (tenant_id, source, source_run_id, repo, branch, status)
VALUES (1, 'github', 'idempotent-test-1', 'org/repo-test', 'main', 'success')
ON CONFLICT (source, source_run_id) DO NOTHING;

SELECT COUNT(*) FROM pipeline_runs WHERE source_run_id = 'idempotent-test-1';
```

**Expected Output:**
```
 count
-------
     1
(1 row)
```

✅ **Success!** 3x inserts → only 1 row in database (idempotent)

**Estimated Time:** 2 minutes

---

## 📊 Task 1.9 ✅ Create Test Data for Next Steps

```sql
psql -h localhost -U postgres -d nexus << 'EOF'
-- Ensure we have test data for Day 2 (Kafka consumers)
SET app.current_tenant_id = '1';

-- Insert a few test runs
INSERT INTO pipeline_runs (tenant_id, source, source_run_id, repo, branch, commit_sha, status, duration_ms)
VALUES 
  (1, 'github', 'gha-run-001', 'myorg/myrepo', 'main', 'abc123def456', 'success', 280000),
  (1, 'github', 'gha-run-002', 'myorg/myrepo', 'develop', 'xyz789uvw012', 'failed', 150000),
  (1, 'gitlab', 'gitlab-pipe-001', 'myorg/another-repo', 'main', 'pqr345stu678', 'success', 320000);

SELECT COUNT(*) FROM pipeline_runs;
EOF
```

**Expected Output:**
```
 count
-------
     3
(3 rows)
```

**Estimated Time:** 5 seconds

---

## 📝 Task 1.10 ✅ Document Results

**Create file:** `DAY1_POSTGRES_TEST_RESULTS.md`

**Copy-paste this template and fill in your results:**

```markdown
# Day 1 PostgreSQL Test Results

**Date:** March 12, 2026  
**Tester:** [Your Name]  
**Status:** ✅ PASSED / ❌ FAILED

## Results Summary

| Task | Description | Status | Duration |
|------|-------------|--------|----------|
| 1.1  | Start PostgreSQL | ✅ | 1 min |
| 1.2  | Verify Connection | ✅ | 30s |
| 1.3  | Create Database | ✅ | 5s |
| 1.4  | Apply Schema | ✅ | 10s |
| 1.5  | Verify Tables | ✅ | 5s |
| 1.6  | Verify Unique Index | ✅ | 5s |
| 1.7  | Test RLS Multi-Tenant | ✅ | 2 min |
| 1.8  | Test Idempotency | ✅ | 2 min |
| 1.9  | Create Test Data | ✅ | 10s |

## Test Evidence

### Connection
```
psql -h localhost -U postgres -d nexus -c "SELECT version();"
PostgreSQL 15.2 (Debian 15.2-1.pgdg120+1) on x86_64-pc-linux-gnu, ...
```

### Tables Created
```
\dt
                List of relations
 Schema |         Name          | Type  | Owner
--------+-----------------------+-------+----------
 public | tenants               | table | postgres
 public | pipeline_runs         | table | postgres
 public | events                | table | postgres
 public | webhooks              | table | postgres
(4 rows)
```

### RLS Verified
```
-- Tenant-A insert: 1 row returned ✅
-- Tenant-B query: 0 rows (isolated) ✅
```

### Idempotency Verified
```
-- 3x same insert: 1 row in database ✅
-- UNIQUE(source, source_run_id) enforced ✅
```

## Conclusion
✅ **PostgreSQL schema ready for Day 2 Kafka integration**

PostgreSQL is operational with:
- 4 tables created (tenants, pipeline_runs, events, webhooks)
- Row-Level Security enforced (multi-tenant isolation verified)
- Unique index on (source, source_run_id) for deduplication
- Sample data loaded for testing
```

**Save this file to workspace root.**

**Estimated Time:** 5 minutes (writing)

---

## ✅ DONE! Update GitHub Issue

### Task 1.11 ✅ Update GitHub Issue #2688

Post comment in [#2688](https://github.com/kushin77/self-hosted-runner/issues/2688):

```markdown
## ✅ Day 1 Complete — PostgreSQL Schema Ready!

**Date:** March 12, 2026  
**Status:** 🟢 PASSED ALL TESTS

### Test Results
✅ PostgreSQL running on localhost:5432
✅ Database created: "nexus"
✅ 4 tables created (tenants, pipeline_runs, events, webhooks)
✅ Unique index on (source, source_run_id) enforced
✅ Row-Level Security policies active
✅ RLS multi-tenant isolation verified (Tenant-A isolated from Tenant-B)
✅ Idempotency proven (3x same insert = 1 row)
✅ Sample test data loaded

**Database ready for Day 2 (Kafka integration) ✅**

See: [DAY1_POSTGRES_TEST_RESULTS.md](DAY1_POSTGRES_TEST_RESULTS.md) for detailed test evidence.
```

**Estimated Time:** 1 minute

---

## ⏱️ TOTAL ESTIMATED TIME: 15-20 MINUTES

- Tasks 1.1-1.6: ~10 minutes
- Tasks 1.7-1.8: ~5 minutes  
- Tasks 1.9-1.11: ~10 minutes

**Total:** 25 minutes for full verification + documentation

---

## 🚀 NEXT STEPS (For Tomorrow - March 13)

Once this is complete:

1. ✅ **Day 1 complete** — PostgreSQL ready
2. → **Day 2 starts:** GitHub issue #2687 (Kafka setup)
3. → Kafka topics creation
4. → Producer/consumer testing
5. → Protocol buffers compilation

**See:** [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md#day-2-march-13--kafka-setup) for Day 2 plan

---

## 🆘 BLOCKERS? QUESTIONS?

- **Connection issues?** Check docker logs: `docker logs nexus-engine_postgres_1`
- **Schema errors?** Verify file exists: `cat database/migrations/001_init_schema.sql`
- **RLS not working?** Ensure `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` in schema
- **Still stuck?** Create comment in issue #2688 with error message + we'll debug together

---

**Let's ship Phase 0. 🚀**
