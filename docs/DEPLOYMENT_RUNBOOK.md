# Hands-Off Secret Management System — Deployment Runbook

**Status:** ✅ PRODUCTION LIVE | **Date:** 2026-03-11 | **Version:** 1.0

## Executive Summary

A complete FAANG-grade secret management system has been deployed to `main` branch with:
- ✅ **Immutable audit trail** (JSONL logs, append-only)
- ✅ **Ephemeral credentials** (no private keys on disk)
- ✅ **Idempotent automation** (safe to re-run)
- ✅ **Hands-off operation** (24/7 cron-scheduled)
- ✅ **NO GitHub Actions** (direct deployment only)
- ✅ **Multi-layer secrets** (GSM → Key Vault → Vault → KMS → Env)

The system is **already scheduled** and running on a 24-hour cycle:
- **2 AM UTC daily:** Complete mirror + verify + test cycle
- **1 AM UTC Sundays:** Weekly credential rotation
- **Every 6 hours:** Health checks with optional alerting

---

## Quick Reference

### View Current Status
```bash
# Check health status
bash scripts/secrets/health-check.sh

# View audit logs
tail -f logs/orchestration/secret-orch-*.jsonl | jq .
tail -f logs/secret-mirror/mirror-*.jsonl | jq .

# View cron logs
tail -f /var/log/nexusshield-secrets/daily-mirror.log
tail -f /var/log/nexusshield-secrets/health-check.log
```

### Rotate Credentials Manually (if needed)
```bash
# Show current versions
bash scripts/secrets/rotate-credentials.sh status

# Rotate all credentials (idempotent)
bash scripts/secrets/rotate-credentials.sh all

# Rotate specific cloud (Azure/AWS/GCP)
bash scripts/secrets/rotate-credentials.sh azure
bash scripts/secrets/rotate-credentials.sh aws
bash scripts/secrets/rotate-credentials.sh gcp
```

### Use Credentials in Workloads
```bash
# Source credential fetcher (auto-fallback through layers)
source scripts/secrets/unified-credential-fetcher.sh

# Load cloud credentials (exports env vars)
load_azure_credentials
load_aws_credentials     # optional
load_gcp_credentials

# Or fetch single credential
export SECRET=$(get_credential "secret-name")
```

---

## System Architecture

### Multi-Layer Secret Storage
```
┌─────────────────────────────────────────┐
│ Canonical Source: GSM (nexusshield-prod) │
└────────────┬────────────────────────────┘
             │ (idempotent mirror)
             ├─→ Azure Key Vault (nsv298610)
             ├─→ HashiCorp Vault (optional)
             ├─→ GCP KMS (encryption)
             └─→ Environment vars (fallback)
```

### Credential Fetch at Runtime
```
Workload needs credential:
  1. Try GSM (canonical source first)
  2. If not found, try Vault (if available)
  3. If not found, try KMS (decrypt)
  4. If not found, try environment
  5. Return empty if none available
```

### Scheduled Operations
```
Daily (2 AM UTC):
  ├─ Mirror GSM → Key Vault/Vault/KMS/Env
  ├─ Verify credentials across all layers
  ├─ Run cross-cloud smoke tests
  ├─ Write audit logs (JSONL, immutable)
  └─ Alert if failures detected

Weekly (Sunday 1 AM UTC):
  ├─ Rotate Azure/AWS/GCP credentials
  ├─ Create new GSM secret versions
  ├─ Update all mirrors
  └─ Alert on completion

Every 6 hours:
  ├─ Check last orchestration run
  ├─ Verify credential freshness
  ├─ Validate Key Vault sync
  ├─ Analyze audit logs
  └─ Send alerts if issues found
```

---

## Credentials Currently Managed

### Azure (✅ PRODUCTION)
- `azure-client-id` — Service principal app ID
- `azure-client-secret` — Service principal password
- `azure-tenant-id` — Azure tenant ID
- `azure-subscription-id` — Azure subscription ID

**Status:** 4 secrets in GSM, mirrored to Key Vault, functional.

