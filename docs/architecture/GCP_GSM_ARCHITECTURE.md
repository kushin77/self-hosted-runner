# GCP GSM Integration Architecture

**Status**: ✅ Production Ready  
**Version**: 1.0  
**Date**: March 8, 2026

---

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│  GitHub Actions Automation Framework                         │
│                                                              │
│  4-Layer Credential Management System                        │
└──────────────────────────────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────────┐
    │ Layer 1: SYNC (Every 15 min)          │
    │ - GitHub → GCP Secret Manager          │
    │ - Immutable versioning                 │
    │ - Automatic deduplication              │
    └────────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────────┐
    │ Layer 2: ROTATION (Daily at 2 AM UTC) │
    │ - Age-based lifecycle tracking         │
    │ - TTL policy enforcement               │
    │ - Version archival (keep 3)            │
    │ - Notification triggers                │
    └────────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────────┐
    │ Layer 3: BREACH RESPONSE (On-demand)  │
    │ - < 2 min automated revocation         │
    │ - All versions destroyed               │
    │ - Audit trail created                  │
    │ - Incident reporting                   │
    └────────────────────────────────────────┘
         ↓
    ┌────────────────────────────────────────┐
    │ Layer 4: MONITORING & AUDIT (Continuous)
    │ - Consistency verification             │
    │ - Access logging                       │
    │ - Compliance reporting                 │
    │ - Alerting (overdue rotations)        │
    └────────────────────────────────────────┘
```

---

## Component Inventory

### Workflows (3 Primary + 1 Base)
| Workflow | Schedule | Purpose | Trigger |
|----------|----------|---------|---------|
| `gcp-gsm-sync-secrets.yml` | Every 15 min | Sync GitHub ↔ GSM | Schedule |
| `gcp-gsm-rotation.yml` | Daily 2 AM UTC | Check rotation status | Schedule |
| `gcp-gsm-breach-recovery.yml` | On-demand | Emergency response | Dispatch |
| `store-slack-to-gsm.yml` | Manual | Store leaked secrets | Manual |

### Scripts (3 Core + 1 Enhanced)
| Script | Lines | Purpose | Execution |
|--------|-------|---------|-----------|
| `gcp-gsm-sync.sh` | ~250 | Credential synchronization | Workflow |
| `gcp-gsm-rotation.sh` | ~200 | TTL policy enforcement | Workflow |
| `gcp-gsm-emergency-recovery.sh` | ~300 | Breach response | On-demand |
| `store-slack-to-gsm.yml` | ~144 | Incident credential storage | Manual |

### Supported Secrets (9 Critical)
```
GCP Integration:
  - gcp-service-account     (GCP_SERVICE_ACCOUNT_KEY)
  - gcp-project-id          (GCP_PROJECT_ID)
  - gcp-workload-identity-provider
  - gcp-service-account-email

AWS Integration:
  - aws-oidc-role-arn       (AWS_OIDC_ROLE_ARN)
  - aws-role-to-assume       (AWS_ROLE_TO_ASSUME)

Third-Party Integration:
  - slack-bot-token         (SLACK_BOT_TOKEN)
  - vault-address           (VAULT_ADDR)
  - vault-token             (VAULT_TOKEN)
```

---

## Data Flow Architecture

### Sync Workflow Pipeline (15-min Cycle)
```
START (cron: */15 * * * *)
  │
  ├─ Checkout code
  │
  ├─ GCP OIDC Authentication
  │   ├─ Load workload identity provider
  │   ├─ Assume service account role
  │   ├─ Generate temporary access token
  │   └─ Validate GCP project access
  │
  ├─ Run gcp-gsm-sync.sh
  │   ├─ Validate environment
  │   │   ├─ Check PROJECT_ID set
  │   │   ├─ Verify gcloud CLI available
  │   │   └─ Confirm GCP authentication
  │   │
  │   ├─ For each secret in sync list:
  │   │   ├─ Read from GitHub env vars
  │   │   ├─ Check if exists in GSM
  │   │   ├─ If exists: Add new version
  │   │   └─ If not: Create with labels
  │   │
  │   ├─ Verify sync consistency
  │   │   ├─ List all synced secrets
  │   │   ├─ Check metadata readability
  │   │   └─ Generate audit report
  │   │
  │   └─ Archive old logs (keep 10)
  │
  ├─ Generate sync report
  │   ├─ Count synced vs failed
  │   ├─ Extract last 20 log lines
  │   └─ Determine overall status
  │
  ├─ Update issue #1381 with status
  │   ├─ Retrieve latest sync log
  │   ├─ Format as comment
  │   └─ Post to tracking issue
  │
  ├─ Guard checks
  │   └─ Verify GSM consistency
  │
  └─ END (Upload logs → Artifact store)
