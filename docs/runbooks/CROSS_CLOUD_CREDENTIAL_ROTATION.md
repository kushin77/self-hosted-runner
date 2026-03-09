# Cross-Cloud Credential Rotation Orchestration

**Status**: ✅ Production Ready  
**Deployment Date**: March 8, 2026  
**Version**: 1.0  

---

## 📋 Overview

**Purpose**: Automate credential rotation across AWS, GCP, and Vault with intelligent orchestration, fallback recovery, and compliance tracking.

**Key Features**:
- ✅ Coordinated multi-cloud rotation (dependencies respected)
- ✅ Automated fallback/recovery (3 retries per service)
- ✅ Validation after each rotation
- ✅ Rollback procedures (if failures detected)
- ✅ Compliance audit trails
- ✅ Slack escalation on failures

---

## 🏗️ Architecture

### Three-Layer Orchestration

```
Layer 1: Dependency Analysis
  ├─ AWS: Independent (rotate first)
  ├─ Vault: Independent (rotate second)
  └─ GCP: Depends on Vault (rotate third)

Layer 2: Coordinated Rotation
  ├─ Execute in dependency order
  ├─ Backup credentials before rotation
  ├─ Validate after each step
  └─ Retry with exponential backoff

Layer 3: Fallback & Recovery
  ├─ On failure: Try 3 times (5s delay between)
  ├─ On persistent failure: Trigger rollback
  ├─ Restore from backup if available
  └─ Create incident issue for operator review
```

### Rotation Flow

```
START
  ↓
[AWS Rotation]
  ├─ Create new access key
  ├─ Update GitHub secret
  ├─ Delete old key
  ├─ Validate connectivity
  └─ On failure: Retry up to 3x, then skip
  ↓
[Vault Rotation]
  ├─ Request new token via AppRole
  ├─ Update GitHub secret
  ├─ Revoke old token
  ├─ Validate token validity
  └─ On failure: Retry up to 3x, skip if persistent
  ↓
[GCP Rotation]
  ├─ Create new service account key
  ├─ Update GitHub secret
  ├─ Delete old keys (30+ days)
  ├─ Validate GCP access
  └─ On failure: Retry up to 3x, trigger incident
  ↓
[Validation]
  ├─ Verify AWS connectivity (sts:GetCallerIdentity)
  ├─ Verify GCP access (gcloud auth list)
  ├─ Verify Vault token (vault token lookup)
  └─ Generate compliance report
  ↓
[Failure Handling]
  ├─ If all success: Complete with ✅
  ├─ If partial success: Create warning issue
  └─ If all fail: Trigger emergency procedures
  ↓
END
```

---

## 🔄 Components

### Primary Workflow
**File**: `.github/workflows/cross-cloud-credential-rotation.yml`

**Schedule**: Daily at 3 AM UTC (after GCP sync, before other operations)

**Modes**:
- `check` - Verify credential ages (default)
- `rotate` - Execute orchestrated rotation
- `emergency` - Force immediate rotation on all clouds

### Scripts

#### 1. Cross-Cloud Orchestrator
**File**: `scripts/automation/cross-cloud-credential-orchestrator.sh`

**Functions**:
- `get_*_credential_age()` - Calculate credential age
- `rotate_*_credentials()` - Rotate specific cloud
- `validate_rotated_credentials()` - Verify after rotation
- `generate_compliance_report()` - Audit trail

**Supported Clouds**: AWS | GCP | Vault

#### 2. Orchestration Engine
**File**: `scripts/automation/credential-orchestration-engine.sh`

**Functions**:
- `get_rotation_order()` - Dependency-aware sequencing
- `rotate_with_fallback()` - Execute with retries
- `execute_rotation_plan()` - Orchestrate full cycle
- `rollback_failed_rotations()` - Recover from failures
- `validate_orchestration()` - Final verification

---

## 🔐 Supported Credentials

