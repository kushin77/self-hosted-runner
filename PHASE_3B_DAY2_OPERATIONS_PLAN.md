# Phase 3B: Day-2 Operations - Vault & GCP Compliance 

**Execution Date:** March 16, 2026 (24 hours post-Phase 3 deployment)  
**Status:** READY FOR STAGED EXECUTION  
**Model:** Hands-off automation with external coordination points  

---

## Overview

Phase 3B completes infrastructure hardening with two non-blocking operations:
- **#3125**: Vault AppRole restoration or recreation  
- **#3126**: GCP Cloud-Audit IAM group + compliance module activation  

Both operations are **optional** (credentials via GSM working fine) but **recommended** for production compliance.

---

## Pre-Execution Checklist (24 Hours Post-Phase 3)

- [ ] Phase 3 deployment completed successfully
- [ ] All 100+ nodes online and healthy (Grafana confirms)
- [ ] Immutable audit trails captured and archived
- [ ] NAS backup policy active (daily snapshots)
- [ ] Service account automation verified

---

## Task #3125: Vault AppRole Restoration/Recreation

**Issue:** https://github.com/kushin77/self-hosted-runner/issues/3125  
**Dependencies:** None (optional, non-blocking)  
**Priority:** Medium  
**Timeline:** ~15-30 minutes

### Prerequisites

**Option A: Original Vault Restore (If accessible)**
- Original Vault cluster URL or credentials
- Backup of original Vault configuration
- Network access to Vault

**Option B: New AppRole Creation (Local)**
- Local Vault running or deployable
- Vault root token available
- `vault` CLI installed

**Option C: Skip (Recommended if GSM working)**
- GSM credentials currently active and healthy
- This is a non-blocking enhancement

### Execution Flow

```bash
# OPTION A: Restore original Vault
bash scripts/ops/OPERATOR_VAULT_RESTORE.sh \
  --vault-server https://vault.example.com \
  --vault-token s.xxxxx

# OPTION B: Create new local AppRole
bash scripts/ops/OPERATOR_CREATE_NEW_APPROLE.sh \
  --vault-root-token s.xxxxx \
  --local-vault-port 8200

# OPTION C: Status check (no changes)
bash scripts/ops/OPERATOR_VAULT_RESTORE.sh \
  --status-check-only
```

### Acceptance Criteria

- ✅ AppRole validates on Vault instance
- ✅ Vault Agent authenticates successfully
- ✅ Health checks pass
- ✅ Immutable audit trail captures operation

### Success Indicators

```bash
# Verify Vault health
curl http://127.0.0.1:8200/v1/sys/health | jq .

# Verify AppRole
vault auth list | grep approle

# Verify Agent logs
sudo journalctl -u vault-agent -n 20
```

---

## Task #3126: GCP Cloud-Audit IAM Group & Compliance Module

**Issue:** https://github.com/kushin77/self-hosted-runner/issues/3126  
**Dependencies:** GCP organization admin coordination  
**Priority:** Low  
**Timeline:** ~30-60 minutes (including external coordination)

### Prerequisites

**Org Admin (External)**
- GCP Cloud Console access
- Permission to create IAM groups
- Cloud Audit logging configured

**Operator (You)**
- Terraform CLI installed
- gcloud CLI configured and authenticated
- Service account credentials available

### Execution Flow

**Step 1: Org Admin Creates IAM Group (External)**

1. Visit: https://console.cloud.google.com/iam-admin/groups
2. Create new group: `cloud-audit@nexusshield-prod.iam.gserviceaccount.com`
3. Add members (if required by org policy)
4. Notify operator (you) when complete

**Step 2: Operator Enables Compliance Module (Automated)**

```bash
bash scripts/ops/OPERATOR_ENABLE_COMPLIANCE_MODULE.sh \
  --gcp-project nexusshield-prod \
  --audit-group-name cloud-audit \
  --terraform-apply
```

**Step 3: Verification**

```bash
# Verify group exists
gcloud identity groups describe \
  cloud-audit@nexusshield-prod.iam.gserviceaccount.com

# Verify Terraform module deployed
terraform -chdir=infrastructure/compliance state list

# Verify audit logs flowing
gcloud logging read "resource.type=global" \
  --format="table(timestamp,severity,message)" \
  --limit=5
```

