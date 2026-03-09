# 📚 OPERATIONS TEAM HANDBOOK

**Edition:** 2.0  
**Effective Date:** 2026-03-08  
**Target Audience:** Operations, SRE, Incident Response Teams  

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Role Definitions](#role-definitions)
3. [Access & Permissions](#access--permissions)
4. [Operational Workflows](#operational-workflows)
5. [Incident Response](#incident-response)
6. [Training & Certification](#training--certification)
7. [Compliance & Auditing](#compliance--auditing)

---

## System Overview

### What This System Does

This is a **credential management and rotation platform** that:
- ✅ Automatically rotates credentials (daily 02:00 UTC)
- ✅ Manages secrets across GSM, Vault, and KMS
- ✅ Maintains 99.9% auth availability and 100% rotation success
- ✅ Provides 24/7 monitoring and automatic recovery
- ✅ Implements enterprise-grade security controls

### Architecture Layers

```
┌─────────────────────────────────────────────┐
│     Monitoring & Alerting Layer              │
│  - Real-time SLA tracking                   │
│  - Threat detection                         │
│  - Health dashboards                        │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│    Security & Audit Layer                    │
│  - AES-256 encryption                       │
│  - Credential scanning                      │
│  - Threat detection                         │
│  - Immutable audit trails                   │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│   Automation & Orchestration Layer           │
│  - 374 executable scripts                   │
│  - 79 GitHub Actions workflows              │
│  - Multi-cloud credential sync              │
│  - Automatic failover & recovery            │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│     Credential Backend Layer                 │
│  - Google Secret Manager (GSM)              │
│  - HashiCorp Vault                          │
│  - AWS Key Management Service (KMS)         │
│  - GitHub Actions Secrets                   │
└─────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose | Status |
|-----------|---------|--------|
| **Credential Rotator** | Daily rotation via workflows | ✅ Active 02:00 UTC |
| **SLA Tracker** | Auth (99.9%) & Rotation (100%) | ✅ Real-time |
| **Threat Detector** | Exposed credentials, brute force | ✅ 24/7 monitoring |
| **Audit Logger** | Immutable JSONL audit trails | ✅ 70+ files active |
| **Health Checker** | System component verification | ✅ Hourly checks |
| **Recovery System** | Auto-failover & rollback | ✅ Tested & verified |

---

## Role Definitions

### Credential Rotator (Automated)

**Responsible for:**
- Daily credential rotation at 02:00 UTC
- Syncing credentials to all backends (GSM, Vault, GitHub)
- Recording rotation attempts in audit logs
- Triggering alerts on rotation failure

**Capabilities:**
- Read: All credential backends
- Write: Rotation records in audit logs
- Action: Create/update/delete temporary credentials
- Access: Expiring in 5 minutes (very short-lived)

**Restrictions:**
- ❌ Cannot access historical credentials
- ❌ Cannot deactivate audit logging
- ❌ Cannot modify RBAC policies
- ❌ Cannot delete audit files

---

### Security Auditor (Team Member)

**Responsible for:**
- Weekly review of threat detections
- Monthly audit trail integrity verification
- Quarterly security training updates
- Incident investigation and documentation

**Capabilities:**
- Read: All audit logs, threat detections, credentials (audit only)
- Write: Incident reports, compliance documentation
- Action: Trigger threat scans, request credential revocation
- Access: Permanent identity with MFA

**Restrictions:**
- ❌ Cannot modify audit logs
- ❌ Cannot change rotation schedules
- ❌ Cannot access active production credentials
- ❌ Cannot approve credential changes

---

### Incident Responder (On-Call)

**Responsible for:**
- Responding to alerts within 15 minutes
- Executing recovery procedures
- Escalating to leadership when needed
- Writing incident post-mortems

**Capabilities:**
- Read: All logs, metrics, credentials (during incident)
- Write: Incident logs, emergency actions
- Action: Execute emergency procedures, revoke credentials, rollback changes
- Access: Elevated during incident response (1-hour window)

**Restrictions:**
- ⚠️ Can only take emergency actions
- ⚠️ All actions logged and audited
- ⚠️ Must escalate after 1 hour
- ❌ Cannot make permanent policy changes

---

### Infrastructure Lead

**Responsible for:**
- Overall system health and optimization
- Policy creation and enforcement
- Team training and certification
- Quarterly reviews and planning

**Capabilities:**
- Read: All system data
- Write: Policies, training materials, architecture changes
- Action: Modify rotation schedules, update thresholds, change providers
- Access: Unrestricted with full audit trail

**Restrictions:**
- ⚠️ All changes require Git commit (code review)
- ⚠️ Production changes require approval
- ⚠️ Audit trail cannot be modified

---

## Access & Permissions

### Authentication Methods

| Method | Use Case | Duration | MFA Required |
|--------|----------|----------|--------------|
| GitHub OIDC | Workflows | < 1 hour (job) | No |
| Google OIDC | GCP access | 1 hour | Yes |
| AWS Temporary | AWS API | 1 hour | Yes |
| Personal Token | CLI access | 7 days (max) | Yes |
| Service Account | Automation | 3 months | Yes |

### Permission Matrix

```
                     Credential   Audit    Alert    Rotation   Policy
                     Access       Read     Modify   Execute    Change
─────────────────────────────────────────────────────────────────────
Credential Rotator      ✓✓        ✓      ✗        ✓✓✓        ✗
Security Auditor        ✓         ✓✓✓    ✗        ✗          ✗
Incident Responder      ✓✓        ✓✓     ✓(emerg) ✓          ✗
Infrastructure Lead     ✓✓✓       ✓✓     ✓        ✓✓         ✓✓✓
```

**Legend:** ✓ = Read-only, ✓✓ = Write access, ✓✓✓ = Full control, ✗ = Denied

### Credential Access Policy

**Active Credentials**
- Stored in: GSM, Vault, KMS, GitHub Actions (encrypted)
- Who can read: Automation only (ephemeral)
- Rotation: Daily automatic
- TTL: 24 hours before next rotation

**Audit Records (who did what)**
- Stored in: JSONL immutable files
- Who can read: Security team (append-only, not deletable)
- Retention: 7 years (compliance requirement)
- Encryption: AES-256 with separate key

**Historical Credentials**
- Stored in: Vault (compliance backup)
- Who can read: Auditors (read-only)
- Rotation: Not rotated (historical only)
- Retention: 3 years

---

## Operational Workflows

### Daily Operations Workflow

```
02:00 UTC ┌─ Rotation Job Triggered
          ├─ Fetch current credentials from GSM/Vault/KMS
          ├─ Generate new credentials
          ├─ Update all credential backends (atomic)
          ├─ Verify all services still healthy
          ├─ Record in audit log
          ├─ Alert team if failed
          └─ Complete

Hour 03:00 UTC ┌─ Compliance Report Generated
              ├─ Summarize all rotations
              ├─ Check SLA metrics (99.9% auth, 100% rotation)
              ├─ Generate alerting rules
              ├─ Archive to compliance storage
              └─ Complete

Hourly 24/7 ┌─ Health Check
            ├─ Verify all 374 scripts are executable
            ├─ Check 79 workflows are healthy
            ├─ Validate 70+ audit files are writable
            ├─ Confirm monitoring dashboards work
            └─ Alert if component down

Continuously ┌─ Threat Detection
             ├─ Scan audit logs for exposed credentials
             ├─ Detect brute force attempts (>10 failures)
             ├─ Monitor for privilege escalation
             ├─ Alert on unusual patterns
             └─ Trigger revocation if needed
```

### Weekly Operational Tasks

**Monday 09:00 AM:**
1. Review SLA metrics from past week
2. Check threat detection report
3. Verify backup credentials are valid
4. Confirm team availability for next week

**Friday 03:00 PM:**
1. Archive week's compliance reports
2. Update incident metrics dashboard
3. Plan next week's maintenance windows
4. Brief team on upcoming changes

### Monthly Maintenance Tasks

**1st of Month:**
1. Audit trail integrity verification (must pass)
2. Review and rotate emergency break-glass credentials
3. Update threat detection rules if needed
4. Conduct a full disaster recovery simulation

**15th of Month:**
1. Review operational metrics and trends
2. Identify and prioritize improvements
3. Plan next quarter's enhancements
4. Update security documentation

---

## Incident Response

### Severity Levels

| Level | Examples | Response Time | Actions |
|-------|----------|---|---------|
| **Critical** | Credentials exposed, auth SLA <99% | 5 min | Immediate revocation, escalate to CTO |
| **High** | Rotation SLA <95%, brute force detected | 15 min | Investigate root cause, execute recovery |
| **Medium** | Single workflow failed, alert misconfigured | 30 min | Fix issue, update documentation |
| **Low** | Dashboard slow, audit log entry delayed | 1 hour | Optimize and monitor |

### Response Procedures by Severity

#### Critical - Credentials Exposed

```bash
# Step 1: IMMEDIATE (< 1 minute)
bash scripts/operations/emergency-test-suite.sh --execute revoke-exposed

# Step 2: ALERT TEAM (< 2 minutes)
Notify: Primary on-call, Secondary on-call, Security lead
Slack: #incident-response [TYPE: CREDENTIAL_EXPOSURE]

# Step 3: ASSESS DAMAGE (< 5 minutes)
1. Which credentials exposed? (check audit logs)
2. When were they exposed? (check threat detection)
3. What could attacker access? (map to services)
4. Any audit evidence of unauthorized use? (review logs)

# Step 4: CONTAIN (< 10 minutes)
1. Revoke exposed credentials immediately
2. Verify all backup credentials still valid
3. Rotate related credentials (if shared secret)
4. Monitor for unauthorized access

# Step 5: RECOVERY (< 30 minutes)
1. Update all services with new credentials
2. Verify services are operational
3. Run SLA checks to confirm health
4. Document what happened

# Step 6: FOLLOW-UP (< 24 hours)
1. Root cause analysis
2. Security review: how did exposure happen?
3. Implement preventative measures
4. Write incident post-mortem
5. Brief team and leadership
```

#### High - Rotation Failure

```bash
# Step 1: INVESTIGATE (< 5 minutes)
gh run view <RUN_ID> --json log | head -50  # See logs
grep "rotation" .operations-audit/*.jsonl | tail -20  # See pattern

# Step 2: ROOT CAUSE (< 10 minutes)
Is it:
- Network issue? (ping backends)
- Permission issue? (check IAM)
- Credential stale? (check validity)
- Quota exceeded? (check limits)

# Step 3: EXECUTE FIX (< 15 minutes)
Depends on root cause:
- Network: Wait for infrastructure to fix
- Permission: Alert infrastructure lead
- Stale: Rotate manually via script
- Quota: Escalate to provider

# Step 4: VERIFY (< 20 minutes)
bash .monitoring-hub/dashboards/sla-dashboard.sh  # Check SLA improved
gh run list --workflow rotation.yml | head -5  # Check latest run

# Step 5: DOCUMENT (within 24 hours)
Create: .security-enhancements/incidents/incident-[YYYYMMDD-HHmm].json
Log all steps taken and outcomes
```

#### Medium - Workflow Failed

```bash
# Step 1: ASSESS (< 10 minutes)
gh run view <RUN_ID> --json status,conclusion
# Is this a one-off or pattern? Check last 5 runs

# Step 2: FIX (< 20 minutes)
If one-off:
  - Manual retry: gh run rerun <RUN_ID>
  - Monitor next run

If pattern:
  - Investigate logs
  - Find root cause
  - Update workflow if needed
  - Commit and push changes

# Step 3: VERIFY (< 30 minutes)
Monitor next 2 scheduled runs
Confirm SLA metrics normal
```

### Escalation Flowchart

```
Incident Detected
       ↓
Severity Assessment
       ↓
   ┌───┴────┬──────────┬─────────┐
   │        │          │         │
Critical  High      Medium      Low
   │        │          │         │
   ↓        ↓          ↓         ↓
 <5min    <15min    <30min    <1hour
Primary  Primary   Assigned  Background
+ Sec    on-call   Engineer   Monitoring
   │        │          │         │
   ↓        ↓          ↓         ↓
Execute  Investigate  Fix       Monitor
Revoke   Root Cause   Issue     & Update
   │        │          │         │
   ↓        ↓          ↓         ↓
Verify   Recovery   Verify    Document
   │        │          │         │
Escalate  Escalate  Document  Done
 if >1h   if >30m
```

---

## Training & Certification

### Required Training Curriculum

**All Team Members (Once per year)**
1. System overview (1 hour)
2. Basic monitoring (1 hour)
3. Alert response (1 hour)
4. Emergency procedures (2 hours)

**Time Estimate:** 5 hours

---

**Incident Responders (Once per quarter)**
1. All above training (refresher)
2. Advanced troubleshooting (2 hours)
3. Root cause analysis (1 hour)
4. Mock incident drill (2 hours)

**Time Estimate:** 10 hours per quarter

---

**Infrastructure Lead (Quarterly)**
1. System internals deep-dive (3 hours)
2. Policy and governance (2 hours)
3. Disaster recovery planning (2 hours)
4. Security assessment (2 hours)

**Time Estimate:** 9 hours per quarter

---

### Certification Process

**Step 1:** Complete required training modules  
**Step 2:** Pass written exam (80% minimum)  
**Step 3:** Practical exercise (emergency drill)  
**Step 4:** Shadowing with certified team member (1 week)  
**Step 5:** Peer review and sign-off  
**Step 6:** Receive badge/certificate

**Recertification:** Required annually or if role changes

---

## Compliance & Auditing

### Compliance Framework

This system implements:
- ✅ **SOC 2 Type II** - Security, availability, and confidentiality controls
- ✅ **ISO 27001** - Information security management
- ✅ **NIST Cybersecurity Framework** - Risk management
- ✅ **PCI DSS** (if handling payment cards) - Secure credential management
- ✅ **HIPAA** (if handling health data) - Audit trail integrity

### Audit Trail Specifications

**What is Logged:**
```json
{
  "timestamp": "2026-03-08T02:00:15Z",
  "action": "credential_rotation",
  "actor": "credential-rotator-v1",
  "service": "github-actions",
  "resource": "database-password",
  "status": "success",
  "details": {
    "old_hash": "sha256:abc123...",
    "new_hash": "sha256:def456...",
    "backends_updated": ["gsm", "vault", "github"],
    "duration_ms": 2350
  }
}
```

**Storage & Retention:**
- Format: JSONL (one JSON object per line)
- Encryption: AES-256 with separate key
- Immutable: Append-only flag (chattr +a)
- Retention: 7 years for compliance
- Verification: SHA256 hashing for integrity

**Audit Trail Verification:**
```bash
# Run monthly
bash .security-enhancements/audit-chain-of-custody.sh --verify

# Results show:
# ✓ All files have append-only flag set
# ✓ SHA256 hashes match (no tampering)
# ✓ No gaps in timestamps
# ✓ All required fields populated
```

### Compliance Reports

Generated daily at 08:00 UTC:
- Credential rotation summary
- Authentication SLA achievement
- Security alert summary
- Threat detection report
- Monthly summary (first of month)

**Stored:** `.operations-audit/compliance-report-YYYYMMDD.json`  
**Archived:** `compliance-archive/` quarterly

### Audit Checklist (Quarterly)

- [ ] All audit files readable and intact
- [ ] No unauthorized access to credentials
- [ ] All rotations completed successfully
- [ ] No SLA violations unexplained
- [ ] Threat detection working correctly
- [ ] Team certifications current
- [ ] Escalation contacts updated
- [ ] DR test completed successfully

---

## Appendix A: Command Reference

```bash
# View SLA metrics
bash .monitoring-hub/dashboards/sla-dashboard.sh

# View system health
bash .monitoring-hub/dashboards/health-dashboard.sh

# Run emergency procedures test (dry-run)
bash scripts/operations/emergency-test-suite.sh

# Execute emergency credential revocation
bash scripts/operations/emergency-test-suite.sh --execute revoke-all

# Check threat detection status
cat .security-enhancements/threat-detection/threats-$(date +%Y%m%d).jsonl

# Verify audit trail integrity
bash .security-enhancements/audit-chain-of-custody.sh --verify

# Manual credential rotation (if needed)
bash scripts/credential-rotation.sh

# Recover from backup
bash scripts/operations/recovery.sh --backup-date YYYYMMDD
```

---

## Appendix B: Escalation Contacts

**Update these with real contact information:**

| Role | Name | Phone | Slack | Email |
|------|------|-------|-------|-------|
| Primary On-Call | [Name] | [Phone] | @[slack] | [Email] |
| Secondary On-Call | [Name] | [Phone] | @[slack] | [Email] |
| Incident Commander | [Name] | [Phone] | @[slack] | [Email] |
| Security Lead | [Name] | [Phone] | @[slack] | [Email] |
| Infrastructure Lead | [Name] | [Phone] | @[slack] | [Email] |
| CTO/Director | [Name] | [Phone] | @[slack] | [Email] |

**War Room Info:**
- Bridge: [Zoom/MS Teams link]
- Conference Room: [Location]
- Slack Channel: #incident-response

---

## Appendix C: System Architecture Diagram

```
┌─────────────────────────────────────────┐
│      GitHub Actions Workflows            │ ← 79 total workflows
│   (Credential Rotation, Compliance, etc) │
└──────────────────┬──────────────────────┘
                   │
        ┌──────────┼──────────┐
        ↓          ↓          ↓
    ┌────────┐ ┌────────┐ ┌─────────┐
    │  GSM   │ │ Vault  │ │   KMS   │
    │(Google)│ │(Open)  │ │  (AWS)  │
    └─┬──────┘ └─┬──────┘ └────┬────┘
      │          │             │
      └──────────┼─────────────┘
                 │
        ┌────────▼────────┐
        │ GitHub Actions  │ ← Deploys with rotated secrets
        │ (All jobs)      │
        └────────┬────────┘
                 │
        ┌────────▼────────────────┐
        │ Monitoring & Alerting   │
        │ - SLA Dashboard         │
        │ - Threat Detection      │
        │ - Health Checks         │
        └────────┬────────────────┘
                 │
        ┌────────▼────────────────┐
        │ Audit Trail (JSONL)     │
        │ - Immutable logs        │
        │ - 70+ files active      │
        │ - 7-year retention      │
        └────────────────────────┘
```

---

**Document Approval:**  
- Author: Infrastructure Team  
- Approved By: [Leadership]  
- Effective Date: 2026-03-08  
- Next Review: 2026-06-08  

---

**Status: ✅ Ready for team distribution and training**