### AWS
- **Credential**: IAM Access Keys
- **Max Age**: 90 days
- **Rotation By**: Creating new key, deleting old
- **Validation**: `aws sts get-caller-identity`

### GCP
- **Credential**: Service Account Keys
- **Max Age**: 30 days
- **Rotation By**: Creating new key, deleting old (30+ days)
- **Validation**: `gcloud auth list`

### Vault
- **Credential**: AppRole Auth Token
- **Max Age**: 168 hours (7 days)
- **Rotation By**: Requesting new token, revoking old
- **Validation**: `vault token lookup`

---

## 📊 Workflows & Triggers

### Scheduled Rotation (Daily)
```yaml
Trigger: 0 3 * * * (Daily at 3 AM UTC)
Execution Time: ~10-15 minutes
Operations:
  1. Authenticate to all three clouds (OIDC)
  2. Execute orchestration engine
  3. Validate all credentials
  4. Generate audit logs
  5. Post status to issue #1381
  6. Create incident issue if failures
```

### Manual Trigger (On-Demand)
```bash
# Check mode (default)
gh workflow run cross-cloud-credential-rotation.yml

# Rotate mode
gh workflow run cross-cloud-credential-rotation.yml -f mode=rotate

# Emergency (force all)
gh workflow run cross-cloud-credential-rotation.yml -f mode=emergency
```

---

## 🛡️ Failure Handling

### Retry Strategy (Per Service)
```
Attempt 1 → Fail → Wait 5s
Attempt 2 → Fail → Wait 5s
Attempt 3 → Fail → Escalate
```

