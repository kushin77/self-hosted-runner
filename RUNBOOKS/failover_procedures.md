# NexusShield Failover Procedures Runbook
**Version:** 1.0 | **Effective Date:** March 11, 2026 | **Owner:** Platform Engineering

---

## 📋 Executive summary

This runbook documents procedures for detecting, responding to, and recovering from credential system failures in NexusShield production. The primary goal is **zero data loss** and **continuous job processing** during credential provider outages.

---

## 🏗️ System Architecture Reference

```
Primary Secret Manager: Google Secret Manager (GSM)
    ↓
Secondary Secret Manager: Vault KV v2 (fallback)
    ↓
Tertiary Secret Manager: AWS Secrets Manager (fallback)
    ↓
Fallback Source: Environment Variables (last resort)
```

Each level automatically engages if the previous level fails. No manual intervention required for failover.

---

## 🔴 CRITICAL: Failure Scenarios

### Scenario 1: Google Secret Manager (GSM) Unavailable

**Detection Thresholds:**
- GSM API response time > 10 seconds (3 consecutive requests)
- GSM return status code 503, 500, or 429 (rate limit)
- 5+ consecutive failed GSM requests

**Symptoms the system exhibits:**
- Increased credential fetch latency (>2 seconds)
- Debug logs show `credential_source=vault` (fallback engaged)
- Jobs continue processing without interruption
- Audit trail shows GSM→Vault source switch

**Automated Response (requires NO manual action):**
1. Flask app detects GSM failure (timeout or error)
2. Automatically falls back to Vault KV
3. Logs credential source switch in audit trail
4. Jobs continue processing via Vault secrets
5. Audit trail remains immutable throughout

**Manual Verification (After Detection):**
```bash
# Verify Vault fallback is active
curl -X GET https://vault.example.com/v1/secret/data/portal-mfa-secret \
  -H "X-Vault-Token: $(cat /run/secrets/vault-token)"

# Check recent audit trail for fallback evidence
tail -20 /opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl | \
  jq 'select(.credential_source == "vault")'

# Monitor error rate for elevation
curl -s http://localhost:8080/metrics | grep nexusshield_http_requests_total | tail -5
```

**Recovery (When GSM restored):**
1. Monitor credentials fetched from Vault
2. Confirm GSM API returning 200 OK status
3. No action needed—automatic return to GSM as primary
4. Audit logs will show source switch back to `gsm`

**Recovery Checklist:**
- [ ] Confirm GSM health via `gcloud secrets list`
- [ ] Verify Flask app metrics show error rate dropping
- [ ] Check audit trail for credential source normalization
- [ ] Run `test_credential_failover.sh` to validate full chain

---

### Scenario 2: Google Secret Manager + Vault Both Down

**Detection Thresholds:**
- Both GSM (503+) and Vault (503+) unavailable simultaneously
- 5+ consecutive failures on both APIs
- Credential fetch failure across both primary and secondary

**Symptoms the system exhibits:**
- Increased job failure rate (jobs fail if credential fetch fails)
- Debug logs show `credential_source=aws` or `credential_source=env`
- AWS Secrets Manager being queried as tertiary fallback
- Brief degradation in job processing (milliseconds, not minutes)

**Automated Response (requires NO manual action):**
1. Flask app detects GSM failure
2. Flask app detects Vault failure
3. Automatically fails over to AWS Secrets Manager
4. Jobs continue processing via AWS credentials
5. Sends alert to monitoring system (PagerDuty/etc if configured)
6. Audit trail shows GSM→Vault→AWS progression

**Manual Verification (During Both Outages):**
```bash
# Verify AWS fallback is active
aws secretsmanager get-secret-value \
  --secret-id portal-mfa-secret \
  --region us-east-1

# Check audit trail for AWS source entries
tail -20 /opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl | \
  jq 'select(.credential_source == "aws")'

# Monitor job processing via metrics
curl -s http://localhost:8080/metrics | grep "nexusshield_jobs_"
```

