# NexusShield Master Portal — Unified Control Plane Design
**Status:** Strategic Design Phase | **Date:** 2026-03-09 | **Version:** 1.0

---

## 🎯 Executive Summary

**NexusShield** is a unified control plane consolidating 6 phases of infrastructure automation into a single enterprise-grade dashboard with credential lifecycle management, deployment orchestration, and real-time compliance verification.

**Core Value Proposition:**
- **Single Portal** for all credential, deployment, and compliance operations
- **Real-Time Visibility** across OIDC/AppRole/KMS/GSM credentials
- **Audit Immutability** with 100% append-only JSONL + GitHub integration
- **Zero-Manual-Ops** — fully automated workflows triggered from dashboard
- **Serverless Architecture** — scales infinitely without infrastructure management

---

## 📐 Phase 1: Portal Architecture

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         NexusShield Master Portal (React/TypeScript)        │
│  unified-dashboard.nexusshield.cloud                         │
└──────────────────┬──────────────────────────────────────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
    ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│Credential│  │Deployment│  │Compliance│
│ Mgmt API │  │Orch API │  │ Audit API│
│(Node.js) │  │(Node.js) │  │(Node.js) │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │
     ▼             ▼             ▼
  ┌─────────────────────────────────────┐
  │    Core Backend (GraphQL/REST)      │
  │    - Auth (OAuth 2.0 + OIDC)        │
  │    - Data Layer (PostgreSQL)        │
  │    - Event Bus (Kafka/Pub-Sub)      │
  │    - Git Integration (GitHub API)   │
  └──────────────┬──────────────────────┘
                 │
     ┌───────────┼───────────┬──────────┐
     ▼           ▼           ▼          ▼
  ┌────────┐ ┌──────┐ ┌──────┐ ┌────────┐
  │ GCP    │ │ AWS  │ │Vault │ │GitHub  │
  │ Secret │ │Secrets││Secrets│ │Issues/ │
  │Manager │ │Mgr.  ││+Audit  │ │Commits │
  └────────┘ └──────┘ └──────┘ └────────┘
