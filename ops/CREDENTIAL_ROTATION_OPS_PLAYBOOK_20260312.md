# Credential Rotation Production Playbook
## Quick Start for Ops Team

**Last Updated**: March 12, 2026 23:40 UTC  
**Status**: ✅ PRODUCTION READY  

---

## Automated Scheduling (NO ACTION REQUIRED)

✅ **Status**: Automated daily rotation is now configured and active!

Your credential rotation is automatically triggered **every day at 2 AM UTC** via:
- **Cloud Scheduler**: `credential-rotation-daily` job (published to Pub/Sub topic)
- **Pub/Sub Topic**: `credential-rotation-trigger` (event bus for rotation events)
- **Automated Submission**: Rotation build is submitted daily without manual intervention

**What this means**:
1. Your GitHub, AWS, and Vault credentials are rotated automatically every morning
2. No ops team action required for daily rotation
3. Rotation results are logged to build history and audit trail
4. All secrets are automatically versioned in Cloud Secret Manager

---

## Prerequisites Check

```bash
# Verify you have gcloud access to nexusshield-prod
gcloud config set project nexusshield-prod
gcloud auth list

# Verify Cloud Build access
gcloud builds list --project=nexusshield-prod --limit=1

# Verify GSM access
gcloud secrets list --project=nexusshield-prod
```

---

## Current Status (March 12, 2026)

- GitHub token rotation: **✅ ACTIVE** (v25 latest)
- AWS key rotation: **✅ ACTIVE** (v14 latest)
- Vault rotation: **⏳ PENDING** (test credentials only)

---

## IMMEDIATE TASK: Provision Real Vault Credentials

### Step 1: Get Your Vault Endpoint
Contact your Vault admin to obtain:
- **Endpoint URL** (example: `https://vault.internal`)
- **Service Token** (example: `s.abcd1234efgh5678`)

### Step 2: Add Vault Endpoint to GSM

**Choose ONE option:**

**Option A: Direct command**
```bash
printf '%s' "https://vault.internal" | \
  gcloud secrets versions add VAULT_ADDR --data-file=- --project=nexusshield-prod
```

**Option B: Interactive (if you prefer to be prompted)**
```bash
# This will prompt you for the value
gcloud secrets versions add VAULT_ADDR --project=nexusshield-prod
```

**Validation**: The value must NOT contain:
- `example`
- `PLACEHOLDER`
- `your-vault`

### Step 3: Add Vault Token to GSM

```bash
printf '%s' "s.abcd1234efgh5678" | \
  gcloud secrets versions add VAULT_TOKEN --data-file=- --project=nexusshield-prod
```

**Validation**: The value must NOT contain:
- `PLACEHOLDER`
- `REDACTED`

### Step 4: Trigger Credential Rotation

```bash
# Copy-paste this entire command block:
gcloud builds submit \
  --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
  --substitutions=PROJECT_ID=nexusshield-prod \
  --project=nexusshield-prod \
  --async
```

This will return a **BUILD_ID** that looks like: `a48ec13f-b6f7-4eb5-b9ca-b7051cea4e02`

### Step 5: Monitor the Rotation

```bash
# Replace BUILD_ID with the one from Step 4
BUILD_ID="<paste-build-id-here>"

gcloud builds log "$BUILD_ID" --project=nexusshield-prod
```

**Look for this in the output**:
```
[rotate-credentials.sh] Vault rotation completed successfully
Created version [X] of the secret [VAULT_APPID]
```

---

## Verification After Rotation

### Check All Credentials Updated