**Recovery (When Primary/Secondary Restored):**

**Priority 1: Restore GSM (Primary)**
```bash
# Verify GSM is healthy
gcloud secrets list --format="value(name,created)" | head -5

# If healthy, system will automatically switch back to GSM
# within 1 minute
```

**Priority 2: Restore Vault (If GSM Still Unavailable)**
```bash
# Verify Vault cluster health
vault status

# Unseal Vault if necessary
vault unseal

# If healthy, system will switch from AWS back to Vault
```

**Recovery Checklist (Full State Restoration):**
- [ ] GSM health verified via `gcloud secrets list`
- [ ] If GSM failed: Vault health verified via `vault status`
- [ ] If Vault failed: AWS access verified via `aws secretsmanager list-secrets`
- [ ] Audit trail normalized to primary (GSM) source
- [ ] Job error rate returned to baseline
- [ ] Incident ticket updated with resolution time

---

### Scenario 3: Vault KV v2 API Path Misconfiguration

**Detection Thresholds:**
- Vault returns 404 on secret path queries
- Vault API path expects `/v1/secret/data/` but Flask uses `/secret/`
- Configuration mismatch prevents Vault access even if healthy

**Symptoms the system exhibits:**
- GSM works fine, but if GSM fails, Vault fallback fails immediately
- Test failover script reports Vault unavailable
- Audit logs show repeated Vault 404 errors before AWS fallback

**Manual Fix:**
```bash
# Verify Vault secret engine is enabled at expected path
vault secrets list | grep secret/

# Should show:
# Path          Type       Accessor            Description
# secret/       kv         kv_abc123...        key/value secret engine

# If not enabled, enable it:
vault secrets enable -path=secret kv-v2

# Verify path format by testing direct access
vault kv get secret/portal-mfa-secret

# If successful, Vault is ready for fallback use
```

**Recovery Checklist:**
- [ ] Vault Sys Admin verifies `/v1/secret/data/` path enabled
- [ ] Manual `vault kv get` test passes
- [ ] Flask app configuration points to correct path
- [ ] Run `test_credential_failover.sh` to validate Vault fallback
- [ ] Update Vault runbook with correct paths

---

## 📊 Monitoring & Alert Rules

**Alert Rule: CredentialFallbackEngaged**
```yaml
- alert: CredentialFallbackEngaged
  expr: nexusshield_credential_source_switches_total > 0
  for: 5m
  annotations:
    summary: "NexusShield switched to credential fallback"
    description: "Primary GSM unavailable. System using {{ $labels.fallback_source }}."
    runbook_url: "https://docs.example.com/runbooks/failover_procedures.md"
```

**Alert Rule: MultipleCredentialSourcesFailing**
```yaml
- alert: MultipleCredentialSourcesFailing
  expr: |
    (nexusshield_credential_fetch_errors{source="gsm"} > 5) AND
    (nexusshield_credential_fetch_errors{source="vault"} > 5)
  for: 2m
  annotations:
    summary: "CRITICAL: Multiple credential sources failing"
    description: "Both GSM and Vault unavailable. System degraded."
    severity: "critical"
```

**Alert Rule: AuditTrailStalled**
```yaml
- alert: AuditTrailStalled
  expr: |
    time() - max(nexusshield_audit_trail_last_entry_timestamp_seconds) > 300
  for: 5m
  annotations:
    summary: "CRITICAL: Audit trail not recording events"
    description: "No audit entries for 5+ minutes. Immediate investigation required."
    severity: "critical"
```

---

## 🧪 Testing Procedures

### Pre-Production Testing (On Staging)