```

### 1.2 API Layer Architecture

**Credential Management API:**
```
POST   /api/v1/credentials/rotate          # Trigger rotation workflow
GET    /api/v1/credentials/status          # Real-time credential health
GET    /api/v1/credentials/{id}/audit-log  # Immutable audit trail
DELETE /api/v1/credentials/{id}/revoke     # Immediate revocation
GET    /api/v1/credentials/health/summary  # 6-point compliance check
```

**Deployment Orchestration API:**
```
POST   /api/v1/deployments/execute         # Trigger Phase workflow
GET    /api/v1/deployments/status          # Workflow progress
GET    /api/v1/deployments/history         # Rollback options
POST   /api/v1/deployments/{id}/rollback   # Automated rollback
GET    /api/v1/deployments/next-scheduled  # Upcoming workflows
```

**Compliance & Audit API:**
```
GET    /api/v1/compliance/dashboard        # Real-time 6-point check
GET    /api/v1/audit/trails/{type}         # JSONL immutable logs
GET    /api/v1/compliance/report           # PDF compliance evidence
POST   /api/v1/compliance/export           # SOC2/ISO27001 reports
GET    /api/v1/audit/github-integration    # GitHub commit + comment audit
```

### 1.3 Dashboard Component Architecture

**Top-Level Views (Unified Dashboard):**

```
┌─────────────────────────────────────────────────────────────┐
│  NexusShield Portal                    [John Doe] [⚙️] [🔔]  │
├─────────────────────────────────────────────────────────────┤
│ ┌─ Sidebar                              ┌─ Main Content    │
│ │ 🏠 Dashboard                          │ ┌───────────────┐│
│ │ 🔐 Credentials                        │ │ COMPLIANCE    ││
│ │ │ ├─ OIDC Pool (GCP)                  │ │ ┌─────────┐  ││
│ │ │ ├─ AppRole (Vault)                  │ │ │  6/6 ✅  │  ││
│ │ │ ├─ KMS Keys (AWS)                   │ │ └─────────┘  ││
│ │ │ └─ GSM Secrets (GCP)                │ │              ││
│ │ 🚀 Deployments                        │ │ CREDENTIALS  ││
│ │ │ ├─ Phase 1 (Live)                   │ │ ┌─────────┐  ││
│ │ │ ├─ Phase 2 (Active)                 │ │ │OIDC 🟢  │  ││
│ │ │ ├─ Phase 3 (Pending)                │ │ │AppRole🟢│  ││
│ │ │ └─ Phase 6 (Next)                   │ │ │KMS 🟢 🔄│  ││
│ │ 📊 Compliance                         │ │ │GSM 🟢   │  ││
│ │ 📋 Audit Logs                         │ │ └─────────┘  ││
│ │ ⚙️  Settings                          │ │              ││
│ │                                       │ │ DEPLOYMENTS  ││
│ │                                       │ │ ┌─────────┐  ││
│ │                                       │ │ │Phase 1 ✅  ││
│ │                                       │ │ │Phase 2 ✅  ││
│ │                                       │ │ │Phase 3 🟡  ││
│ │                                       │ │ │Phase 6 ⏭️   ││
│ │                                       │ │ └─────────┘  ││
│ │                                       │ └───────────────┘│
│ └───────────────────────────────────────└─────────────────┘
└─────────────────────────────────────────────────────────────┘
```

**Dashboard Cards (Real-Time):**

1. **Compliance Status Card** (Top)
   - 6-point verification: Ephemeral Auth ✅ | Linting ✅ | Vault ✅ | KMS ✅ | Audit Trail ✅ | Secrets ✅
   - Last check: 3 minutes ago (auto-refresh every 5 min)
   - Alert threshold: Turn red if any check fails

2. **Credential Health Card** (Left)
   - OIDC Pool: `github-actions` — 47 workflows using, TTL 1h, next rotation in 25d
   - AppRole: `deployment-automation` — 18 active workflows, secret ID TTL 30d, 892/1000 uses
   - KMS: `github-actions-credentials` — next rotation in 358d, 2 cipher ops last 24h
   - GSM: 12 secrets, 0 near-TTL, 3 accessed last 24h

3. **Deployment Orchestration Card** (Center)
   - Live Workflows: 5 running
   - Scheduled Next (24h): Phase 1 lint (8 AM), AppRole rotation (2 AM), KMS rotation (3 AM)
   - Last deployment: Phase 2 AWS OIDC setup (12h ago, ✅ success)
   - Failed recently: None

4. **Audit Trail Card** (Right)
   - Last 10 entries (scrollable):
     ```
     Today 14:32 — Credential rotation — AppRole secret ID rotated — ✅
     Today 12:05 — Compliance check — 6/6 passed — ✅
     Today 08:00 — Credential linting — 0 violations — ✅
     Yesterday 23:15 — KMS key rotation — 365d cycle — ✅
     ```
   - Export options: JSONL | PDF | CSV

---

## 🔌 Phase 2: Integration Points

### 2.1 Credential Lifecycle Management Tab

**Current State Dashboard:**
- **OIDC Pool (GCP Workload Identity)**
  - Status: Active | Pool ID: `projects/123/locations/global/workloadIdentityPools/github-actions`
  - Service Account: `github-actions@project.iam.gserviceaccount.com`
  - Workflows using: 47 | Last used: 2h ago
  - TTL: 1 hour (ephemeral) | Expiry: 2026-04-09
  - Actions: [Rotate Now] [Audit Trail] [Revoke]

- **AppRole (Vault)**
  - Status: Active | Auth path: `auth/approle`
  - Roles: deployment-automation (active), credential-rotation (active), observability (standby)
  - Secret ID TTL: 30 days | Token TTL: 1 hour | Uses: 892/1000
  - Last rotation: 2026-02-08 | Next: 2026-02-38
  - Actions: [Force Rotation] [Create Role] [Audit Trail] [Revoke Role]

- **KMS Keys (AWS)**
  - Status: Active | Key ARN: `arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012`
  - Key Status: Enabled | Rotation: Automatic (365-day cycle)
  - Last rotation: 2025-03-09 | Next rotation: 2026-03-09
  - Encryption ops (24h): 238 | Decryption ops: 156
  - Actions: [Test Encryption] [Rotate Now] [Audit Trail] [Disable]

- **GSM Secrets (Google Secret Manager)**
  - Secrets: 12 total | Near-TTL (<7d): 0 | Expired: 0
  - Latest access: vault-token (1h ago), deployment-key (4h ago), oauth-client-secret (12h ago)
  - Actions: [Add Secret] [Rotate Secret] [Audit Trail] [Export]

**Bulk Actions Panel:**
```
[All OIDC] [All AppRole] [All KMS] [All GSM]
[Rotate All] [Revoke All] [Health Check All] [Export Audit]
```

### 2.2 Deployment Orchestration Tab

**Workflow Timeline View:**
```
┌─ Phase 1 Workflows (OIDC Migration) ─────────────────────────┐
│ ✅ COMPLETE (2026-02-28)                                     │
│ • ci-credential-lint.yml — Daily 8 AM UTC                   │
│ • auto-deploy-phase3b.yml — On main merge                   │
│ • phase3-revoke-keys.yml — Manual                           │
│ • autonomous-deployment-orchestration.yml — Manual          │
│ Status: 4/4 Live | Success Rate: 98.2% | Last exec: 8 AM   │
└─────────────────────────────────────────────────────────────┘

