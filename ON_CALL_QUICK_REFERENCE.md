# 🚨 ON-CALL QUICK REFERENCE
**Credential Management System - Rapid Troubleshooting Guide**

---

## ✅ System Status Check
```bash
./scripts/credential-monitoring.sh all
```
**Expected:** All 3 providers UP (GSM, Vault, KMS) ✓

---

## 📋 Common Issues

### ❌ GSM Provider DOWN
1. Run: `curl -I https://cloudresourcemanager.googleapis.com/`
2. Check GCP status: https://status.cloud.google.com
3. Verify IAM: `gcloud projects get-iam-policy <PROJECT>`
4. **Auto-failover to Vault** (should work automatically)
5. **If still down:** Escalate to @platform-team

### ❌ Vault Provider DOWN
1. Run: `curl -I $VAULT_ADDR/v1/sys/health`
2. Check network connectivity
3. Verify JWT token: `echo $GITHUB_TOKEN`
4. **Auto-failover to KMS** (should work automatically)
5. **If still down:** Escalate to @vault-admins

### ❌ KMS Provider DOWN
1. Check AWS: `aws sts get-caller-identity`
2. Verify OIDC: `aws iam list-open-id-connect-providers`
3. **Last provider - CRITICAL**
4. **Immediate action:** Escalate to @aws-platform

### ❌ ALL 3 DOWN (SEV-1)
```bash
./scripts/credential-monitoring.sh failover
# Should show which providers are down

# Verify audit logs intact
python3 scripts/immutable-audit.py verify

# Start recovery
./scripts/auto-credential-rotation.sh rotate
```
**Escalation:** Page on-call manager immediately

---

## 🕐 Rotation Status
```bash
tail -20 .audit-logs/audit-*.jsonl | grep '"operation":"credential_rotation"'
```

---

## 📊 Monitoring Commands
| Command | Purpose |
|---------|---------|
| `./scripts/credential-monitoring.sh all` | Full health check |
| `./scripts/credential-monitoring.sh ttl` | Check TTL remaining |
| `./scripts/credential-monitoring.sh failover` | Failover chain status |
| `./scripts/credential-monitoring.sh usage` | Credential usage patterns |

---

## 💾 Audit Trail
```bash
# Query last failures
grep '"status":"failure"' .audit-logs/*.jsonl | tail -5

# Check provider health timeline
grep '"operation":"health_check"' .audit-logs/*.jsonl | jq '.{timestamp, provider, status}'

# Verify hash chain integrity
python3 scripts/immutable-audit.py verify
```

---

## 🚨 EMERGENCY (No Credentials Available)

**Last Resort: Cached Credentials**
```bash
ls -la .credentials-cache/
cat .credentials-cache/* | head -20  # Show cached creds
```

**If cache empty:**
1. All providers down + cache empty = MAJOR INCIDENT
2. Page CEO/CTO immediately
3. Activate vendor emergency contact
4. Document everything in audit log

---

## 📞 Escalation Paths

| Time | Action |
|------|--------|
| 0-5 min | Check monitoring, run diagnostics |
| 5-15 min | Escalate to on-call engineer |
| 15+ min | Escalate to infrastructure lead |
| 30+ min | Page VP Infrastructure |
| 60+ min | Page CTO/CISO |

---

## 📚 Full Documentation

- **Operations:** [docs/CREDENTIAL_RUNBOOK.md](docs/CREDENTIAL_RUNBOOK.md)
- **Disasters:** [docs/DISASTER_RECOVERY.md](docs/DISASTER_RECOVERY.md)
- **Compliance:** [docs/AUDIT_TRAIL_GUIDE.md](docs/AUDIT_TRAIL_GUIDE.md)
- **Index:** [docs/INDEX.md](docs/INDEX.md)

---

**Rotation Cycle:** Every 15 minutes (automatic)  
**Health Checks:** Every hour (automatic)  
**TTL:** All credentials <60 minutes  
**Retention:** 365+ days (immutable logs)

---
