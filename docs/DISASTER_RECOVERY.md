# Disaster Recovery Guide - Credential System
**Last Updated:** 2026-03-09  
**Classification:** Internal - Operations Only  
**RTO/RPO:** 5 minutes / 0 minutes (immutable logs)

---

## Table of Contents
1. [Recovery Time Objectives (RTO/RPO)](#recovery-time-objectives)
2. [Failure Modes & Responses](#failure-modes--responses)
3. [Backup Strategies](#backup-strategies)
4. [Recovery Scenarios](#recovery-scenarios)
5. [Pre-Incident Checklist](#pre-incident-checklist)

---

## Recovery Time Objectives

### RTO (Recovery Time Objective)
- **GSM Only DOWN:** 5 minutes (automatic failover to Vault)
- **Vault Only DOWN:** 5 minutes (automatic failover to KMS)
- **KMS Only DOWN:** No impact (GSM primary, Vault secondary both up)
- **2 Providers DOWN:** 15 minutes (manual intervention required)
- **All 3 DOWN:** 60 minutes (incident response)

### RPO (Recovery Point Objective)
- **Zero-minute RPO:** All operations logged immutably (no data loss)
- **Audit Trail:** 365+ days retained
- **Credential Snapshots:** Every 15 minutes (rotation cycle)
- **Failed Operations:** Traceable via audit log with exact timestamp

---

## Failure Modes & Responses

### Mode 1: Single Provider Failure

**Automatic Response:**
- Health check detects failure (15-min rotation cycle)
- Failover chain activates: GSM → Vault → KMS
- No escalation (automatic recovery)
- No alert (system operates normally)

**Manual Verification:**
```bash
./scripts/credential-monitoring.sh failover
# Expected: "Primary (GSM): DOWN, Failover: ACTIVE (using Vault)"
```

**Success Condition:** Same credentials available via failover provider

---

### Mode 2: Two Providers Failure (GSM + Vault DOWN, KMS UP)

**Automatic Response:**
- Health check detects both DOWN at 15-min cycle
- Failover chain: GSM → Vault (both fail) → KMS (succeeds)
- ⚠️ **Single point of failure now active**

**Manual Actions Required:**
1. Investigate primary provider (GSM)
   - Check GCP service status
   - Verify IAM permissions
   - Check network connectivity

2. Investigate secondary provider (Vault)
   - Check Vault service health
   - Verify authentication tokens
   - Check capacity/rate limits

3. Escalate if no recovery within 10 minutes

**Success Condition:** At least one of GSM or Vault recovers

---

### Mode 3: All Three Providers DOWN

**🚨 CRITICAL INCIDENT - SEV-1**

**Automatic Response:**
- Health check fails at 15-min cycle
- Hourly health check at +60 min detects sustained failure
- **Auto-escalation: GitHub issue created** (incident #XXXX)
- Auto-escalation mentions: @oncall, @infrastructure-team

**Manual Actions Required (Immediate):**

1. **Acknowledge incident:**
   ```bash
   # Comment on auto-created issue
   # Example: "Starting investigation: GSM/Vault/KMS all down"
   ```

2. **Assess root cause:**
   ```bash
   # Check service status pages
   curl https://status.cloud.google.com/  # GCP
   # (Vault status varies by deployment)
   curl https://health.aws.amazon.com/  # AWS
   
   # Test connectivity to each provider
   curl -I $VAULT_ADDR
   aws sts get-caller-identity
   gcloud projects list
   ```

3. **Determine failure scope:**
   - **Cloud provider issue?** → Wait for provider recovery, coordinate with platform teams
   - **Network issue?** → Restore network connectivity, test each provider
   - **Credential issue?** → Rotate credentials, test re-authentication
   - **Local issue?** → Restart workflow, check runner health

4. **Mitigation (15-minute window):**
   - Use last-known-good credentials from cache
   - Run fewer/smaller jobs to extend TTL
   - Manually trigger rotation once any provider recovers

5. **Recovery (Once Provider Recovers):**
   ```bash
   # Automatic: Next 15-min rotation cycle
   # Manual: Trigger immediate rotation
   ./scripts/auto-credential-rotation.sh rotate
   
   # Verify
   ./scripts/credential-monitoring.sh all
   ```

6. **Close Incident:**
   - Automatic: Escalation issue auto-closes when health check passes
   - Manual: Once all providers UP, comment "Incident resolved" on tracking issue

---

### Mode 4: Credential Cache Corrupted

**Symptoms:**
- Cache validation fails
- Credential retrieval timeouts
- Hash mismatches between cache versions

**Recovery:**
```bash
# Clear corrupted cache
rm -rf .credentials-cache/

# Force immediate re-fetch
./scripts/cred-helpers/enhanced-fetch-gsm.sh <project> <key>
./scripts/cred-helpers/enhanced-fetch-vault.sh secret/path

# Verify
ls -la .credentials-cache/
```

**Audit Trail:** All fetch attempts logged with success/failure

---

### Mode 5: Audit Log Corruption

**Symptoms:**
- `immutable-audit.py verify` fails
- Hash chain broken at entry N
- JSON parse errors in log file

**Recovery:**
```bash
# Verify integrity
python3 scripts/immutable-audit.py verify
# Output: "Hash chain broken at entry 1234"

# Backup corrupted log
mv .audit-logs/audit-YYYYMMDD.jsonl .audit-logs/audit-YYYYMMDD.jsonl.corrupt

# Restart logging
# Next operation automatically creates new log file
python3 scripts/immutable-audit.py --operation "audit_recovery" \
    --status "success" --details "Corrupted log backed up, fresh log started"
```

**Immutability Guarantee:** Corrupted entries remain in `.corrupt` backup indefinitely

---

## Backup Strategies

### Automatic Backups
```bash
# Workflow: .github/workflows/auto-credential-rotation.yml
- Uploads audit logs to GitHub Actions Artifacts
- Retention: 30 days (configurable)
- Compression: gzip
- Scope: Full audit trail + health check logs
```

### Manual Backup
```bash
# Create on-demand backup
tar -czf audit-backup-$(date +%Y%m%d-%H%M%S).tar.gz .audit-logs/
tar -czf cache-backup-$(date +%Y%m%d-%H%M%S).tar.gz .credentials-cache/

# Upload to secure location (S3, GCS, Vault, etc.)
aws s3 cp audit-backup-*.tar.gz s3://company-backups/credentials/
```

### External Verification
```bash
# Download audit logs from GitHub Artifacts
# Verify hash chain integrity
python3 scripts/immutable-audit.py verify < downloaded-audit.jsonl

# Compare with running system
diff <(python3 scripts/immutable-audit.py verify) \
     <(unzip -p credential-artifacts.zip audit-log.jsonl | \
       python3 scripts/immutable-audit.py verify)
```

---

## Recovery Scenarios

### Scenario 1: GCP GSM Service Outage (2+ hours)

**Timeline:**
- T+0: GSM down, failover to Vault (automatic)
- T+5: Monitoring detects GSM down (non-critical, failover active)
- T+15: Vault handling all credential requests
- T+60: Daily breach check (escalates if GSM still down + Vault at limit)
- T+120: GCP restores service
- T+135: Next rotation cycle re-enables GSM
- T+150: System returns to full redundancy

**Actions:**
- Monitor Vault capacity (not designed for sustained load)
- If Vault nearing capacity: pre-rotate credentials to KMS
- Document timeline in incident post-mortem
- Update runbook with GSM outage procedures

### Scenario 2: Complete Network Isolation (5-10 minutes)

**Symptoms:**
- All three providers unreachable
- Network connectivity test fails
- No outbound HTTP/HTTPS

**Recovery:**
```bash
# Check connectivity
ping 8.8.8.8  # Google public DNS
ping 1.1.1.1  # Cloudflare public DNS
curl -I https://google.com  # HTTP connectivity

# If partial connectivity
# (e.g., GCP reachable but Vault not)
# Automatic failover still works - use available provider
```

**Expected:** 5-10 minute outage, then automatic recovery

### Scenario 3: Credential Rotation Loop (Infinite Failures)

**Symptoms:**
- Rotation keeps failing every 15 minutes
- Error: "Max retries exceeded"
- All providers responding but rejecting credentials

**Root Cause Analysis:**
```bash
# Check recent audit log entries
tail -50 .audit-logs/*.jsonl | grep "rotation"

# Check auth failure pattern
grep "authentication_failed" .audit-logs/*.jsonl | wc -l

# If > 10 failures in last hour:
# → Credential refresh likely needed
# → Contact platform team for credential reset
```

**Recovery:**
1. Stop automatic rotation (prevents log spam)
   ```bash
   # Disable in GitHub Actions by commenting out schedule
   # .github/workflows/auto-credential-rotation.yml
   ```

2. Manually reset credentials
   ```bash
   # Platform-specific:
   # - GSM: Regenerate service account key
   # - Vault: Create new role + token
   # - KMS: Regenerate IAM role credentials
   ```

3. Re-enable rotation
   ```bash
   git checkout .github/workflows/auto-credential-rotation.yml
   git push
   ```

---

## Pre-Incident Checklist

### Weekly (Every Monday 9 AM)
- [ ] Run full health check: `./scripts/credential-monitoring.sh all`
- [ ] Verify audit trail: `python3 scripts/immutable-audit.py verify`
- [ ] Test manual rotation: `./scripts/auto-credential-rotation.sh rotate`
- [ ] Check backup files: `ls -la audit-backup-*.tar.gz` (remove if > 7 days old)
- [ ] Review escalation issues (should be auto-closed)

### Monthly (First Monday of Month)
- [ ] Full drill: Simulate single provider outage
  ```bash
  VAULT_ADDR="http://invalid" ./scripts/credential-monitoring.sh failover
  # Should show: "Primary DOWN, Failover: ACTIVE (using KMS)"
  ```
- [ ] Full drill: Simulate all providers down
  ```bash
  # Create mock down scenario in test environment
  # Verify escalation issue auto-created and auto-closed
  ```
- [ ] Audit log rotation check (verify old logs archived)
- [ ] Update this runbook with lessons learned
- [ ] Review and approve any credential changes

### Quarterly (First Monday of Quarter)
- [ ] Full incident simulation exercise
- [ ] Validate RTO/RPO metrics
- [ ] Review and update contact list
- [ ] Test backup restoration
- [ ] Update disaster recovery documentation

---

## Incident Post-Mortem Template

**Use after any SEV-1 incident:**

```markdown
## Incident Post-Mortem
**Date:** YYYY-MM-DD  
**Duration:** HH:MM (start time - end time)  
**RTO Met?** YES / NO  
**Data Loss?** YES (none) / NO  

### Timeline
- T+0: [What happened]
- T+X: [What we detected]
- T+Y: [What we did]
- T+Z: [System recovered]

### Root Cause
[1-2 sentences explaining why]

### Immediate Actions Taken
- [Action 1]
- [Action 2]

### Follow-Up Actions (To prevent recurrence)
- [ ] [Action] - Owner: [Name] - Due: [Date]
- [ ] [Action] - Owner: [Name] - Due: [Date]

### Monitoring Improvements
- [ ] Add alert for [condition]
- [ ] Increase health check frequency to [interval]
- [ ] Update runbook section [name]
```

---

## Contact & Resources

**On-Call Infrastructure Team:** [PagerDuty Link]  
**Incident Channel:** #incidents-sec on Slack  
**Cloud Provider Status:**
- GCP: https://status.cloud.google.com
- AWS: https://health.aws.amazon.com
- HashiCorp (Vault): Check with platform teams

**Escalation Path:**
1. On-call engineer (first 15 min)
2. Infrastructure team lead (if not resolved by 15 min)
3. VP Infrastructure (if not resolved by 30 min)
4. CTO/CISO (if SEV-0, total data loss)

---

**Version:** 1.0  
**Last Updated:** 2026-03-09  
**Next Review:** 2026-04-09