```

### Rotation Check Pipeline (Daily at 2 AM UTC)
```
START (cron: 0 2 * * *)
  │
  ├─ For each monitored secret:
  │   ├─ Get latest version creation timestamp
  │   ├─ Calculate age in days
  │   ├─ Compare against TTL policy
  │   │
  │   ├─ If age < TTL:
  │   │   └─ Log: "No rotation needed (X/Y days)"
  │   │
  │   └─ If age >= TTL:
  │       ├─ Mark secret for rotation
  │       ├─ Archive old versions (keep 3)
  │       ├─ Create rotation tracking issue
  │       └─ Notify via #1381 comment
  │
  ├─ Generate compliance audit report
  │   ├─ Table: secret name | age | max_age | status
  │   ├─ Count: total | overdue | compliant
  │   └─ Archive report
  │
  ├─ Post audit summary to #1381
  │
  └─ END
```

### Breach Response Pipeline (On-Demand)
```
TRIGGER: /breach, /revoke-secret, /emergency-rotate
  │
  ├─ Generate incident ID (INCIDENT-timestamp-random)
  │
  ├─ Execute chosen action:
  │   │
  │   ├─ REVOKE:
  │   │   ├─ Revoke secret immediately
  │   │   ├─ Destroy all versions
  │   │   └─ Mark in metadata
  │   │
  │   ├─ COMPROMISE:
  │   │   ├─ Same as REVOKE
  │   │   ├─ Create breach audit entry
  │   │   └─ Send Slack escalation
  │   │
  │   ├─ EXPOSURE:
  │   │   ├─ Same as REVOKE
  │   │   ├─ Add location metadata
  │   │   └─ Create cleanup issue
  │   │
  │   └─ MASS-ROTATE:
  │       ├─ Revoke ALL monitored secrets
  │       ├─ Destroy all versions (every secret)
  │       ├─ Create high-severity incident issue
  │       └─ Send critical escalation
  │
  ├─ Generate incident report
  │   ├─ Incident ID
  │   ├─ Action taken
  │   ├─ Timestamp
  │   ├─ Response log (last 40 lines)
  │   └─ Archive for compliance
  │
  ├─ Comment on triggering issue
  │   └─ Link incident report
  │
  ├─ Create high-priority ops issue
  │   ├─ Title: "[INCIDENT] GSM Emergency Response"
  │   ├─ Body: Details + operator next steps
  │   └─ Labels: emergency, ops, incident-response
  │
  └─ END (< 2 minutes total)
