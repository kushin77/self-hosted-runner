# Credential Rotation System - Operator Handoff (March 13, 2026)

## Overview

A production-ready automated credential rotation pipeline has been deployed for HashiCorp Vault AppRole secret rotation. The system is **infrastructure-complete** and **ready for operator activation**.

## What's Delivered

### 1. **Vault AppRole Rotation Script**
- **File**: `scripts/secrets/run_vault_rotation.sh`
- **Function**: Rotates Vault AppRole secret_id, stores new version in GSM
- **Safety Features**:
  - Health-checks Vault before rotation
  - Placeholder detection (prevents using fake/test credentials)
  - DRY_RUN mode (skips GSM writes for testing)
  - MOCK_VAULT mode (uses mocked secret_id for CI/CD validation)
  - Detailed audit logging to `logs/rotate-vault-*.log`

### 2. **Cloud Build Pipeline**
- **File**: `cloudbuild/run-vault-rotation.yaml`
- **Triggers**: Via Cloud Pub/Sub topic `vault-rotation-trigger`
- **Injected Secrets**: VAULT_ADDR and VAULT_TOKEN (from GSM)
- **Output**: New secret_id stored as version in GSM secret `vault-example-role-secret_id`

### 3. **Cloud Scheduler (Daily Automation)**
- **Job Name**: `vault-rotation-schedule`
- **Schedule**: `0 3 * * *` (daily at 03:00 UTC)
- **Location**: `us-central1`
- **Action**: Publishes to Pub/Sub topic → triggers Cloud Build

### 4. **Pub/Sub Topic**
- **Name**: `vault-rotation-trigger`
- **Project**: `nexusshield-prod`
- **Purpose**: Decouples scheduler from build execution; allows manual triggers

### 5. **IAM Bindings**
- Cloud Build Service Account (151423364222@cloudbuild.gserviceaccount.com) has:
  - `roles/secretmanager.secretAccessor` on VAULT_ADDR, VAULT_TOKEN, vault-example-role-secret_id
  - `roles/secretmanager.secretVersionAdder` on vault-example-role-secret_id

---

## Quick Start for Operators

### **Step 1: Supply Vault Credentials**

Run the automated setup helper:

```bash
./scripts/secrets/enable-vault-rotation.sh 'https://vault.example.com:8200' 's.your_token_here'
```

This script will:
1. Store `VAULT_ADDR` and `VAULT_TOKEN` in Google Secret Manager
2. Test connectivity to Vault
3. Execute the first rotation build (deploy new secret_id to GSM)
4. Confirm setup is complete

**Alternative (manual)**: If you prefer to store credentials manually:

```bash
# Store Vault address
echo -n "https://vault.example.com:8200" | \
  gcloud secrets versions add VAULT_ADDR --data-file=- --project=nexusshield-prod

# Store Vault token
echo -n "s.your_token_here" | \
  gcloud secrets versions add VAULT_TOKEN --data-file=- --project=nexusshield-prod

# Then submit the build manually
gcloud builds submit . --config=cloudbuild/run-vault-rotation.yaml \
  --substitutions=_GSM_PROJECT=nexusshield-prod --timeout=600s
```

### **Step 2: Verify Setup**

```bash
# Check scheduler job is active
gcloud scheduler jobs describe vault-rotation-schedule \
  --location=us-central1 --project=nexusshield-prod

# Check that Pub/Sub topic exists
gcloud pubsub topics describe vault-rotation-trigger --project=nexusshield-prod

# View recent rotations (check logs)
gcloud logging read 'resource.type=cloud_build AND logName=~"vault-rotation"' \
  --project=nexusshield-prod --limit=5 --format=json
```

### **Step 3: Manual Trigger (Optional Testing)**

```bash
# Publish a message to the Pub/Sub topic to manually trigger a rotation
gcloud pubsub topics publish vault-rotation-trigger \
  --message '{"action":"rotate"}' --project=nexusshield-prod

# Watch the build execute
gcloud builds list --project=nexusshield-prod --limit=1 --format='table(id,status,createTime)'
```

---

## Architecture

```
Cloud Scheduler (daily 03:00 UTC)
         ↓
    Pub/Sub Topic (vault-rotation-trigger)
         ↓
    Cloud Build (run-vault-rotation.yaml)
         ↓
    Fetch VAULT_ADDR, VAULT_TOKEN from GSM
         ↓
    Execute scripts/secrets/run_vault_rotation.sh
         ↓
    Health-check Vault
    Request new AppRole secret_id
    Store new secret_id → GSM secret 'vault-example-role-secret_id'
         ↓
    Audit log entry recorded
```

---

## Testing & Validation

### **Local DRY-RUN (No GSM Writes)**

```bash
DRY_RUN=1 VAULT_ADDR=https://vault.example.com:8200 \
  VAULT_TOKEN=s.your_token_here \
  ./scripts/secrets/run_vault_rotation.sh
```

