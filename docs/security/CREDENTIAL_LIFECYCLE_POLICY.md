# Credential Lifecycle Management & Policy

**Status:** ✅ ACTIVE | **Version:** 2.0 | **Last Updated:** 2026-03-11

---

## 🔐 Complete Credential Lifecycle

```
CREATE → DISTRIBUTE → VERIFY → MONITOR → ROTATE → DEPRECATE → ARCHIVE

At each stage: Check freshness, verify integrity, log immutably
```

---

## 📋 Lifecycle Stage Details

### 1. CREATE (Creation & Initial Storage)
**Ownership:** Credential Manager  
**Approval:** Credential Manager OR Security Architect  
**Backends:** GSM (canonical), pending distribution  
**Duration:** 30 days (age before mandatory rotation)  
**Audit:** Full context logged with creator details  

```json
{
  "stage": "create",
  "timestamp": "2026-03-11T10:00:00Z",
  "secret_name": "db-password",
  "creator": "sa-credential-manager@project.iam.gserviceaccount.com",
  "backends": ["GSM"],
  "ttl_seconds": 2592000,
  "created_at_timestamp": "2026-03-11T10:00:00Z",
  "rotation_deadline": "2026-04-10T10:00:00Z"
}
```

### 2. DISTRIBUTE (Send to Mirrors)
**Ownership:** Credential Manager  
**Backends:** Vault, Key Vault, KMS (via mirroring)  
**Validation:** Cross-backend hash verification  
**Audit:** Distribution to each backend logged separately  

```json
{
  "stage": "distribute",
  "timestamp": "2026-03-11T10:05:00Z",
  "secret_name": "db-password",
  "backends": {
    "gsm": {"status": "ok", "hash": "abc123..."},
    "vault": {"status": "ok", "hash": "abc123..."},
    "keyvault": {"status": "ok", "hash": "abc123..."}
  },
  "consistency_check": "PASS"
}
```

### 3. VERIFY (Integrity Check)
**Frequency:** Daily  
**Check Type:** Hash-based content verification  
**Scope:** All backends for consistency  
**Action on Failure:** QUARANTINE + alert  

```json
{
  "stage": "verify",
  "timestamp": "2026-03-11T12:00:00Z",
  "secret_name": "db-password",
  "verification_results": [
    {"backend": "GSM", "hash": "abc123...", "status": "ok", "age_hours": 2},
    {"backend": "Vault", "hash": "abc123...", "status": "ok", "age_hours": 2},
    {"backend": "KeyVault", "hash": "abc123...", "status": "ok", "age_hours": 2}
  ],
  "all_consistent": true
}
```

### 4. MONITOR (Ongoing Observations)
**Frequency:** Continuous (every 6 hours)  
**Checks:** Freshness, access patterns, anomalies  
**Metrics Tracked:**
- Age since creation
- Age since last rotation
- Access frequency
- Last access timestamp
- Error rate

```json
{
  "stage": "monitor",
  "timestamp": "2026-03-11T18:00:00Z",
  "secret_name": "db-password",
  "metrics": {
    "age_hours": 8,
    "hours_since_rotation": null,
    "access_today": 147,
    "last_access": "2026-03-11T17:55:00Z",
    "error_rate": 0.02,
    "status": "healthy"
  }
}
```

### 5. ROTATE (Update & Redistribute)
**Owner:** Credential Manager  
**Trigger:** 30 days OR on-demand  
**Process:**
  1. Generate new version
  2. Verify in GSM (before distribute)
  3. Distribute to all mirrors
  4. Verify cross-backend consistency
  5. Keep old version (immutable, for rollback)
  6. Update all consumers

**Audit:** Every rotation logged with all details

```json
{
  "stage": "rotate",
  "timestamp": "2026-04-10T09:00:00Z",
  "secret_name": "db-password",
  "rotation_details": {
    "old_version": "v1",
    "new_version": "v2",
    "reason": "scheduled_rotation (30d)",
    "rotator": "sa-credential-manager@project.iam.gserviceaccount.com",
    "distribution": {
      "gsm": {"status": "ok", "version": "v2"},
      "vault": {"status": "ok", "version": "v2"},
      "keyvault": {"status": "ok", "version": "v2"}
    },
    "consumers_notified": 3,
    "rollback_available": true
  }
}
```

