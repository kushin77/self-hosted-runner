# DAY 1: POSTGRESQL FOUNDATION — EXECUTION PLAN
**Date**: March 12, 2026  
**Duration**: 45 minutes  
**Owner**: Database Operator  
**Status**: ✅ Ready for Execution

---

## PRE-EXECUTION CHECKLIST (5 minutes)

Before starting, verify:

- [ ] You have read [FINAL_EXECUTION_SIGN_OFF_20260312.md](FINAL_EXECUTION_SIGN_OFF_20260312.md)
- [ ] All 7 critical assumptions are met in your environment
- [ ] You have SSH/terminal access to the deployment machine
- [ ] Kubernetes is NOT required for Day 1 (it's database only)
- [ ] Docker OR native PostgreSQL installation is available
- [ ] Git repository is up-to-date: `git pull origin main`
- [ ] Logs directory exists: `mkdir -p logs`

---

## WHAT THIS DOES

**Scope**: Deploy a production-ready PostgreSQL database with:
- Complete schema (8 migrations)
- Row-level security (RLS) on github_repos table
- Credential storage in Google Secret Manager (GSM)
- Idempotent initialization (safe to re-run)

**Success Indicator**: Database running on localhost:5432, all migrations applied, RLS policies active.

---

## STEP-BY-STEP EXECUTION

### Step 1: Start the Script (2 minutes)

```bash
cd /home/akushnir/self-hosted-runner

# Run the deployment script and log output
bash infra/scripts/deploy-postgres.sh 2>&1 | tee logs/day1-execution.log

# In another terminal, monitor progress
tail -f logs/day1-execution.log
```

**What's Happening**:
1. Script checks prerequisites (docker/psql availability)
2. Pulls PostgreSQL image (if using Docker)
3. Starts PostgreSQL service
4. Waits for database to be ready (30-second healthcheck retry loop)
5. Creates `nexus_engine` database
6. Applies 8 migrations in sequence:
   - 001: base schema (users, repos, metadata)
   - 002: github_repos table
   - 003: RLS policies
   - 004: indexes for performance
   - 005: audit triggers
   - 006: secrets table
   - 007: job queue
   - 008: compliance tracking

---

### Step 2: Monitor the Output (30-40 minutes)

Watch the logs for:

```
✅ [1/8] Migration 001_base_schema.sql ... OK
✅ [2/8] Migration 002_github_repos.sql ... OK
✅ [3/8] Migration 003_rls_policies.sql ... OK
...
✅ Migration Completed: All 8 migrations applied successfully
✅ RLS Policies Enabled on github_repos table
✅ Health Check: PostgreSQL responding to queries
✅ Credential Storage: `postgres-password` stored in Google Secret Manager (GSM). Do NOT paste passwords into files; use GSM as the single source-of-truth.
```

**If you see errors**, go to "Troubleshooting" section below.

---

### Step 3: Verify Success (5 minutes)

After the script completes, run verification commands:

```bash
# 1. Connect to database and check schema
psql -h localhost -U postgres -d nexus_engine -c \
  "SELECT table_name FROM information_schema.tables WHERE table_schema='public';"

# Should list: github_repos, users, audit_logs, job_queue, etc.

# 2. Verify RLS policies exist
psql -h localhost -U postgres -d nexus_engine -c \
  "SELECT policyname, tablename FROM pg_policies WHERE tablename='github_repos';"

# Should show: enable-read-based-github-org, enable-update-owned-repos

# 3. Check migration history
psql -h localhost -U postgres -d nexus_engine -c \
  "SELECT id, name, installed_on FROM public.db_version ORDER BY id;"

# Should show 8 rows with all migrations installed

# 4. Test a simple query
psql -h localhost -U postgres -d nexus_engine -c \
  "SELECT COUNT(*) FROM github_repos;"

# Should return: count = 0 (empty, as expected)
```

**All checks pass?** ✅ Day 1 is COMPLETE. Proceed to Day 2.

---

## TROUBLESHOOTING

### Error: "Connection refused" (localhost:5432)

**Cause**: PostgreSQL not running or not listening

**Fix**:
```bash
# If using Docker, check container status
docker ps | grep postgres
docker logs postgres

# If using native PostgreSQL
systemctl status postgresql
journalctl -u postgresql -n 50

# Restart if needed
docker restart postgres  # or
systemctl restart postgresql
```

### Error: "Database already exists"

**Cause**: Script ran before and created the database

**Fix** (SAFE):
```bash
# This is idempotent - just re-run the script:
bash infra/scripts/deploy-postgres.sh

# It will skip already-applied migrations
```

### Error: "Migration XXX failed"

**Cause**: Schema conflict or SQL syntax error

**Fix**:
```bash
# 1. Check the detailed error
cat logs/day1-execution.log | grep -A 5 "ERROR"

# 2. Identify which migration failed (e.g., 003)

# 3. Manually inspect the migration file
cat infra/migrations/003_rls_policies.sql

# 4. If critical, document the error and contact DBA team
```

### Error: "GSM secret not found" (postgres-password)

**Cause**: Google Secret Manager credential not accessible

**Fix**:
```bash
# Verify GCP credentials
gcloud auth list
gcloud config get-value project

# Create the secret if missing (ADMIN ACTION ONLY)
gcloud secrets create postgres-password \
  --replication-policy="automatic" \
  --data-file=- <<< "your-password-here"

# Then re-run Day 1 script
```

### Port 5432 Already in Use

**Cause**: PostgreSQL already running on this port

**Fix**:
```bash
# Option 1: Use the existing PostgreSQL (if it's the right one)
# Skip the deployment script, just verify with:
psql -h localhost -U postgres -d nexus_engine

# Option 2: Stop the running instance and restart
docker stop postgres  # or: systemctl stop postgresql
# Wait 5 seconds, then re-run Day 1 script

# Option 3: Use a different port (advanced)
# Edit the script and set: POSTGRES_PORT=5433
```

---

## WHAT'S NEXT

After verification succeeds:

1. **Checkpoint**: Day 1 Complete ✅
2. **Notify**: Day 2 can now start
3. **Handoff**: Move to [DAY2_KAFKA_PROTOS_CHECKLIST.md](DAY2_KAFKA_PROTOS_CHECKLIST.md)
4. **Command**: `bash nexus-engine/scripts/day2_kafka_protos.sh`

---

## REFERENCE INFORMATION

### Database Schema Overview

```
Users (optional)
  ├─ id (UUID)
  ├─ email
  └─ created_at

GitHub Repos (primary)
  ├─ id (UUID)
  ├─ owner (string, RLS-protected)
  ├─ repo (string)
  ├─ topics (JSON array)
  └─ synced_at

Audit Logs (automatic)
  ├─ id
  ├─ table_name
  ├─ operation (INSERT/UPDATE/DELETE)
  └─ timestamp

Job Queue (for async work)
  ├─ id
  ├─ job_type
  ├─ status
  └─ created_at
```

### RLS Policies on github_repos

```sql
-- Allows users to read only repos owned by their org
CREATE POLICY "enable-read-based-github-org" ON github_repos
  FOR SELECT USING (owner = current_user_org);

-- Allows users to update only repos they own
CREATE POLICY "enable-update-owned-repos" ON github_repos
  FOR UPDATE USING (owner = current_user_org);
```

### GSM Integration

The script automatically:
1. Creates `postgres-password` secret in Google Secret Manager
2. Stores the auto-generated password securely
3. Uses the secret for subsequent connections (Day 2 & 3)

**To retrieve the password** (AUTHORIZED PERSONNEL ONLY):
```bash
gcloud secrets versions access latest --secret="postgres-password" --project=nexusshield-prod
```

---

## GOVERNANCE VERIFICATION

After Day 1 completes, verify:

- ✅ **Immutable**: Database schema in git history (`infra/migrations/`)
- ✅ **Ephemeral**: No hardcoded passwords (all in GSM)
- ✅ **Idempotent**: Re-running script is safe (skips completed migrations)
- ✅ **No-Ops**: Fully automated deployment script (0 manual steps)
- ✅ **Hands-Off**: Credentials in GSM, not in code or env vars
- ✅ **Logged**: Full execution logged to `logs/day1-execution.log`

---

## SUCCESS METRICS

| Metric | Expected | How to Verify |
|--------|----------|---------------|
| Database Running | ✅ | `docker ps \| grep postgres` |
| Migrations Applied | 8/8 | `psql ... SELECT COUNT(*) FROM db_version;` |
| Tables Created | 6+ | `psql ... SELECT COUNT(*) FROM information_schema.tables;` |
| RLS Enabled | Yes | `psql ... SELECT COUNT(*) FROM pg_policies;` |
| Health Check | PASS | `psql ... SELECT 1;` |
| Credential Stored | Yes | `gcloud secrets list \| grep postgres-password` |

---

**Time Estimate**: 45 minutes  
**Complexity**: Low-Medium (mostly automated)  
**Risk**: LOW (reversible, well-tested script)  
**Success Rate**: 95%+ (assuming prerequisites met)

---

**Ready?** Run the script and let it execute. Total time: ~45 minutes.  
**Questions?** See "Troubleshooting" above or contact DBA team.