┌─ Phase 2 Workflows (Vault + KMS Rotation) ────────────────────┐
│ 🟢 OPERATIONAL (2026-03-09)                                   │
│ • phase2-vault-approle-rotation.yml — Sun 2 AM UTC           │
│ • phase2-kms-rotation.yml — Sun 3 AM UTC                     │
│ • phase2-compliance-audit.yml — Mon 5 AM UTC                 │
│ • phase2-unblock-blockers.yml — Daily 1 AM UTC              │
│ Status: 4/4 Ready | Next exec: Sun 2 AM UTC (in 1d 10h)    │
│ Actions: [Execute Now] [Pause] [Edit Schedule] [View Log]   │
└─────────────────────────────────────────────────────────────┘

┌─ Phase 3+ Workflows (Future Phases) ────────────────────────────┐
│ ⏳ SCHEDULED (Days 27-90)                                     │
│ • phase3-gcp-infrastructure.yml — Day 27 (2026-04-05)       │
│ • phase4-observability-e2e.yml — Day 45 (2026-04-23)        │
│ • phase5-multi-cloud-failover.yml — Day 60 (2026-05-08)     │
│ • phase6-admin-operationalization.yml — Day 90 (2026-06-07) │
│ Status: 4/4 Queued | Auto-execute: ON                       │
│ Actions: [Reschedule] [Manual Trigger] [View Docs]          │
└─────────────────────────────────────────────────────────────┘
```

**Execution Control Panel:**
```
┌─ Execution History ─────────────────────────────────────────┐
│ Filter: [Last 24h ▼] [Status: All ▼] [Phase: All ▼]        │
│ ┌─ 2026-03-09 08:00 — ci-credential-lint — PASSED (2m 14s) │
│ │ Violations: 0 | Secrets scanned: 847 | Baseline: ✅       │
│ │ [View Log] [Re-run] [Rollback]                            │
│ │                                                            │
│ ├─ 2026-03-08 14:32 — phase2-kms-rotation — PASSED (5m 47s)│
│ │ Keys rotated: 1 | Test encrypt: PASS | CloudTrail: 12 ops│
│ │ [View Log] [Re-run] [Rollback]                            │
│ │                                                            │
│ └─ 2026-03-07 02:15 — phase2-vault-approle-rotation — PASS  │
│   Secrets rotated: 3 roles | New secret IDs: 3 | TTL: 30d  │
│   [View Log] [Re-run] [Rollback]                            │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Compliance & Audit Tab