**Test 1: GSM Failure Simulation**
```bash
# SSH to staging host
ssh staging@host.example.com

# Add iptables rule to blackhole GSM
sudo iptables -A OUTPUT -p tcp --dport 8888 -j DROP

# Trigger migration job
curl -X POST http://localhost:8080/api/v1/migrate \
  -H "X-Admin-Key: admin-key-here" \
  -H "Content-Type: application/json" \
  -d '{"source":"s3://bucket","destination":"gs://bucket","dry_run":true}'

# Monitor audit trail for Vault source
tail -f /opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl | jq '.credentials_source'

# Remove iptables rule
sudo iptables -D OUTPUT -p tcp --dport 8888 -j DROP

# Verify recovery to GSM
sleep 10
tail -5 /opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl | jq '.credential_source'
# Should show "gsm" again
```

**Test 2: Full Failover Chain Validation**
```bash
# Run automated test script
./scripts/ops/test_credential_failover.sh staging@host.example.com

# Expected output:
# TEST 1 PASSED: Baseline operational
# TEST 2 PASSED: GSM→Vault fallback
# TEST 3 PASSED: Audit trail immutable
# TEST 4 PASSED: Credential source tracked
# TEST 5 PASSED: Jobs process continuously
# TEST 6 PASSED: System recovery validated
# ALL TESTS PASSED ✅
```

**Test 3: Vault Fallback Validation**
```bash
# Block both GSM and Vault simultaneously
sudo iptables -A OUTPUT -p tcp --dport 8888 -j DROP  # GSM
sudo iptables -A OUTPUT -p tcp --dport 8200 -j DROP  # Vault

# Trigger migration job
curl -X POST http://localhost:8080/api/v1/migrate ...

# Verify AWS fallback engaged
tail -5 /opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl | jq '.credential_source'
# Should show "aws"

# Cleanup
sudo iptables -D OUTPUT -p tcp --dport 8888 -j DROP
sudo iptables -D OUTPUT -p tcp --dport 8200 -j DROP
```

### Production Verification (Low-Risk)

**Monthly Failover Drill (Do NOT test during business hours)**
```bash
# 1. Schedule maintenance window: Tuesday 2-3 AM UTC
# 2. Notify on-call team of intentional test
# 3. Run: ./scripts/ops/test_credential_failover.sh localhost
# 4. Document results in incident ticket
# 5. Post-mortem if any tests fail
```

**Continuous Monitoring (Always Active)**
```bash
# Monitor credential_fetch_errors metric (should be ~0)
curl -s http://localhost:8080/metrics | grep credential_fetch_errors

# Monitor audit trail growth (should be ~1 entry per job)
tail -1 /opt/nexusshield/scripts/cloudrun/logs/portal-migrate-audit.jsonl

# Alert thresholds
# - WARNING: credential_fetch_errors > 5 in 5 minutes
# - CRITICAL: credential_fetch_errors > 10 in 1 minute
# - CRITICAL: audit_trail last_entry_timestamp > 5 minutes old
```

---

## 🛠️ Operational Procedures

### Immediate Response (First 5 Minutes)

**For GSM Outage Only:**
```bash
# 1. Verify GSM is actually down
gcloud secrets list

# 2. If unavailable, acknowledge in status page
# 3. Page on-call SRE if recovery ETA > 10 minutes
# 4. No further action needed—system auto-recovers
```

**For Multi-Provider Outage:**
```bash
# 1. CRITICAL: Page on-call team immediately
# 2. Declare SEV-1 incident in status page
# 3. Verify at least one credential source accessible:
gcloud secrets list      # GSM
vault status             # Vault
aws secretsmanager list-secrets # AWS

# 4. If ALL unavailable: HARD STOP—escalate to cloud provider support
```

### Short-Term Response (5-30 Minutes)

**Triage:**
1. Determine which credential sources are unavailable
2. Check cloud provider status pages (GCP, HashiCorp, AWS)
3. Review recent config changes or deployments
4. Verify network connectivity to credential services

**Escalation Matrix:**
- **GSM only down:** Assign to GCP team, ETA 10-30 min
- **Vault only down:** Check HashiCorp cluster, ETA 20-60 min
- **Multiple down:** Multi-team incident, declare SEV-1

### Long-Term Recovery (30+ Minutes)

