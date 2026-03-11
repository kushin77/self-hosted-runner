# Phase 7: Advanced Features & Resilience - Execution Plan
**Date:** March 11, 2026 | **Status:** Ready for Execution | **Version:** 1.0

---

## 🎯 Strategic Overview

**Current State:**  
✅ Production LIVE with NexusShield immutable audit + no-ops framework  
✅ All core APIs operational (migrations, health, metrics, audit)  
✅ Multi-cloud credentials (GSM/Vault/KMS) active with fallback chains  
✅ Observability (Prometheus, Grafana, alerts) deployed and verified  
✅ CI-less automation framework with systemd timers running

**Next Phase:**  
Four EPICs remain to be implemented. This document outlines execution strategy, priorities, and technical approach for each.

---

## 📋 Remaining Work Summary

| EPIC | Title | Scope | Priority | Est. Hours |
|------|-------|-------|----------|-----------|
| **0** | **Multi-Cloud Failover Validation** | Verify production resilience (GSM→Vault→KMS sequential failover) | **🔴 CRITICAL** | 6-8 |
| **3** | **Browser Migration Dashboard** | React UI for migration management (job status, history, DLQ recovery) | 🟡 HIGH | 20-25 |
| **4** | **VS Code Extension** | Portal command integration (migrate from editor, view status) | 🟡 HIGH | 15-20 |
| **5** | **Multi-Cloud Sync Providers** | S3↔GCS, RDS↔CloudSQL, BlobStorage↔FileShare bidirectional sync | 🟠 MEDIUM | 30-40 |

**Recommended Execution Order:**  
1. **EPIC-0 (Failover)** — Operational resilience (production dependency)
2. **EPIC-3 (Dashboard)** — User-facing feature (foundational)
3. **EPIC-4 (VS Code)** — Developer tooling (extends EPIC-3)
4. **EPIC-5 (Sync)** — Advanced capabilities (additive)

---

## 🔴 EPIC-0: Multi-Cloud Failover Validation (CRITICAL)

### Purpose
Verify production system can survive credential system failures without data loss. Current system has GSM→Vault→KMS fallback, but failover behavior untested in production.

### Deliverables
1. **Failover Test Script** (`scripts/ops/test_credential_failover.sh`)
   - Simulate GSM outage (black-hole all GSM requests)
   - Verify Vault fallback engages automatically
   - Verify KMS fallback engages if Vault fails
   - Verify audit trail unaffected during failover
   - Verify job processing continues uninterrupted

2. **Runbook** (`RUNBOOKS/failover_procedures.md`)
   - Step-by-step failover procedures
   - Detection thresholds (e.g., GSM error rate >10% over 5m)
   - Rollback procedures for false positives
   - Recovery checklist

3. **Monitoring Alerts**
   - Alert if primary GSM fails, secondary Vault unavailable
   - Alert if credential fetch latency >5s (indicates fallback chain activated)
   - Alert if audit trail stops (critical blocker)

4. **Production Proof-of-Work**
   - Run failover test on staging replica
   - Document results (jobs completed, audit trail intact, no data loss)
   - Get sign-off from ops team

### Technical Approach
```bash
# scripts/ops/test_credential_failover.sh
# 1. Add iptables rule to black-hole GSM requests (localhost:8888)
# 2. Trigger migration job (should use Vault fallback)
# 3. Verify job in audit trail
# 4. Remove iptables rule (restore GSM)
# 5. Verify subsequent jobs use GSM again
```

### Files to Create
- `scripts/ops/test_credential_failover.sh` (executable bash)
- `RUNBOOKS/failover_procedures.md` (documentation)
- `monitoring/alerts/failover.rules.yaml` (Prometheus rules)

### Success Criteria
- ✅ Failover test passes on staging without data loss
- ✅ Audit trail shows credential source switches (GSM→Vault→KMS)
- ✅ Job processing unaffected during credential failover
- ✅ Runbook tested by ops team (dry-run)
- ✅ Alert rules deployed and validated

**Estimated Time:** 6-8 hours  
**Owner Recommendation:** Execute immediately (production dependency)

---

## 🟡 EPIC-3: Browser Migration Dashboard (HIGH PRIORITY)

### Purpose
User-facing React UI for managing cloud migrations. Provides visibility into job status, history, error handling, and replay functionality.

### Architecture
```
┌─────────────────────┐
│  React Dashboard    │     (Port 3000)
│ (EPIC-3)            │
├─────────────────────┤
│ • Job Status Board  │
│ • Migration History │
│ • DLQ Recovery UI   │
│ • Metrics Viewer    │
└──────────┬──────────┘
           │ HTTP API
           ↓
┌─────────────────────┐
│  Flask API          │     (Port 8080)
│ (Existing)          │
├─────────────────────┤
│ • GET /api/v1/jobs  │     [NEW] List all migration jobs
│ • POST /api/v1/sync │     [NEW] Trigger manual sync
│ • DELETE /api/...   │     [NEW] Cancel job
│ • POST .../replay   │     [NEW] Retry from DLQ
└─────────────────────┘
```