```

---

## Authentication Architecture

### OIDC-First Model

```
GitHub Actions Workflow
    │
    ├─ Requests OIDC token from GitHub's token service
    │ (Audience: https://iam.googleapis.com/google.iam.credentials.workload_identity_user)
    │
    ├─ GitHub issues JWT token
    │ (Signed by GitHub's OIDC provider, includes:)
    │   - job_id, repository, ref, actor, etc.
    │
    ├─ Exchange JWT for GCP access token
    │ (via Workload Identity Federation)
    │   ├─ URL: https://sts.googleapis.com/v1/token
    │   ├─ Subject: GitHub JWT
    │   └─ Audience: GCP workload identity pool
    │
    ├─ GCP validates JWT signature
    │ (Checks GitHub's public OIDC key)
    │
    ├─ Generate temporary access token
    │ (Valid for 1 hour, scoped to service account)
    │
    └─ Use token for gcloud operations
     (Secret Manager reads/writes)
```

**Advantages**:
- ✅ No long-lived credentials stored as secrets
- ✅ Time-limited tokens (1 hour)
- ✅ Automatic rotation by Google
- ✅ Full audit trail (who, when, what)
- ✅ Can require additional checks (e.g., branch == main)

### Fallback Authentication

If OIDC unavailable:
```
GitHub Secret (GCP_SERVICE_ACCOUNT_KEY)
    ↓
Service Account JSON (contains private key)
    ↓
gcloud auth activate-service-account
    ↓
Use service account credentials
```

---

## Secret Version Management

### Immutable Versioning Strategy

```
Secret: gcp-service-account

Timeline:
  Day 1:  version 1 (created)
  Day 15: version 2 (rotated)
  Day 30: version 3 (rotated) ← Current active
  Day 45: version 4 (rotated)
          version 1 (archived)  ← Oldest version destroyed
                                  (Keep only 3 latest)

Access Pattern:
  - Latest always returns current active version
  - Historical versions available for debugging
  - Destroyed versions cannot be recovered

Tracking:
  - Created timestamp → Age calculation
  - Labels → gh-saas-sync, rotation-pending, status, etc.
  - Metadata → Access logs, rotation history
```

---

## Compliance & Audit

### Audit Trail

Every GSM operation creates immutable audit entry:
```json
{
  "timestamp": "2026-03-08T14:23:15Z",
  "operation": "secretmanager.googleapis.com/SecretVersion.add",
  "secret": "gcp-service-account",
  "actor": "github-gsm-manager@project.iam.gserviceaccount.com",
  "action": "version_added",
  "severity": "NOTICE",
  "status": "SUCCESS"
}
```

Accessible via:
```bash
gcloud logging read "resource.type=secretmanager.googleapis.com" --limit=1000
```

### Rotation Compliance

**Default Policies**:
| Secret | Max Age | Check Frequency | Reason |
|--------|---------|-----------------|--------|
| GCP Service Account | 30 days | Daily | Critical infrastructure |
| AWS OIDC Role | 90 days | Daily | Cross-cloud credential |
| Slack Token | 60 days | Daily | Integration stability |
| Vault Token | 45 days | Daily | Secret backend auth |

---

## Performance Characteristics

### Sync Performance
- **Sync startup latency**: ~5-10 seconds (checkout + auth)
- **Per-secret sync time**: ~200-500ms (create/update)
- **Total sync time**: ~30-60 seconds (for 9 secrets)
- **Network calls**: ~12-15 (auth + list + upsert for each secret)

### Rotation Check Performance  
- **Startup**: ~5-10 seconds
- **Per-secret check**: ~100-200ms (describe + calculate)
- **Total time**: ~15-30 seconds (for 9 secrets)

### Breach Response Performance
- **Initiation to execution**: < 60 seconds
- **Per-secret revocation**: ~200-300ms
- **Mass revocation (9 secrets)**: ~2-3 minutes
- **Issue creation**: ~1-2 minutes
- **Total response time**: < 5 minutes

---

## Disaster Recovery

### Backup Strategy
```
GitHub Secrets
  ↓ (Backed up by GitHub's infrastructure)
     
GCP Secret Manager
  ├─ Automatic replication (multi-region)
  ├─ Version history (last 3 versions kept)
  ├─ Immutable audit trail
  └─ Point-in-time recovery possible

External Backups (recommended):
  - Encrypted export to secure bucket
  - Scheduled nightly export
  - Separate GCP project for backups
```

### Recovery Procedures

**Scenario 1: Lost secret in GitHub**
```bash
# Restore from GSM:
gcloud secrets versions access latest --secret=gcp-service-account | \
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
```

**Scenario 2: Lost secret in GSM**
```bash
# Restore from GitHub secret:
gh secret list | grep GCP
# Contact incident response team for backup restore
```

**Scenario 3: Accidental secret deletion**
```bash
# GCP versioning prevents immediate loss:
gcloud secrets versions list SECRET_NAME
# Can restore from old version if available (keep 3 versions)
```

---

## Scalability

### Current Capacity
- **Secrets managed**: 9
- **Sync frequency**: 4× per hour (every 15 min)
- **Rotation checks**: 1× per day
- **Max workflow concurrency**: 10 (per GCP quota)

### Scaling Path (Future)
```
Current (9 secrets):
  - 96 syncs/day
  - ~2 GB logs/month
  - ~1000 audit entries/day

Near-term (50 secrets):
  - Add batch processing
  - ~500 syncs/day
  - Archive logs daily

Long-term (500+ secrets):
  - Database-backed tracking
  - Batch operations
  - Archive strategy
```

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| **Compromised GitHub secret** | OIDC removes need for long-lived secrets; automatic token rotation |
| **Unauthorized GSM access** | Service account has minimal permissions; RBAC enforcement |
| **Data exposure in logs** | Secrets masked in logs; log rotation enabled |
| **Network interception** | All traffic TLS encrypted; mTLS for GCP APIs |
| **Replay attacks** | JWT tokens include GitHub request ID, nonce, audience validation |

### Secret Masking
```bash
# Secrets automatically masked in logs:
- Before: gcloud secrets create --data-file=$SECRET
- After:  gcloud secrets create --data-file=****

# Log masking configured in:
- .github/workflows/gcp-gsm-*.yml (output masking)
- scripts/automation/gcp-gsm-*.sh (echo redaction)
```

---

## Monitoring & Alerting

### Metrics to Track
```
Sync Success Rate:
  - Target: > 99% (< 1 failure per day)
  - Alert if: 3 consecutive failures

Rotation Compliance:
  - Target: 100% (no overdue secrets)
  - Alert if: Any secret exceeds TTL by 1 day

Breach Response Time:
  - Target: < 5 minutes (automated)
  - Alert if: Response takes > 10 minutes

Audit Log Completeness:
  - Target: Every operation logged
  - Alert if: Missing entries detected
```

### Dashboard (Proposed)
```
Status: OPERATIONAL ✅

Last Sync:    2026-03-08 14:23:15 UTC ✅
Last Rotation: 2026-03-08 02:00:00 UTC ✅
Incidents:     0 (today)
Compliance:    100% (all secrets within TTL)

Recent Issues:
  - #1381 (auto-updated every 15 min)
  - #XXXX (rotation due: vault-token)
```

---

## References

- [GCP Secret Manager Docs](https://cloud.google.com/secret-manager/docs)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub OIDC in GCP](https://cloud.google.com/docs/authentication/federation/oidc-workload-identity)
- [GCP Audit Logging](https://cloud.google.com/logging/docs)

---

**Document Version**: 1.0  
**Last Updated**: March 8, 2026  
**Maintained By**: DevOps + Security Teams  