```bash
echo "GitHub Token:"
gcloud secrets versions list github-token --project=nexusshield-prod --limit=3 --format='csv(name,createTime)'

echo "AWS Access Key ID:"
gcloud secrets versions list aws-access-key-id --project=nexusshield-prod --limit=3 --format='csv(name,createTime)'

echo "AWS Secret Access Key:"
gcloud secrets versions list aws-secret-access-key --project=nexusshield-prod --limit=3 --format='csv(name,createTime)'

echo "Vault Address:"
gcloud secrets versions list VAULT_ADDR --project=nexusshield-prod --limit=3 --format='csv(name,createTime)'

echo "Vault Token:"
gcloud secrets versions list VAULT_TOKEN --project=nexusshield-prod --limit=3 --format='csv(name,createTime)'
```

### Check Recent Build History

```bash
gcloud builds list --project=nexusshield-prod --limit=5 \
  --format='table(id,status,createTime)'
```

### Review Audit Trail

```bash
# Show all rotation events
tail -20 logs/rotation-audit-*.jsonl

# Or check specific date
ls -lh logs/rotation-audit-*.jsonl | tail -5
```

---

## Ongoing Operations

### Automated Daily Rotation (No Action Needed)

✅ **Your credentials are automatically rotated every day at 2 AM UTC**

Infrastructure:
- **Cloud Scheduler Job**: `credential-rotation-daily` (enabled, publishes daily)
- **Pub/Sub Topic**: `credential-rotation-trigger` (receives rotation events)
- **Service Account**: `credential-rotation-scheduler@nexusshield-prod.iam.gserviceaccount.com` (has Cloud Build permissions)

**Monitoring the automated rotation**:
```bash
# View the scheduler job
gcloud scheduler jobs describe credential-rotation-daily \
  --location=us-central1 \
  --project=nexusshield-prod

# Check recent automated builds
gcloud builds list --project=nexusshield-prod --limit=5 \
  --format='table(id,status,createTime,substitutions.PROJECT_ID)'
```

### Run Weekly Verification

```bash
bash scripts/ops/production-verification.sh
```

Expected output: **Exit code: 0** ✅

### Trigger Manual Rotation (On-Demand)

```bash
gcloud builds submit \
  --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
  --substitutions=PROJECT_ID=nexusshield-prod \
  --project=nexusshield-prod \
  --async
```

### Troubleshooting

**Build failed?**
```bash
# Check the logs
gcloud builds log "$BUILD_ID" --project=nexusshield-prod

# Check for common errors:
gcloud builds log "$BUILD_ID" --project=nexusshield-prod | grep -i error
gcloud builds log "$BUILD_ID" --project=nexusshield-prod | grep -i "vault"
```

**Vault rotation skipped?**
This means `VAULT_ADDR` or `VAULT_TOKEN` still contains a placeholder value.
- Check current values: `gcloud secrets versions describe LATEST --secret=VAULT_ADDR --project=nexusshield-prod`
- Ensure no "example", "PLACEHOLDER", or "your-vault" in the VAULT_ADDR
- Ensure no "PLACEHOLDER" or "REDACTED" in the VAULT_TOKEN

---

## Compliance Checklist

After completing all steps, verify:

- [ ] Vault endpoint added to GSM VAULT_ADDR
- [ ] Vault token added to GSM VAULT_TOKEN
- [ ] Cloud Build rotation triggered successfully
- [ ] All 5 credentials have new versions in GSM
- [ ] Build logs show all three credential types rotating
- [ ] Weekly production-verification.sh script passes (exit 0)
- [ ] Audit trail logs show rotation timestamp

---

## Support

**Documentation**: [CREDENTIAL_ROTATION_PRODUCTION_READY_20260312.md](../CREDENTIAL_ROTATION_PRODUCTION_READY_20260312.md)

**Configuration**: [cloudbuild/rotate-credentials-cloudbuild.yaml](../cloudbuild/rotate-credentials-cloudbuild.yaml)

**Scripts**: 
- Orchestrator: `scripts/secrets/rotate-credentials.sh`
- Vault rotation: `scripts/secrets/run_vault_rotation.sh`

---

**Status**: Ready for prod Vault credential provisioning  
**Last Verified**: March 12, 2026 23:40 UTC