### Deliverables

#### Phase 3a: Backend API Extensions
**Files:** `scripts/cloudrun/app.py` (modifications)

**New Endpoints:**
```python
# List all migration jobs (pagination support)
GET /api/v1/jobs?page=1&limit=50
├─ Response: { "jobs": [...], "total": N, "page": 1 }

# Get single job details with full audit trail
GET /api/v1/jobs/{job_id}/details
├─ Response: { "job": {...}, "audit_entries": [...] }

# Trigger manual sync (dry-run or execute)
POST /api/v1/sync
├─ Body: { "source": "s3://bucket", "dest": "gs://bucket", "dry_run": true }
├─ Response: { "job_id": "...", "status": "queued" }

# Cancel in-progress job
DELETE /api/v1/jobs/{job_id}
├─ Response: { "job_id": "...", "status": "cancelled" }

# Retry failed job from DLQ
POST /api/v1/jobs/{job_id}/replay
├─ Response: { "job_id": "...", "new_attempt": 2 }

# Get system metrics (for dashboard graphs)
GET /api/v1/metrics/summary
├─ Response: { "jobs_queued": N, "jobs_running": N, "jobs_completed": N, "avg_duration_s": X.XX }
```

**Auth:** Require admin-key header for all new endpoints  
**Idempotency:** All requests idempotent (upsert, not insert)

#### Phase 3b: React Dashboard UI
**Framework:** React 18 + Vite  
**Directory:** `frontend/dashboard/` (new)

**Pages:**
1. **Dashboard Home** (`/`)
   - Summary cards: Jobs Queued, Running, Completed, Failed
   - Job timeline graph (last 7 days)
   - System health status (API, Redis, GSM fallback status)

2. **Active Jobs** (`/jobs`)
   - Real-time job status board (table with sortable columns)
   - Filter by source/dest cloud, status, date range
   - Action buttons: View Details, Cancel, Replay (if failed)

3. **Job Details** (`/jobs/:id`)
   - Full job metadata (source, dest, size, progress %)
   - Complete audit trail (timeline view)
   - Error details and recovery options
   - Replay button if job in DLQ

4. **System Metrics** (`/metrics`)
   - Prometheus metrics graphs (via embedded Grafana)
   - Error rate trend (30d)
   - Job duration histogram
   - Credential source usage (GSM vs Vault vs KMS)

**Authentication:** Admin-key in localStorage, sent in X-Admin-Key header

#### Phase 3c: Deployment & Integration
**Files to Create:**
- `frontend/dashboard/package.json` (React + dependencies)
- `frontend/dashboard/vite.config.js` (build config)
- `frontend/dashboard/src/App.jsx` (main component)
- `frontend/dashboard/src/pages/*.jsx` (4 pages above)
- `frontend/dashboard/src/api.js` (API client)
- `frontend/dashboard/Dockerfile` (production image)
- `scripts/deploy/deploy_dashboard.sh` (CI-less deploy)
- `systemd/dashboard.service` (systemd unit)

**Deployment:**
- Build React app (vite build)
- Package with Docker or run in Node
- Deploy via CI-less bash script to production
- Serve on port 3000 (expose via Nginx reverse proxy on port 80/443 if production)

### Success Criteria
- ✅ All 5 API endpoints working with rate limiting, idempotency, audit logging
- ✅ Dashboard UI renders all 4 pages without errors
- ✅ Real-time job status updates (WebSocket or polling)
- ✅ Authentication working (admin-key validated on all endpoints)
- ✅ Deployed to production and accessible

**Estimated Time:** 20-25 hours (phased implementation)  
**Phases:** 3a (API, 4h) → 3b (UI, 15h) → 3c (Deploy, 6h)

---

## 🟡 EPIC-4: VS Code Extension Integration (HIGH PRIORITY)

### Purpose
Integrate Portal migration commands into VS Code. Allow developers to trigger migrations, view status, and manage jobs without leaving editor.

### Architecture
```
┌──────────────────────────┐
│  VS Code Workspace       │
├──────────────────────────┤
│  NexusShield Extension   │  (EPIC-4)
│  ├─ Command Palette      │
│  │  ├─ Migrate S3→GCS
│  │  ├─ View Job Status
│  │  ├─ Replay Failed Job
│  │  └─ View Metrics
│  ├─ Activity Sidebar     │
│  │  └─ Migration Explorer
│  └─ Web View             │
│     └─ Job Details Panel │
└──────────┬───────────────┘
           │ HTTP calls
           ↓
    Flask API (EPIC-3)
```