### GCP (✅ PRODUCTION)
- `gcp-epic6-operator-sa-key` — Service account JSON key

**Status:** Key created, stored in GSM, functional.

### AWS (⏳ OPTIONAL)
- `aws-access-key-id` — IAM user access key
- `aws-secret-access-key` — IAM user secret access key

**Status:** Bootstrap script ready. Requires IAM credentials or privileged host to complete.

---

## Audit & Compliance

### Immutable Logs (Append-Only)
```
logs/orchestration/secret-orch-*.jsonl
├─ Build ID, timestamp, step, status
├─ Each run is a new file (never overwritten)
└─ Suitable for SOC 2 / ISO 27001 compliance

logs/secret-mirror/mirror-*.jsonl
├─ GSM → Vault/KMS/Key Vault mirror events
├─ Success/failure status per secret
└─ Audit trail of all mirror operations

logs/rotation/rotation-*.jsonl
├─ Credential rotation events
├─ GSM version increments
└─ Rotation completion status

logs/health-check/check-*.log
├─ Health check results
├─ Issues detected (if any)
└─ Alert delivery status
```

### Pre-Commit Protection
- ✅ Pre-commit hook prevents secret commits
- ✅ GitHub push protection enabled
- ✅ If secrets detected: history rewrite + cleanup

---

## Troubleshooting

### Health Check Failed
```bash
# View detailed health check output
bash scripts/secrets/health-check.sh

# Common issues:
# 1. Last orchestration > 24h old (check cron logs)
# 2. Missing GSM secrets (check GSM console)
# 3. Key Vault out of sync (re-run mirror manually)
# 4. Audit logs show failures (check specific error in JSON)
```

### Manual Mirror Run
```bash
# Run mirror outside cron (idempotent)
bash scripts/secrets/mirror-all-backends.sh

# Output shows:
# - Which backends succeeded/failed
# - Audit file location
# - Skipped layers (if VAULT_ADDR/TOKEN not set)
```

### Credential Not Available
```bash
# Debug credential fetch
source scripts/secrets/unified-credential-fetcher.sh
export DEBUG_CREDS=1
get_credential "secret-name"

# Check each layer manually:
gcloud secrets versions access latest --secret="secret-name" --project=nexusshield-prod
vault kv get secret/path/to/secret  # if Vault available
```

### Cron Job Not Running
```bash
# Check if in crontab
crontab -l | grep hands-off-orchestrate

# Check cron logs
sudo tail -f /var/log/syslog | grep CRON  # Linux
log stream --predicate 'process == "cron"'  # macOS
cat /var/log/nexusshield-secrets/daily-mirror.log
```

---

## Adding New Secrets

If you need to add a new secret to the multi-layer mirror:

### 1. Create in GSM
```bash
echo "secret-value" | gcloud secrets create "new-secret" \
  --data-file=- \
  --project=nexusshield-prod
```

### 2. Update mirror configuration
Edit `scripts/secrets/mirror-all-backends.sh` and add the secret name to the `secrets=()` array.

### 3. Re-run mirror (idempotent)
```bash
bash scripts/secrets/mirror-all-backends.sh
# or wait for cron (2 AM UTC daily)
```

### 4. Verify in all backends
```bash
gcloud secrets versions access latest --secret="new-secret" --project=nexusshield-prod
az keyvault secret show --vault-name nsv298610 --name "new-secret"
vault kv get secret/path/to/new-secret  # if Vault available
```

---

## Optional Enhancements

### Enable HashiCorp Vault Mirroring
```bash
export VAULT_ADDR=https://vault.example.internal:8200
# Set via credential manager: bash scripts/provision-operator-credentials.sh vault
bash scripts/secrets/mirror-all-backends.sh
```

**After:** Update cron env or wrapper script to pass `VAULT_ADDR` (token via credential manager on each run).

### Enable Slack Alerts
```bash
export SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
# Then health-check alerts will post to Slack on failures
```