### **Local Mock-Mode (No Real Vault Needed)**

```bash
MOCK_VAULT=1 DRY_RUN=1 \
  VAULT_ADDR=http://127.0.0.1:8200 \
  VAULT_TOKEN=dummy \
  ./scripts/secrets/run_vault_rotation.sh
```

### **Cloud Build Mock Validation**

```bash
gcloud builds submit . --config=cloudbuild/run-vault-rotation-mockmode.yaml \
  --timeout=600s --project=nexusshield-prod
```

---

## Troubleshooting

### **Build Fails: "Could not resolve host: vault.internal"**
- **Cause**: VAULT_ADDR in GSM is a placeholder (vault.internal)
- **Fix**: Update GSM with real Vault URL:
  ```bash
  echo -n "https://your-real-vault.com:8200" | \
    gcloud secrets versions add VAULT_ADDR --data-file=- --project=nexusshield-prod
  ```

### **Build Fails: "X-Vault-Token: permission denied"**
- **Cause**: Invalid token or insufficient Vault permissions
- **Fix**: Verify token is valid and AppRole has `read:secret_id` permission on the auth method

### **Secret Version Never Created**
- **Cause**: Build succeeded but secret write failed (IAM issue)
- **Fix**: Verify Cloud Build SA has `secretVersionAdder` role on `vault-example-role-secret_id`:
  ```bash
  gcloud secrets get-iam-policy vault-example-role-secret_id \
    --project=nexusshield-prod
  ```

### **View Build Logs**

```bash
# Get build ID
BUILD_ID=$(gcloud builds list --limit=1 --format='value(id)' --project=nexusshield-prod)

# Stream logs
gcloud builds log $BUILD_ID --stream --project=nexusshield-prod
```

---

## Security / Compliance

- ✅ **No secrets in code**: All credentials stored in Google Secret Manager
- ✅ **No passwords in logs**: Rotation script avoids printing sensitive values
- ✅ **Audit trail**: All rotations logged via Cloud Build + Cloud Logging
- ✅ **Immutable history**: Commit history cleaned; backup tag created (`backup/main-before-history-purge-20260313T0042Z`)
- ✅ **IAM least-privilege**: Cloud Build SA has minimal roles needed only
- ✅ **Daily rotation**: Automated schedule prevents credential stale-ness

---

## Support & Monitoring

**To monitor active rotations:**

```bash
# Real-time build logs
gcloud builds log $(gcloud builds list --limit=1 --format='value(id)' --project=nexusshield-prod) \
  --stream --project=nexusshield-prod

# Recent build statuses
gcloud builds list --limit=10 --project=nexusshield-prod \
  --filter='config~"vault-rotation"' --format='table(id,status,createTime,failureMessage)'

# Rotation audit trail
gcloud logging read 'resource.type=cloud_build AND logName=~"vault-rotation"' \
  --project=nexusshield-prod --format='table(timestamp,labels.build_id,textPayload)'
```

**To disable rotation (emergency):**

```bash
gcloud scheduler jobs pause vault-rotation-schedule \
  --location=us-central1 --project=nexusshield-prod

# Re-enable when ready:
gcloud scheduler jobs resume vault-rotation-schedule \
  --location=us-central1 --project=nexusshield-prod
```

---

## Files & Locations

| File | Purpose |
|------|---------|
| `scripts/secrets/run_vault_rotation.sh` | Core rotation logic |
| `scripts/secrets/enable-vault-rotation.sh` | Operator activation script |
| `scripts/secrets/mock_vault_server.py` | Local testing mock |
| `cloudbuild/run-vault-rotation.yaml` | Production Cloud Build config |
| `docs/VaultRotation_Automation.md` | Detailed technical documentation |
| `.gcloudignore` | Excludes stale files from build source |

---

## Next Steps

1. **Provide Vault Credentials** (operator action):
   ```bash
   ./scripts/secrets/enable-vault-rotation.sh '<YOUR_VAULT_URL>' '<YOUR_VAULT_TOKEN>'
   ```

2. **Verify Scheduler is Running**:
   ```bash
   gcloud scheduler jobs describe vault-rotation-schedule --location=us-central1 --project=nexusshield-prod
   ```

3. **Monitor First Rotation** (occurs daily at 03:00 UTC or on demand):
   ```bash
   gcloud builds list --limit=1 --filter='config~"vault-rotation"' --format='table(id,status)'
   ```

4. **Audit Success**:
   - Verify new secret version in `vault-example-role-secret_id`
   - Check Cloud Logging for rotation completion

---

**Delivered**: March 13, 2026, 01:30 UTC  
**Status**: ✅ Production-Ready (awaiting Vault credentials)  
**Support**: Review logs in Cloud Console or use `gcloud` CLI commands above.