### Acceptance Criteria

- ✅ cloud-audit group exists in GCP
- ✅ Terraform compliance module deployed
- ✅ IAM audit bindings active
- ✅ Compliance logs flowing to Cloud Logging

### Success Indicators

```bash
# Org admin verification
# (Can be done in GCP Console)

# Operator verification
gcloud projects get-iam-policy nexusshield-prod \
  --flatten="bindings[].members" \
  --format='table(bindings.role)' \
  | grep cloud-audit

# Audit logging verification
gcloud logging read "protoPayload.methodName=~'.*iam.*'" \
  --limit=5 \
  --format=json
```

---

## Execution Sequence (Recommended)

### Timeline

| Time | Task | Status | Owner | Output |
|------|------|--------|-------|--------|
| T+0 (Day 1 02:00 UTC) | Phase 3 deployment | ✅ Autonomous | Systemd | 100+ nodes online |
| T+24h (Day 2 02:00 UTC) | Phase 3B eligibility check | MANUAL | You | Pre-flight validation |
| T+24h (Day 2 02:30 UTC) | Execute #3125 (Vault) | MANUAL | You | Vault configured |
| T+24h (Day 2 03:00 UTC) | Coordinate #3126 ext. step | MANUAL | Org Admin | IAM group created |
| T+24h (Day 2 04:00 UTC) | Execute #3126 (Compliance) | MANUAL | You | Terraform applied |
| T+72h (Day 4) | Production stability review | CHECK | You | Final sign-off |

### Option Flow (Pick One Path)

**Path A: Full Hardening (Recommended)**
1. Execute #3125 (Vault AppRole)
2. Coordinate #3126 with org admin & execute
3. Result: Complete compliance + credential federation

**Path B: Vault Only**
1. Execute #3125 (Vault AppRole)
2. Skip #3126 (GCP compliance non-blocking)
3. Result: Credential federation active

**Path C: GCP Only**
1. Skip #3125 (Vault optional)
2. Coordinate #3126 with org admin & execute
3. Result: Audit compliance active

**Path D: Skip Both (Minimum)**
1. Verify GSM credentials working
2. Defer Day-2 ops to later phase
3. Result: Core infrastructure complete

---

## Automation Scripts Available

### Vault Operations

**OPERATOR_VAULT_RESTORE.sh** (220 lines)
- Detects Vault server availability
- Restores AppRole configuration
- Validates health checks
- Generates audit trail

Usage:
```bash
bash scripts/ops/OPERATOR_VAULT_RESTORE.sh \
  --vault-server <URL> \
  --vault-token <TOKEN> \
  [--dry-run]
```

**OPERATOR_CREATE_NEW_APPROLE.sh** (180 lines)
- Creates new AppRole on local Vault
- Configures Vault Agent
- Enables auth method
- Tests authentication

Usage:
```bash
bash scripts/ops/OPERATOR_CREATE_NEW_APPROLE.sh \
  --vault-root-token <TOKEN> \
  [--approle-name automation] \
  [--local-vault-port 8200]
```

### GCP Compliance Operations

**OPERATOR_ENABLE_COMPLIANCE_MODULE.sh** (240 lines)
- Validates GCP project access
- Enables Cloud Audit logging
- Deploys Terraform compliance module
- Establishes IAM bindings

Usage:
```bash
bash scripts/ops/OPERATOR_ENABLE_COMPLIANCE_MODULE.sh \
  --gcp-project <PROJECT> \
  --audit-group-name <GROUP> \
  [--terraform-apply] \
  [--dry-run]
```

---

## Rollback Procedures

### If Vault Operation Fails

```bash
# View last operation
tail -100 logs/phase3b-operations/vault-transaction-*.jsonl | jq .

# Rollback Vault Agent config
bash scripts/ops/OPERATOR_VAULT_RESTORE.sh --rollback

# Verify GSM credentials still working
gcloud secrets versions access latest --secret="automation-service-account"
```

### If GCP Compliance Fails