### Escalation Actions
- ✅ Log detailed error
- ✅ Skip to next service (don't block)
- ✅ Create warning issue if multiple failures
- ✅ Send Slack notification
- ✅ Generate incident report

### Rollback Procedures
```
IF any rotation failed:
  1. Identify failed services
  2. Restore credentials from backup (if available)
  3. Re-validate restored credentials
  4. Create incident issue for operator review
  5. Trigger manual rotation workflow
```

---

## 📈 Compliance & Audit

### Compliance Report
Generated automatically after each rotation:
```
Cross-Cloud Credential Rotation Compliance Report
├─ AWS IAM Key Age: 0 days (Max: 90)
├─ GCP Service Account Age: 0 days (Max: 30)
├─ Vault Token Age: 0 hours (Max: 168)
├─ All Credentials Valid: ✅
└─ Rotation Status: SUCCESS
```

### Audit Trail
```
Timestamp       | Service | Action           | Status | Details
────────────────┼─────────┼──────────────────┼────────┼──────────
2026-03-08T03:* | AWS     | Create Key       | ✅     | key-123
2026-03-08T03:* | AWS     | Update Secret    | ✅     | gh-secret
2026-03-08T03:* | AWS     | Delete Old Key   | ✅     | old-key
2026-03-08T03:* | AWS     | Validate         | ✅     | sts-ok
2026-03-08T03:* | Vault   | Request Token    | ✅     | token-456
2026-03-08T03:* | Vault   | Update Secret    | ✅     | gh-secret
2026-03-08T03:* | Vault   | Revoke Old       | ✅     | old-token
2026-03-08T03:* | Vault   | Validate         | ✅     | lookup-ok
2026-03-08T03:* | GCP     | Create Key       | ✅     | key-789
2026-03-08T03:* | GCP     | Update Secret    | ✅     | gh-secret
2026-03-08T03:* | GCP     | Cleanup Old      | ✅     | 3 old keys
2026-03-08T03:* | GCP     | Validate         | ✅     | auth-ok
```

### Metrics Tracked
- Rotation frequency (daily)
- Service-specific success rates
- Average rotation time per cloud
- Failure recovery times
- Backup restore frequency

---

## 🔧 Configuration

### GitHub Secrets Required
```
# GCP
GCP_PROJECT_ID
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
GCP_WORKLOAD_IDENTITY_PROVIDER
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# AWS
AWS_ROLE_TO_ASSUME

# Vault
VAULT_ADDR
VAULT_ROLE_ID
VAULT_SECRET_ID

# Notifications
SLACK_WEBHOOK_ROTATION (optional)
```

### Environment Variables (Workflow)
```yaml
ROTATION_MODE: check|rotate|emergency
VAULT_ADDR: ${VAULT_ADDR}
GCP_PROJECT_ID: ${GCP_PROJECT_ID}
```

---

## 👤 Operator Procedures

### Daily Monitoring
1. Check issue #1381 for rotation status (auto-updates)
2. Review compliance report for age trending
3. Respond to any warning issues

### Manual Rotation Trigger
```bash
# Force immediate rotation (if needed)
gh workflow run cross-cloud-credential-rotation.yml -f mode=rotate
```

### Emergency Rotation (All Clouds)
```bash
# Rotate ALL credentials immediately
gh workflow run cross-cloud-credential-rotation.yml -f mode=emergency
```

### Credential Age Checks
```bash
# Check current status without rotating
gh workflow run cross-cloud-credential-rotation.yml -f mode=check
```

---

## 📊 Monitoring Dashboard

Issue #1381 auto-receives updates after each rotation:
```
✅ AWS Rotation: SUCCESS
   - New key created
   - Old key deleted
   - Validation: PASS

✅ Vault Rotation: SUCCESS
   - New token requested
   - Old token revoked
   - Validation: PASS

✅ GCP Rotation: SUCCESS
   - New key created
   - Old keys (1) deleted
   - Validation: PASS

Timestamp: 2026-03-08T03:00:00Z
Next Rotation: 2026-03-09T03:00:00Z
Status: ✅ ALL CREDENTIALS CURRENT
```

---

## 🆘 Troubleshooting

### Issue: "AWS rotation failed"
**Solution**:
```bash
# 1. Verify AWS credentials in GitHub
gh secret list | grep AWS

# 2. Test AWS access manually
aws sts get-caller-identity

# 3. Check IAM permissions for current user
# 4. Monitor workflow logs for details
gh run view --log (latest run)
```

### Issue: "GCP rotation failed"
**Solution**:
```bash
# 1. Verify GCP service account email
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# 2. Test GCP access
gcloud auth list

# 3. Check service account IAM permissions
gcloud iam service-accounts list

# 4. Monitor workflow logs
```

### Issue: "Vault token invalid"
**Solution**:
```bash
# 1. Verify Vault address
gh secret get VAULT_ADDR

# 2. Test Vault connectivity
vault status

# 3. Check AppRole credentials
# 4. Manually request new token:
vault write -field=token auth/approle/login \
  role_id=$VAULT_ROLE_ID secret_id=$VAULT_SECRET_ID

# 5. Update GitHub secret manually
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
```

---

## 📝 System Properties

| Property | Met | Details |
|----------|-----|---------|
| **Immutable** | ✅ | All logic in Git, no state files |
| **Ephemeral** | ✅ | State resets each rotation cycle |
| **Idempotent** | ✅ | Safe to re-run (creates new creds) |
| **No-Ops** | ✅ | Fully scheduled, no manual triggers |
| **Hands-Off** | ✅ | Setup only, then automatic |

---

## 📚 Related Documentation

- [GCP_GSM_INTEGRATION_GUIDE.md](GCP_GSM_INTEGRATION_GUIDE.md) - GSM sync details
- [GCP_GSM_QUICK_START.md](GCP_GSM_QUICK_START.md) - GCP setup
- [OPS_AUTOMATION_INFRASTRUCTURE.md](../architecture/OPS_AUTOMATION_INFRASTRUCTURE.md) - Overall automation

---

**Last Updated**: March 8, 2026  
**Maintained By**: GitHub Actions Automation  
**Status**: 🟢 Production Ready
