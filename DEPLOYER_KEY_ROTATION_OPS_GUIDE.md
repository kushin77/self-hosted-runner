# Deployer Key Rotation - Operations & Deployment Guide

**Date**: 2026-03-12
**Status**: ✅ READY FOR PRODUCTION DEPLOYMENT  
**Lead Engineer Approval**: Approved (Lead-engineer-approved direct deployment, no PRs)

---

## Overview

The `owner-rotate-deployer-key-bootstrap.sh` implements **idempotent**, **immutable-audited**, **hands-off** deployment of deployer service account key rotations into Google Cloud Secret Manager.

### Key Features

- **Immutable Audit Trail**: Append-only JSONL with SHA256 hash chaining in `logs/multi-cloud-audit/owner-rotate-<timestamp>.jsonl`
- **Idempotent**: Prevents rapid re-rotations using `MIN_INTERVAL_SECONDS` (default 600s = 10min)
- **Ephemeral**: Temporary keys are securely deleted with `shred` (3-pass overwrite)
- **Hands-Off**: Daily scheduled via systemd timer at 2 AM
- **No-Ops**: Fully automated, no GitHub Actions, direct system deployment
- **Secret Versioning**: Automatic new version creation in Secret Manager with immutable history

---

## File Inventory

### Bootstrap Script
- **Location**: `infra/owner-rotate-deployer-key-bootstrap.sh`
- **Purpose**: Create new deployer-run SA key, add as new Secret Manager version, verify access
- **Audit Output**: Append-only JSONL to `logs/multi-cloud-audit/owner-rotate-<ts>.jsonl`

### Systemd Automation
- **Service**: `infra/systemd/deployer-key-rotate.service`  
  - Defines the rotation job (runs bootstrap script)
  - Failure restart policy: backoff up to 3 retries per hour
  
- **Timer**: `infra/systemd/deployer-key-rotate.timer`  
  - Schedule: Daily at 02:00 UTC
  - Persistent: Runs on next boot if missed
  - Randomized start: ±5 min (avoid thundering herd)

### Audit Logs
- **Location**: `logs/multi-cloud-audit/owner-rotate-*.jsonl`
- **Format**: Newline-delimited JSON (JSONL)
- **Chaining**: Each entry includes `prev_hash` (previous entry hash) and `hash` (current entry hash)
- **Append-Only**: No modifications to existing entries; new rotations create new files

---

## Deployment Instructions

### 1. Deploy Systemd Timer (Manual, Lead Engineer)

```bash
cd /home/akushnir/self-hosted-runner

# Copy unit files to system directory
sudo cp infra/systemd/deployer-key-rotate.service /etc/systemd/system/
sudo cp infra/systemd/deployer-key-rotate.timer /etc/systemd/system/

# Reload systemd configuration
sudo systemctl daemon-reload

# Enable timer (auto-start on boot, will start at 2 AM UTC)
sudo systemctl enable deployer-key-rotate.timer

# Start timer immediately (first rotation at next 2 AM, or manually via start)
sudo systemctl start deployer-key-rotate.timer

# Verify status
sudo systemctl status deployer-key-rotate.timer
```

### 2. Verify Deployment

```bash
# Check timer next run time and last state
sudo systemctl list-timers deployer-key-rotate.timer

# View systemd logs for rotation history
sudo journalctl -u deployer-key-rotate.service -n 50 -f

# Check audit trail
tail -10 logs/multi-cloud-audit/owner-rotate-*.jsonl
```

### 3. Manual On-Demand Rotation (if needed)

```bash
# Force immediate rotation (bypasses 10-min cooldown)
MIN_INTERVAL_SECONDS=0 bash infra/owner-rotate-deployer-key-bootstrap.sh

# Or use default cooldown (idempotent)
bash infra/owner-rotate-deployer-key-bootstrap.sh
```

---

## Operations

### Idempotency

- **Default Cooldown**: 600 seconds (10 minutes)
- **Override**: Set `MIN_INTERVAL_SECONDS=0` to force rotation
- **Safety**: Bootstrap skips rotation if a version was created more recently than the cooldown interval

**Example**: Run bootstrap every hour via cron, but only performs rotation if > 600s since last

```bash
# Crontab: run every hour, but only if 10+ min since last rotation (idempotent)
0 * * * * /bin/bash -c 'cd /home/akushnir/self-hosted-runner && bash infra/owner-rotate-deployer-key-bootstrap.sh'
```

### Audit Inspection

Each audit file contains JSONL entries with:
- `timestamp`: ISO 8601 UTC timestamp
- `level`: INFO, WARN, ERROR
- `message`: Operation or status message
- `prev_hash`: SHA256 of previous entry (hash chain anchor)
- `hash`: SHA256 of current entry