```bash
# View last operation
tail -100 logs/phase3b-operations/gcp-transaction-*.jsonl | jq .

# Rollback Terraform
terraform -chdir=infrastructure/compliance destroy -auto-approve

# Verify no downtime (GSM + systemd still working)
sudo systemctl status phase3-deployment.service
```

---

## Monitoring & Observability

### Real-Time Monitoring

**Vault Health:**
```bash
watch -n 5 'curl -s http://127.0.0.1:8200/v1/sys/health | jq .'
```

**GCP Compliance:**
```bash
watch -n 5 'gcloud logging read "resource.type=global" --limit=3 --format=table'
```

**Audit Trails (Immutable):**
```bash
tail -f logs/phase3b-operations/*.jsonl | jq .
```

### Grafana Dashboards

Access: http://192.168.168.42:3000

Panels:
- Vault authentication count
- GCP audit event volume
- Compliance module status
- Error rates by operation

---

## Support & Escalation

### Vault Issues

**Contact:** ops-vault@company.com  
**Escalation:** Vault platform team  
**SLA:** 2 hours for P1 (auth broken)

**Troubleshooting:**
```bash
# Check Agent logs
sudo journalctl -u vault-agent -n 50

# Check network to Vault
nc -zv vault.example.com 8200

# Re-run with debug
DEBUG=true bash scripts/ops/OPERATOR_VAULT_RESTORE.sh ...
```

### GCP Compliance Issues

**Contact:** gcp-security@company.com  
**Escalation:** GCP compliance team  
**SLA:** 24 hours for non-P1

**Troubleshooting:**
```bash
# Check authentication
gcloud auth list

# Check project setup
gcloud projects describe nexusshield-prod

# Check Terraform state
terraform -chdir=infrastructure/compliance show
```

---

## Success Criteria (Post-Execution)

### Phase 3B Complete When:

- ✅ Phase 3 deployment stable for 24+ hours
- ✅ All nodes healthy in Grafana
- ✅ Immutable audit trails captured & archived
- ✅ #3125 executed OR deferred with documented reason
- ✅ #3126 executed OR skipped with documented reason
- ✅ Zero production incidents attributed to Day-2 ops
- ✅ All operations logged immutably in JSON format

### Production Sign-Off

After above criteria met:

```bash
# Create final summary
cat > PHASE_3B_EXECUTION_SUMMARY.md << SUMMARY
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Phase: 3B Day-2 Operations
Status: COMPLETE
Vault: [EXECUTED|SKIPPED|DEFERRED]
GCP: [EXECUTED|SKIPPED|DEFERRED]
Nodes Online: $(systemctl list-units | grep phase3 | wc -l)
Audit Entries: $(wc -l logs/phase3-deployment/*.jsonl | tail -1)
SUMMARY

# Commit
git add PHASE_3B_EXECUTION_SUMMARY.md
git commit -m "complete: Phase 3B Day-2 operations finalised"
git push origin main
```

---

## GitHub Issue Status

Upon successful execution, update GitHub issues:

```bash
# Close #3125 (if executed)
gh issue close 3125 \
  --comment "Phase 3B complete: Vault AppRole configured successfully"

# Close #3126 (if executed)  
gh issue close 3126 \
  --comment "Phase 3B complete: GCP Cloud-Audit group & compliance module deployed"

# Update EPIC #3130
gh issue comment 3130 \
  --body "Phase 3B: Day-2 operations complete. All 10 EPIC enhancements deployed and hardened."
```

---

## Next Phase: 3C (Production Ops)

After Phase 3B stabilizes:

**Scheduled Operations (Monthly):**
- Vault token rotation (#3127)
- GCP compliance audit report (#3128)
- Distributed node health scan (#3129)
- Backup validation & restore test (#3130)

**On-Demand Operations:**
- Node scaling (1→100+ workers)
- Credential refresh (automatic via automation)
- Incident response automation

---

**Document Version:** 3B-20260315  
**Status:** READY FOR EXECUTION  
**Framework:** Hands-off, audit-trail enabled, rollback-protected  
**Next Update:** Post-execution (March 17, 2026)  