**Real-Time Compliance Report:**
```
┌─ NexusShield Compliance Dashboard ──────────────────────────┐
│ Last verified: 2m ago (auto-verify every 5m) | Score: 6/6 ✅│
│                                                             │
│ ✅ 1. Ephemeral Authentication                             │
│    All workflows use OIDC (1h TTL) — No long-lived creds  │
│    Credential source: GitHub Actions ID tokens             │
│    Lifespan: 5 minutes (expiry in JWT)                     │
│    Status: PASS | Verified: 2m ago                        │
│                                                             │
│ ✅ 2. Credential Linting                                   │
│    Scan: gitleaks + regex patterns + entropy checks       │
│    Last scan: 2026-03-09 08:00 UTC (Daily 8 AM)           │
│    Violations in last 24h: 0                               │
│    Files scanned: 847 | Baseline rules: 19                │
│    Status: PASS | Verified: 2h ago                        │
│                                                             │
│ ✅ 3. Vault Integration                                    │
│    AppRole auth: ACTIVE | Roles: 3                        │
│    Secret ID lifetimes: 7-30d | Uses: 892/1000           │
│    Token TTL: 1h | Auto-renew: 55min                      │
│    Last access: 4h ago | Audit entries: 2847              │
│    Status: PASS | Verified: 6m ago                        │
│                                                             │
│ ✅ 4. KMS Key Rotation                                     │
│    Master key: github-actions-credentials                 │
│    Encryption ops (24h): 238 | Decryption: 156           │
│    Auto-rotation: ENABLED (365d cycle)                    │
│    Last rotation: 2025-03-09 | Next: 2026-03-09          │
│    Status: PASS | Verified: 1h ago                        │
│                                                             │
│ ✅ 5. Immutable Audit Trail (JSONL)                        │
│    Storage: GitHub repo + CloudTrail + Vault logs        │
│    JSONL entries: 20,847 | GitHub commits: 156            │
│    Size: 8.3 MB | Retention: ∞ (git immutable)           │
│    Last entry: 2026-03-09 14:37 UTC                       │
│    Status: PASS | Verified: 1m ago                        │
│                                                             │
│ ✅ 6. No Long-Lived Credentials                            │
│    Long-lived keys scanned: 0                              │
│    Fallback keys (backup only): 2 (encrypted, emergency) │
│    Service accounts using OIDC: 100%                       │
│    Status: PASS | Verified: 2m ago                        │
│                                                             │
│ OVERALL COMPLIANCE: 100% ✅ | Trend: ↗️ +8 entries today  │
└─────────────────────────────────────────────────────────────┘
```

**Immutable Audit Trail Viewer:**
```
┌─ JSONL Audit Log (Immutable) ────────────────────────────────┐
│ Export: [JSONL] [PDF] [CSV] | Filter: [Date] [Type] [Status]│
│ ┌─ Entry 20847 (Latest) ───────────────────────────────────┐
│ │ Timestamp: 2026-03-09T14:37:29Z                         │
│ │ Action: credential_rotation                             │
│ │ Resource: approle:credential-rotation                   │
│ │ Status: success                                          │
│ │ Details: Secret ID rotated, TTL 30d, use limit 1000    │
│ │ Actor: github-actions-workflow                          │
│ │ Immutable Hash: 8a2f4c9e1b7d5f3a6e9c2b4d1f8a7e5c      │
│ │ Git Commit: 90298e381                                   │
│ │ GitHub Issue: #2160 (comment ref)                      │
│ └─────────────────────────────────────────────────────────┘
│ ┌─ Entry 20846 ────────────────────────────────────────────┐
│ │ Timestamp: 2026-03-09T08:00:15Z                         │
│ │ Action: compliance_check                                │
│ │ Result: 6/6 passed                                      │
│ │ Duration: 2m 14s                                        │
│ │ Violations: 0                                           │
│ │ Immutable Hash: 7b1e3d8f9c5a2e6b4f1d3c8a9e7f2b5      │
│ │ GitHub Issue: #2160 (comment ref)                      │
│ └─────────────────────────────────────────────────────────┘
```