### Deliverables

**Files:**
- `vscode-extension/package.json` (manifest)
- `vscode-extension/src/extension.ts` (activation)
- `vscode-extension/src/commands/*.ts` (handlers)
- `vscode-extension/src/webviews/*.ts` (UI panels)
- `vscode-extension/icon.png` (logo)

**Commands:**
```
Command: nexusshield.migrate
├─ Prompts user for source/dest S3/GCS paths
├─ Submits via POST /api/v1/sync
├─ Shows job_id in notification

Command: nexusshield.showStatus
├─ Lists active jobs (GET /api/v1/jobs)
├─ Opens WebView panel showing real-time updates

Command: nexusshield.replayJob
├─ Quick-pick failed job from history
├─ Triggers POST /api/v1/jobs/{id}/replay
├─ Shows new attempt notification

Command: nexusshield.viewMetrics
├─ Opens embedded Grafana dashboard
```

**Activity Sidebar:**
- Tree view showing active migrations
- Status indicators (queued, running, completed, failed)
- Context menu with Cancel/Replay options

**Authentication:**
- Prompt user for admin-key on first use
- Store in VS Code Secrets API (not localStorage)
- Sent in X-Admin-Key header for all API calls

### Success Criteria
- ✅ Extension installs from .vsix package
- ✅ All 4 commands registered and callable
- ✅ Commands successfully trigger API endpoints
- ✅ WebView shows real-time job status
- ✅ Sidebar tree shows active migrations with status

**Estimated Time:** 15-20 hours

---

## 🟠 EPIC-5: Multi-Cloud Sync Providers (MEDIUM PRIORITY)

### Purpose
Implement bidirectional data sync between any two cloud storage/database systems.

### Providers
- **S3 ↔ GCS** (object storage)
- **RDS ↔ Cloud SQL** (databases)
- **Azure Blob ↔ GCS** (blob storage)
- **Firestore ↔ DynamoDB** (NoSQL)

### Base Provider Interface
```python
class SyncProvider(ABC):
    @abstractmethod
    def list_objects(self, prefix: str) -> Iterator[Object]: pass
    
    @abstractmethod
    def get_object(self, key: str) -> bytes: pass
    
    @abstractmethod
    def put_object(self, key: str, data: bytes) -> str: pass
    
    @abstractmethod
    def delete_object(self, key: str) -> None: pass
```

### Sync Strategies
- **Full Copy** — All objects source→dest
- **Incremental** — New/modified since last sync
- **Bidirectional** — Merge both directions with conflict resolution
- **Differential** — Only changed blocks

### Files to Create
- `scripts/cloudrun/providers/` (directory)
- `scripts/cloudrun/providers/base.py`
- `scripts/cloudrun/providers/s3.py`
- `scripts/cloudrun/providers/gcs.py`
- `scripts/cloudrun/providers/azure_blob.py`
- `scripts/cloudrun/sync_engine.py`
- `scripts/cloudrun/conflict_resolver.py`

### Success Criteria
- ✅ At least 3 providers fully implemented
- ✅ Full and incremental sync working
- ✅ Data integrity verified (checksums)
- ✅ Audit trail logging all operations
- ✅ Deployed to production

**Estimated Time:** 30-40 hours

---

## 📊 Consolidated Execution Plan

### Phase Timeline
```
Week 1 (Mar 11-15):
  Mon-Tue: EPIC-0 (Failover) ✅ CRITICAL
  Wed-Fri: EPIC-3a (API endpoints)

Week 2 (Mar 18-22):
  Mon-Wed: EPIC-3b (React UI)
  Thu-Fri: EPIC-3c (Deployment)

Week 3 (Mar 25-29):
  Mon-Wed: EPIC-4 (VS Code)
  Thu-Fri: EPIC-5 Phase 1

Week 4 (Apr 1-5):
  All: EPIC-5 Phase 2
```

### Resource Requirements
- **Developer Hours:** ~80 total
- **Testing Time:** ~10 hours
- **Production Deployment:** ~2 hours per EPIC

---

## 🚀 Next Steps

### Question for User:

**Which EPIC should I execute first?**

- **A) EPIC-0 (Failover)** - Critical operational safety for production
- **B) EPIC-3 (Dashboard)** - User-facing feature, foundational
- **C) Parallel execution** - Both simultaneously
- **D) Different priority order?**

Please provide guidance and I will proceed immediately with no waiting.

---

## ✅ Status
**Author:** GitHub Copilot  
**Created:** 2026-03-11T14:45Z  
**Status:** Awaiting user approval for EPIC execution order