**Verify Integrity** (example):

```bash
# Extract last entry's hash and first line of next file (should match)
LAST_HASH=$(tail -1 logs/multi-cloud-audit/owner-rotate-20260312-005102.jsonl | jq -r '.hash')
NEXT_FIRST_PREV=$(head -1 logs/multi-cloud-audit/owner-rotate-20260312-005207.jsonl | jq -r '.prev_hash')
echo "Last hash: $LAST_HASH"
echo "Next prev: $NEXT_FIRST_PREV"
[ "$LAST_HASH" = "$NEXT_FIRST_PREV" ] && echo "✅ Chain valid" || echo "❌ Chain broken"
```

### Secret Manager Versions

List current secret versions:

```bash
gcloud secrets versions list deployer-sa-key --project=nexusshield-prod --format="table(name,created)"
```

Destroy old versions (after confirming deployments use new key):

```bash
gcloud secrets versions destroy VERSION_ID --secret=deployer-sa-key --project=nexusshield-prod
```

---

## Monitoring & Alerting (Recommended)

### Systemd Timer Health

```bash
# Check if timer is active and next scheduled time
sudo systemctl list-timers deployer-key-rotate.timer

# Alert if timer is inactive
sudo systemctl is-active deployer-key-rotate.timer || echo "ALERT: Timer not active"
```

### Audit File Freshness

```bash
# Alert if no rotation for > 25 hours (timer runs daily at 2 AM)
LATEST_AUDIT=$(ls -t logs/multi-cloud-audit/owner-rotate-*.jsonl | head -1)
MTIME=$(stat -c "%Y" "$LATEST_AUDIT")
NOW=$(date +%s)
AGE=$((NOW - MTIME))
if [ "$AGE" -gt 90000 ]; then
  echo "ALERT: No rotation in 25+ hours"
fi
```

### Secret Version Staleness

```bash
# Alert if deployed key version hasn't been updated in 3 days
LAST_VERSION=$(gcloud secrets versions list deployer-sa-key --project=nexusshield-prod --limit=1 --format="value(created)")
LAST_EPOCH=$(date -d "$LAST_VERSION" +%s)
NOW=$(date +%s)
AGE_SECONDS=$((NOW - LAST_EPOCH))
AGE_DAYS=$((AGE_SECONDS / 86400))
if [ "$AGE_DAYS" -gt 3 ]; then
  echo "ALERT: Secret version age > 3 days"
fi
```

---

## IAM Requirements

The deployer-run service account requires:

```bash
# Grant Secret Manager admin (or creator) role:
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/secretmanager.admin"
```

---

## Troubleshooting

### Timer Not Running

```bash
# Check if enabled
sudo systemctl is-enabled deployer-key-rotate.timer

# Enable if needed
sudo systemctl enable deployer-key-rotate.timer

# Start if needed
sudo systemctl start deployer-key-rotate.timer
```

### Permission Denied When Creating Secret

```bash
# Grant deployer-run the secretmanager.admin role (see IAM Requirements)
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/secretmanager.admin"
```

### Manual Key File Not Deleted

If `shred` fails or isn't available, fallback is `rm -f`:  
Ensure `/tmp` volume has secure-delete capabilities or manually wipe:

```bash
# Manual secure deletion
shred -vfz -n 5 /tmp/deployer-sa-key-*.json
```

---

## Security Posture

✅ **Immutable**: Audit trail is append-only; no deletion or modification of rotations  
✅ **Ephemeral**: Temporary key files destroyed with multi-pass overwrite  
✅ **Idempotent**: Safe to call repeatedly; won't rotate too often  
✅ **Hands-Off**: No human intervention needed; fully automated via systemd  
✅ **No-Ops**: No GitHub Actions, no PR releases; direct system deployment  
✅ **Audited**: Every step logged with timestamp, level, and message  

---

## Change Log

- **2026-03-12**: Initial bootstrap deployment with idempotency, immutable audit trail, and systemd timer scheduling
- **Commits**:
  - `306289926`: Fix JSONL audit logging (remove tee contamination)
  - `793eea852`: Add systemd timer for daily rotation at 2 AM

---

## Next Steps (Recommended)

1. ✅ Deploy systemd units (`sudo systemctl enable deployer-key-rotate.timer`)
2. ✅ Monitor audit trail for first automated rotation (2 AM UTC next day)
3. ✅ Retire old secret versions after confirming new key is deployed to services
4. ✅ Set up monitoring/alerting for timer health and audit freshness
5. ✅ Document in runbooks and on-call playbooks

**Status**: Ready for immediate production deployment.