---

## 🏗️ Phase 3: Data Model & Storage

### 3.1 PostgreSQL Schema

```sql
-- Core Tables

CREATE TABLE organizations (
  id UUID PRIMARY KEY,
  name VARCHAR(256) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE credentials (
  id UUID PRIMARY KEY,
  org_id UUID REFERENCES organizations(id),
  type ENUM('oidc_pool', 'approle', 'kms_key', 'gsm_secret'),
  provider ENUM('gcp', 'aws', 'vault', 'github'),
  name VARCHAR(256) NOT NULL,
  status ENUM('active', 'rotating', 'revoked', 'expired'),
  ttl_seconds INT,
  last_rotated TIMESTAMP,
  next_rotation TIMESTAMP,
  metadata JSONB,
  audit_log_path VARCHAR(512),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE deployments (
  id UUID PRIMARY KEY,
  org_id UUID REFERENCES organizations(id),
  phase INT,
  workflow_name VARCHAR(256),
  status ENUM('scheduled', 'running', 'success', 'failed', 'rollback'),
  triggered_at TIMESTAMP,
  completed_at TIMESTAMP,
  duration_seconds INT,
  executed_by VARCHAR(256),
  metadata JSONB,
  audit_log_path VARCHAR(512),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit_entries (
  id UUID PRIMARY KEY,
  org_id UUID REFERENCES organizations(id),
  action VARCHAR(256),
  resource_type VARCHAR(256),
  resource_id VARCHAR(256),
  status ENUM('success', 'failure', 'pending'),
  details JSONB,
  actor VARCHAR(256),
  immutable_hash VARCHAR(256),
  github_commit_sha VARCHAR(40),
  github_issue_comment_id BIGINT,
  jsonl_path VARCHAR(512),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(immutable_hash) -- Ensure no duplicates via hash
);

CREATE TABLE compliance_checks (
  id UUID PRIMARY KEY,
  org_id UUID REFERENCES organizations(id),
  check_type VARCHAR(256),
  check_name VARCHAR(256),
  status ENUM('pass', 'fail', 'warning'),
  score INT,
  max_score INT,
  details JSONB,
  verified_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE webhooks (
  id UUID PRIMARY KEY,
  org_id UUID REFERENCES organizations(id),
  event_type VARCHAR(256),
  url VARCHAR(512),
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_credentials_org_type ON credentials(org_id, type);
CREATE INDEX idx_deployments_phase_status ON deployments(org_id, phase, status);
CREATE INDEX idx_audit_entries_org_action ON audit_entries(org_id, action);
CREATE INDEX idx_compliance_checks_org_type ON compliance_checks(org_id, check_type);
```

### 3.2 Event Stream (Kafka/Google Pub-Sub)

```
Topics (auto-created):
- org.{org_id}.credential.rotated
- org.{org_id}.deployment.triggered
- org.{org_id}.deployment.completed
- org.{org_id}.compliance.check
- org.{org_id}.audit.entry

Event Schema Example:
{
  "event_id": "evt_12345678",
  "org_id": "org_abc123",
  "timestamp": "2026-03-09T14:37:29Z",
  "event_type": "credential.rotated",
  "resource": {
    "type": "approle",
    "id": "role_credential_rotation",
    "provider": "vault"
  },
  "metadata": {
    "ttl_days": 30,
    "secret_id_uses": 892,
    "max_uses": 1000
  },
  "immutable_hash": "8a2f4c9e1b7d5f3a6e9c2b4d1f8a7e5c",
  "audit_trail": {
    "github_commit": "90298e381",
    "jsonl_log": "logs/phase2-blockers-resolution-2026-03-09T143729Z.jsonl"
  }
}
```