**Root Cause Analysis:**
- [ ] Collect logs from credential service (GSM, Vault, AWS)
- [ ] Review Flask app error logs for fetch failures
- [ ] Check network connectivity and firewall rules
- [ ] Verify API authentication tokens valid

**Post-Incident:**
- [ ] Document what failed and why in incident ticket
- [ ] Update runbook with new findings
- [ ] Schedule post-mortem within 24 hours
- [ ] Implement preventive measures (alerts, monitoring)

---

## 📋 Credential Source Audit Trail

Every credential fetch is logged in the immutable audit trail with source information:

```json
{
  "timestamp": "2026-03-11T14:45:30.123Z",
  "event": "credential_fetched",
  "credential_name": "portal-mfa-secret",
  "credential_source": "gsm",  // or "vault", "aws", "env"
  "fetch_duration_ms": 145,
  "status": "success",
  "hash": "abc123...",
  "prev": "xyz789..."
}
```

**Source Priority (automatic fallback order):**
1. **gsm** — Google Secret Manager (primary, <100ms)
2. **vault** — Vault KV v2 (fallback, <200ms)
3. **aws** — AWS Secrets Manager (fallback, <500ms)
4. **env** — Environment Variables (last resort, <1ms)

**Operational Insight:**
- Normal operation: 99%+ of entries show `credential_source: "gsm"`
- If seeing frequent `"vault"` entries: GSM may be experiencing intermittent issues
- If seeing `"aws"` entries: Both GSM and Vault failing
- If seeing `"env"` entries: Critical—all cloud secrets unavailable

---

## ✅ Checklist: Pre-Production Deployment

Before deploying NexusShield to production, verify:

- [ ] All credential sources (GSM, Vault, AWS) accessible from production network
- [ ] Credential secrets pre-populated in all three systems (for redundancy)
- [ ] Flask app can authenticate to each system
- [ ] Audit trail directory writable and has sufficient disk space (10GB+ recommended)
- [ ] Systemd service configured to restart on failure
- [ ] Monitoring alerts configured (see Alert Rules section above)
- [ ] Runbook reviewed by ops team
- [ ] Failover test script passes on staging (`test_credential_failover.sh`)
- [ ] Team trained on failover procedures
- [ ] Incident escalation contacts configured
- [ ] Status page integration ready (for customer communication)

---

## 🚨 Emergency Contacts

**For GCP Services Issues:**
- Cloud Support: https://support.google.com/

**For Vault Issues:**
- HashiCorp Support: https://support.hashicorp.com/

**For AWS Services Issues:**
- AWS Support: https://console.aws.amazon.com/support/

**Internal Escalation:**
- On-Call SRE: `oncall@platform-eng.example.com` (PagerDuty)
- Platform Engineering Lead: `lead@platform-eng.example.com`

---

## 📝 Document Control

| Field | Value |
|-------|-------|
| **Document ID** | FAILOVER-001 |
| **Version** | 1.0 |
| **Authors** | GitHub Copilot, Platform Engineering |
| **Effective Date** | March 11, 2026 |
| **Last Updated** | March 11, 2026 |
| **Next Review** | April 11, 2026 |
| **Classification** | Internal – Operations Only |

**Change History:**
- **v1.0** (2026-03-11): Initial version—comprehensive failover procedures

---

## 🎓 Training & Knowledge

### For Operators
- Read: "Immediate Response (First 5 Minutes)" section
- Test: Run `./scripts/ops/test_credential_failover.sh` monthly
- Know: Which credential source is currently active (check audit trail)

### For Engineers
- Read: Full runbook (you're reading it!)
- Understand: "System Architecture Reference" section
- Review: Alert rules and monitoring thresholds
- Test: Failover scenarios on staging before production

### For Managers
- Know: Failover is automatic (no manual intervention)
- Understand: Data loss risk is zero (immutable audit trail)
- Monitor: Alert escalations and incident frequency
- Plan: Quarterly reviews to update runbook

---

**END OF RUNBOOK**