### Enable Email Alerts
```bash
# Ensure mail/postfix is installed
sudo apt-get install postfix  # or equivalent for your OS

export ALERT_EMAIL="ops@example.com"
# Then health-check will email alerts on failures
```

---

## Production Checklist

- [x] Core orchestration framework deployed
- [x] Azure credentials in GSM + Key Vault
- [x] GCP service account key in GSM
- [x] KMS encryption key provisioned
- [x] Daily mirror cron job installed (2 AM UTC)
- [x] Weekly rotation cron job installed (Sunday 1 AM UTC)
- [x] Health checks running (every 6 hours)
- [x] Audit logs operational (JSONL, append-only)
- [x] Pre-commit hook protecting secrets
- [x] Documentation committed to `main`
- [x] NO GitHub Actions used (direct deployment)
- [x] NO pull request releases used (direct commits)

### Optional (Can Add Later):
- [ ] HashiCorp Vault endpoint + token (if Vault infrastructure available)
- [ ] AWS IAM credentials (if AWS account access available)
- [ ] Slack webhook for alerts
- [ ] Email alerts for ops team
- [ ] External audit system integration (Splunk/DataDog)

---

## Support & Escalation

| Issue | Contact | Action |
|-------|---------|--------|
| Cron not running | DevOps | Check `crontab -l` and cron logs in `/var/log/nexusshield-secrets/` |
| Vault not reachable | Cloud Security | Provide via credential manager: `bash scripts/provision-operator-credentials.sh vault` (optional) |
| AWS credentials missing | Cloud Ops | Run `scripts/aws/setup-aws-iam-role.sh` on authorized host (optional) |
| Secret not in any layer (fetch fails) | DevOps | Check GSM, re-run mirror, verify workload has correct secret name |
| Health check alerts | Ops Team | Manual run: `bash scripts/secrets/health-check.sh` |

---

## Key Files & Locations

| File | Purpose |
|------|---------|
| `scripts/secrets/hands-off-orchestrate.sh` | Main workflow (mirror → verify → test → audit) |
| `scripts/secrets/mirror-all-backends.sh` | Multi-layer mirror (GSM → Vault/KMS/AKV) |
| `scripts/secrets/unified-credential-fetcher.sh` | Runtime credential fetch (used in workloads) |
| `scripts/secrets/rotate-credentials.sh` | Credential rotation helper |
| `scripts/secrets/health-check.sh` | Health checks + alerting |
| `scripts/secrets/cron-scheduler.sh` | Cron job installer |
| `docs/SECRETS_MANAGEMENT_SYSTEM.md` | Full system documentation |
| `logs/orchestration/` | Immutable audit logs (daily runs) |
| `logs/secret-mirror/` | Immutable audit logs (mirror operations) |
| `logs/rotation/` | Immutable audit logs (credential rotations) |
| `logs/health-check/` | Health check results |
| `/var/log/nexusshield-secrets/` | Cron execution logs |

---

## Next Steps

**Immediate (Day 0):**
- [x] System deployed to production
- [x] Cron jobs scheduled
- [x] Health checks operational
- [ ] Communicate to teams that system is live

**Short-term (Week 1):**
- [ ] Monitor logs for first full week of operation
- [ ] Confirm daily mirror runs successfully
- [ ] Observe first Sunday rotation
- [ ] Validate credential freshness across all layers

**Medium-term (Month 1):**
- [ ] Optional: Enable Vault and AWS integrations
- [ ] Optional: Set up Slack/email alerts
- [ ] Baseline: 1-month audit trail review

**Long-term (Ongoing):**
- [ ] Monitor audit logs for compliance
- [ ] Annual credential rotation policy review
- [ ] Quarterly: Update bootstrap scripts (new cloud regions, etc.)
- [ ] Continuous: Add new secrets as workloads require them

---

**Deployment Date:** 2026-03-11  
**Status:** ✅ PRODUCTION READY  
**Support:** See GitHub issues #2450–#2459 for detailed context  
**Audit:** All operations logged immutably in `logs/` and GitHub issue comments