---

## 🔐 Phase 4: Security & Auth

### 4.1 Authentication Flow

```
User Login → GitHub OAuth → NexusShield OAuth Provider
                              ↓
                        Issue JWT (30m)
                        Issue Refresh (7d)
                              ↓
                     Validate against GitHub
                     Check org memberships
                              ↓
                        Return to Portal
                     Set httpOnly secure cookie
```

### 4.2 Authorization Model (RBAC)

```
Role: Admin
- Credential lifecycle (rotate, revoke, view all)
- Deployment control (trigger, schedule, rollback)
- Compliance reporting (full access)
- User management (invite, remove, change roles)
- Audit log export (all levels)

Role: Operations Engineer
- Credential health monitoring (view, rotate)
- Deployment status monitoring
- Compliance dashboard view
- Audit log view (limited to last 90 days)
- Cannot delete or revoke

Role: Developer
- Credential status (read-only)
- Deployment history view (read-only)
- Compliance score view (read-only)
- Cannot modify anything

Role: Audit (SOC2/ISO27001)
- Full audit log access
- Compliance reports
- Immutable hash verification
- Cannot modify anything
```

---

## 📡 Phase 5: Real-Time Updates

### 5.1 WebSocket Integration

```
Connection → Portal subscribes to org events
             ws://api.nexusshield.cloud/subscribe?org_id={id}

Message Flow:
Server → Client: credential_status_update
  {
    "type": "credential_status",
    "credential_id": "cred_approle_123",
    "status": "rotating",
    "progress": 45,
    "eta_seconds": 120
  }

Server → Client: deployment_progress
  {
    "type": "deployment_progress",
    "deployment_id": "deploy_456",
    "phase": 2,
    "step": "rotating_vault_approles",
    "progress": 12,
    "total_steps": 8
  }

Server → Client: compliance_updated
  {
    "type": "compliance_check",
    "check_id": "check_6",
    "name": "KMS Key Rotation",
    "status": "pass",
    "verified_at": "2026-03-09T14:37:29Z"
  }
```

---

## 📊 Phase 6: Reporting & Analytics

### 6.1 Pre-Built Reports

1. **Compliance Dashboard** (Real-time)
   - 6-point verification scores
   - Trend analysis (7d, 30d, YTD)
   - Violations timeline
   - Export: PDF, CSV, JSON

2. **Credential Lifecycle Report** (Weekly)
   - Rotation schedule adherence
   - TTL distribution
   - Failed rotations
   - Access patterns

3. **Deployment Performance Report** (Monthly)
   - Phase completion times
   - Success rates
   - Rollback frequency
   - Infrastructure cost allocation

4. **Audit Trail Report** (On-demand)
   - Immutable JSONL export
   - GitHub commit hashes
   - Signature verification
   - Regulatory compliance (SOC2/ISO27001)

### 6.2 Custom Dashboard Builder

```
Drag-and-drop metrics:
- Credential health scorecards
- Deployment timeline
- Audit entry volume (per hour/day)
- Compliance trend charts
- Cost allocation (per phase/per org)
```

---

## 🚀 Phase 7: Deployment Architecture

### 7.1 Production Infrastructure

```
Tier 1: Frontend (CDN)
- React SPA hosted on CloudFlare/CloudFront
- Auto-scaling, geo-redundant
- Cache: CSS/JS/images (365d TTL)
- Purge on deployment

Tier 2: Backend (Serverless)
- Node.js API on Cloud Run / Lambda
- Auto-scaling (0-100 instances)
- Regional deployments (US, EU, APAC)
- Cost: ~$0.00024/request, $0.30/vCPU/hour

Tier 3: Database (Managed PostgreSQL)
- Cloud SQL / RDS Multi-AZ
- Read replicas for analytics
- Automated backup (15-min granularity)
- Point-in-time recovery (30d)

Tier 4: Event Bus (Kafka / Pub-Sub)
- Message queue for audit trails
- Dead-letter queue for failures
- Retention: 7 days (hot) + S3 archive (180d)
- Throughput: 1M+ messages/day

Tier 5: Storage (Immutable)
- GitHub repo (append-only git history)
- S3 / Cloud Storage (JSONL archives)
- Versioning enabled, delete protection
- Compliance: MFA delete, lifecycle (7y retention)
```

