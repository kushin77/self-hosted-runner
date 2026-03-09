# Credential System Runbook
**Last Updated:** 2026-03-09  
**Audience:** Operations, On-Call, Emergency Response

---

## Table of Contents
1. [Normal Operations](#normal-operations)
2. [Monitoring & Alerts](#monitoring--alerts)
3. [Troubleshooting](#troubleshooting)
4. [Emergency Procedures](#emergency-procedures)
5. [Recovery Procedures](#recovery-procedures)

---

## Normal Operations

### Daily Health Check
```bash
./scripts/credential-monitoring.sh all
```

**Expected Output:**
- ✓ All 3 providers UP (GSM, Vault, KMS)
- ✓ Credential TTL > 30 minutes
- ✓ 100% success rate

### Manual Credential Rotation
```bash
./scripts/auto-credential-rotation.sh rotate
```

**When to use:**
- After operational incident
- Before major deployment
- After provider maintenance

### Verify Audit Integrity
```bash
python3 scripts/immutable-audit.py verify
```

**Expected:**
- ✓ Hash chain intact
- ✓ No broken entries

---

## Monitoring & Alerts

### Automated Schedules
| Schedule | Action | Alert Threshold |
|----------|--------|-----------------|
| Every 15 min | Credential refresh | N/A (non-blocking) |
| Every hour | Health check | All providers DOWN |
| Daily 2 AM | Full rotation | Any failure |
| Weekly Sun 1 AM | Compliance audit | Any drift |

### Alert Types

**🚨 CRITICAL (Escalate Immediately)**
- All credential providers DOWN
- Audit log integrity check FAILED
- Credential TTL < 5 minutes

**⚠️ WARNING (Investigate within 1 hour)**
- Single provider DOWN (failover active)
- Credential TTL < 30 minutes
- Health check latency > 30 seconds

**ℹ️ INFO (Log & Review)**
- Successful rotation
- Failover event (with auto-recovery)
- New credential version created

---

## Troubleshooting

### Issue: GSM Provider DOWN

**Symptoms:**
- `gsm_health: "down"` in monitoring output
- Error: "Failed to retrieve credential from GSM"

**Steps:**
1. Check GCP project access: `gcloud projects list`
2. Verify OIDC token valid: Check $ACTIONS_ID_TOKEN_REQUEST_URL
3. Check Vault & KMS status (should be UP for failover)
4. If still DOWN after 5 min → Escalate (see Emergency section)

**Resolution:**
```bash
# Force re-authentication
unset GOOGLE_APPLICATION_CREDENTIALS
export GCP_PROJECT_ID=<your-project>
./scripts/cred-helpers/enhanced-fetch-gsm.sh <project> test-key
```

### Issue: Vault Provider DOWN

**Symptoms:**
- `vault_health: "down"`
- Error: "Failed to authenticate to Vault"

**Steps:**
1. Check Vault URL reachable: `curl $VAULT_ADDR/v1/sys/health`
2. Verify JWT/OIDC token valid (if using): `echo $GITHUB_TOKEN`
3. Check AppRole credentials if configured
4. Verify network connectivity (no firewall blocks)

**Resolution:**
```bash
# Test Vault connectivity
curl -I $VAULT_ADDR/v1/sys/health

# Test authentication
export VAULT_ROLE=github-actions
./scripts/cred-helpers/enhanced-fetch-vault.sh secret/test
```

### Issue: KMS Provider DOWN

**Symptoms:**
- `kms_health: "down"`
- Error: "Failed to retrieve credentials from KMS"

**Steps:**
1. Verify AWS role assumption: `aws sts get-caller-identity`
2. Check OIDC provider trust: `aws iam list-open-id-connect-providers`
3. Verify IAM permissions on role
4. Check AWS credential expiration

**Resolution:**
```bash
# Test AWS credentials
aws sts get-caller-identity

# Test KMS access
aws kms list-keys

# Force re-authentication (GitHub Actions automatically handles this)
```

### Issue: Credential TTL Expired

**Symptoms:**
- `credential_ttl: "EXPIRED"`
- Jobs fail with "Unauthorized" errors

**Steps:**
1. Run immediate rotation: `./scripts/auto-credential-rotation.sh rotate`
2. Verify new credentials cached: `ls -la .credentials-cache/`
3. Re-run failed job

**Prevention:**
- Monitoring alerts when TTL < 30 min
- Automatic refresh every 15 min

---

## Emergency Procedures

### ALL Providers DOWN

**🚨 CRITICAL SCENARIO**

**Symptoms:**
- All 3 providers (GSM, Vault, KMS) reporting DOWN
- Workflow escalation issue auto-created
- Credentials cannot be retrieved

**Steps (Execute in Order):**

1. **Acknowledge:** Comment on GitHub escalation issue
2. **Assess:** Run full diagnostics
   ```bash
   ./scripts/credential-monitoring.sh all
   python3 scripts/immutable-audit.py verify
   ```

3. **Failover Check:**
   - Is primary (GSM) down? → Check GCP service status
   - Is secondary (Vault) down? → Check Vault service + network
   - Is tertiary (KMS) down? → Check AWS service + IAM

4. **If Network Issue:**
   ```bash
   ping google.com  # General connectivity
   curl -I $VAULT_ADDR  # Vault connectivity
   ```

5. **Contact Cloud Providers:**
   - GCP: https://status.cloud.google.com
   - HashiCorp: Check Vault support channel
   - AWS: https://health.aws.amazon.com

6. **Temporary Mitigation (< 1 hour):**
   ```bash
   # Use cached credentials if available
   cat .credentials-cache/*  # Show cached values
   
   # Manual export (LAST RESORT - requires audit log)
   export TEMPORARY_CREDENTIALS=$(cat .credentials-cache/backup)
   # Document in audit log!
   ```

7. **Escalation Path:**
   - 5 min no progress → Notify team lead
   - 15 min no progress → Page on-call manager
   - 30 min no progress → Initiate incident response

### Credential Compromise

**🚨 EMERGENCY RESPONSE**

**Symptoms:**
- Unused credential accessed from unknown source
- Audit log shows suspicious pattern
- Credential used outside normal operation window

**Immediate Actions:**
1. **REVOKE All Active Credentials**
   ```bash
   # Stop current jobs
   pkill -f credential-rotation
   
   # Invalidate all cached credentials
   rm -rf .credentials-cache/
   
   # Force full re-authentication on next cycle
   ```

2. **Audit Review**
   ```bash
   python3 scripts/immutable-audit.py verify
   grep "session_id" .audit-logs/*.jsonl | grep -v "known-session-id"
   ```

3. **Provider Rotation**
   ```bash
   # Rotate credentials in GSM/Vault/KMS
   # This varies by provider - contact platform team
   ```

4. **Notification**
   - Create GitHub issue: "SECURITY: Credential compromise - rotation in progress"
   - Notify security team
   - Document full timeline

5. **Recovery**
   ```bash
   ./scripts/auto-credential-rotation.sh rotate
   ./scripts/credential-monitoring.sh ttl
   ```

---

## Recovery Procedures

### After Provider Outage

**Timeline:**
1. **0-5 min:** Provider recovers, system detects via health check
2. **5-10 min:** Automatic escalation issue auto-closes
3. **10-15 min:** Next scheduled rotation refreshes all credentials
4. **15+:** System back to normal operation

**Verification:**
```bash
# Check all providers UP
./scripts/credential-monitoring.sh failover

# Verify audit trail intact
python3 scripts/immutable-audit.py verify

# Check recent operations
tail -20 .audit-logs/*.jsonl
```

### After Manual Intervention

**Always Document:**
1. What failed and when
2. Manual actions taken
3. Why automatic recovery didn't work
4. Preventive measures to avoid recurrence

**Update audit log:**
```bash
# Manual entry (for transparency)
python3 scripts/immutable-audit.py --operation "manual_recovery" \
    --status "success" --details "Provider X recovered after manual intervention"
```

---

## Quick Reference

| Scenario | Command | Expected Time |
|----------|---------|---|
| Health check | `./scripts/credential-monitoring.sh all` | < 30 sec |
| Credential rotation | `./scripts/auto-credential-rotation.sh rotate` | < 60 sec |
| Audit verification | `python3 scripts/immutable-audit.py verify` | < 10 sec |
| Full recovery (GSM down) | Varies by GCP | 5-15 min |
| Full recovery (all down) | Page on-call | 15-60 min |

---

## Contact & Escalation

**On-Call:** Check PagerDuty for current responder  
**Team Slack:** #infrastructure-oncall  
**Email:** infrastructure-team@company.com  
**Severity:** All credential issues are P0/SEV-1

---

**Last Review:** 2026-03-09  
**Next Review:** 2026-04-09