### 6. DEPRECATE (Stop Using)
**Owner:** Security Architect  
**Trigger:** Migration complete or compromise  
**Process:**
  1. No new access allowed
  2. Existing sessions continue (grace period: 1 hour)
  3. Immutable archive created
  4. Metrics summarized
  5. Audit trail finalized

```json
{
  "stage": "deprecate",
  "timestamp": "2026-05-01T15:00:00Z",
  "secret_name": "old-api-key",
  "deprecation_details": {
    "reason": "migrated_to_oauth",
    "initiated_by": "security-architect@company.com",
    "grace_period_minutes": 60,
    "access_allowed_until": "2026-05-01T16:00:00Z",
    "sessions_still_active": 2
  }
}
```

### 7. ARCHIVE (Store Permanently)
**Owner:** Compliance Officer  
**Storage:** Immutable GCS bucket  
**Retention:** 10 years (regulatory requirement)  
**Access:** Read-only, fully audited  

```json
{
  "stage": "archive",
  "timestamp": "2026-05-01T16:05:00Z",
  "secret_name": "old-api-key",
  "archive_details": {
    "location": "gs://nexusshield-audit-archive/credentials/old-api-key-2026-05-01.tarball.gpg",
    "encrypted": true,
    "encryption_key": "kms://nexusshield/archive-key",
    "life_cycle": "permanent_immutable",
    "retention_years": 10,
    "retention_until": "2036-05-01T16:05:00Z",
    "access_log_location": "gs://nexusshield-audit-archive/access-logs/old-api-key/",
    "hash": "archive-content-hash-xyz"
  }
}
```

---

## 🔄 Lifetime Tracking

```
Age (hours) │ Stage      │ Action
────────────┼────────────┼──────────────────────
0-24        │ CREATE     │ Fresh, being distributed
24-168      │ DISTRIBUTE │ In all backends
168-720     │ VERIFY     │ Daily health checks
720-2160    │ MONITOR    │ Monitor for anomalies (30-90 days)
2160        │ ROTATE     │ CREATE new version
            │ DEPRECATE  │ Old version stops accepting new access
            │ ARCHIVE    │ Move to permanent immutable store
```

---

## 🛡️ Failure Scenarios & Recovery

### Scenario 1: Backend Out of Sync
**Detection:** Cross-backend hash mismatch  
**Response:**
1. QUARANTINE credential (stop new access)
2. Alert Credential Manager + Security Architect
3. System auto-initiates re-mirror
4. Verify consistency
5. Resume access
6. Audit: Incident + resolution logged

### Scenario 2: Stale Credential
**Detection:** Last rotation > 30 days  
**Response:**
1. Warning alert (25 days)
2. Auto-rotate (30 days)
3. Consumers notified
4. Audit: Forced rotation logged

### Scenario 3: High Access Anomaly
**Detection:** Access rate 10x baseline  
**Response:**
1. Immediate alert
2. Rate limit applied (exponential backoff)
3. Security investigation initiated
4. If compromise suspected: quarantine
5. Force rotation on clear

---

## 📊 Audit Schema

Every lifecycle event includes:
```json
{
  "timestamp": "ISO-8601 UTC",
  "secret_id": "unique identifier",
  "stage": "CREATE|DISTRIBUTE|VERIFY|MONITOR|ROTATE|DEPRECATE|ARCHIVE",
  "actor": "service account email",
  "action": "operation performed",
  "result": "SUCCESS|FAIL|WARN",
  "backends_affected": ["GSM", "Vault", "KMS"],
  "verification": {
    "consistency_hash": "sha256 digest",
    "signatures": ["gpg signatures if present"],
    "timestamps": ["Creation", "Distribution", "Verification"]
  },
  "context": {
    "reason": "why this action occurred",
    "approvals": ["approver emails"],
    "duration_ms": "execution time"
  }
}
```

---

## ✅ Compliance Requirements Met

- ✅ Immutable audit trail (every lifecycle event)
- ✅ Time-bound credentials (max 30 days)
- ✅ Multi-backend verification (consistency guaranteed)
- ✅ Automatic rotation (ensures freshness)
- ✅ Graceful deprecation (no sudden access loss)
- ✅ Permanent archival (10-year retention)
- ✅ Zero manual steps (fully automated)
- ✅ Anomaly detection (rate limits, freshness checks)