### 7.2 Disaster Recovery

```
RTO (Recovery Time Objective): 15 minutes
RPO (Recovery Point Objective): 5 minutes

Archive Strategy:
- Every 12h: PostgreSQL snapshot to S3
- Real-time: JSONL logs to GitHub + S3
- Quarterly: Full compliance audit export

Failover Procedure:
1. Detect primary region failure (3 consecutive health checks)
2. Promote read replica to primary (5 min)
3. Update DNS to regional failover endpoint (2 min)
4. Alert stakeholders, begin investigation
```

---

## 📈 Phase 8: Scalability Roadmap

| Metric | Current | 12mo Target | 24mo Target |
|--------|---------|-------------|-------------|
| Orgs | 1 | 500 | 50,000 |
| Daily API calls | 5K | 500K | 10M |
| Audit entries/day | 200 | 50K | 500K |
| Portal uptime | 99.5% | 99.95% | 99.99% |
| Deployment cycles | 6 | 50+ | 200+ |
| Compliance checks/org | 6 | 15 | 30 |
| Database size | 500 MB | 100 GB | 5 TB |
| Regional regions | 1 (US) | 3 (US, EU, APAC) | 6+ global |

---

## 🎓 Phase 9: Documentation & Support

### 9.1 In-App Help System

```
Tour: First-time user onboarding
- Credential management quickstart (2 min)
- Deployment orchestration (3 min)
- Compliance dashboard walkthrough (2 min)
- Audit log interpretation (1 min)

Contextual Help:
- Chat bubble on each dashboard card
- Video tutorials (YouTube embeds)
- FAQ linked to common actions
- API documentation (OpenAPI 3.0)

Status Page:
- Uptime history (30d, 90d, 365d)
- Incident timeline
- Maintenance window calendar
```

### 9.2 Support Tiers (See Pricing Section)

---

## 🔗 Integration Roadmap

**Phase 1 (MVP):**
- GitHub Actions (read workflows, write commits)
- Vault (AppRole CRUD)
- AWS IAM (OIDC provider, KMS key data)
- Google Cloud (WIF pool, service accounts)

**Phase 2 (3 months):**
- Slack notifications (credential health, deployments)
- PagerDuty alerts (compliance failures)
- Jira issue tracking (deployment failures)
- DataDog metrics export

**Phase 3 (6 months):**
- Terraform state management
- ArgoCD integration
- Kubernetes secrets sync
- HashiCorp Boundary SSH sessions

---

## 📋 Summary Table

| Component | Status | Purpose | Users |
|-----------|--------|---------|-------|
| Dashboard | Design | Real-time unified view | All |
| Credential Tab | Design | OIDC/AppRole/KMS/GSM lifecycle | Ops |
| Deployment Tab | Design | Phase workflow orchestration | Ops + Devs |
| Compliance Tab | Design | 6-point audit + reporting | Ops + Audit |
| API Layer | Design | Programmatic integration | Integrations |
| PostgreSQL | Design | State + audit storage | Backend |
| Event Bus | Design | Real-time notifications | Backend |
| Auth (OAuth 2.0) | Design | GitHub-based access | All |
| Webhooks | Design | External integrations | Customers |
| Serverless Backend | Design | Scalable compute | Backend |
| CDN Frontend | Design | Global distribution | All |

---

**Next Steps:** Implement Phase 1 (Portal MVP), then design monetization tiers based on features & deployment complexity.

