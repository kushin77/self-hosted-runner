# Phase 3 Pragmatic Unblock - Remediation Options

**Status:** ⚠️ **REQUIRES OPERATOR ACTION**  
**Generated:** 2026-03-08 18:42 UTC  
**Blocker:** Multi-layer secret infrastructure unavailable (GSM, Vault, KMS)  
**Solution:** 3 remediation paths to choose from  

---

## Current Situation

**What Works:**
- ✅ GitHub secrets exist (GCP_SERVICE_ACCOUNT_KEY)
- ✅ Phase 3 workflow ready (provision_phase3.yml)
- ✅ Terraform infrastructure code ready (infra/gcp-workload-identity.tf)
- ✅ All logic and automation in place

**What's Blocked:**
- ❌ Cannot access GSM (Google Secret Manager)
- ❌ Cannot access Vault (HashiCorp)
- ❌ Cannot access KMS (Cloud Key Management)
- ❌ Local environment not authenticated to GCP

**Result:** 6 failed workflow runs unable to fetch credentials

---

## Option A: Local Deployment (FASTEST)

### Requirements
- [ ] gcloud CLI installed
- [ ] Authenticated to GCP (gcloud auth login)
- [ ] terraform CLI v1.5+
- [ ] GitHub CLI (gh) configured
- [ ] GCP Editor role in project

### Timeline
⏱️  **5-10 minutes total**

### Steps

```bash
# Step 1: Authenticate to GCP
gcloud auth login
gcloud config set project gcp-eiq

# Step 2: Setup environment
export GCP_PROJECT_ID="gcp-eiq"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"

# Step 3: Deploy infrastructure
cd /home/akushnir/self-hosted-runner/infra
terraform init
terraform apply -auto-approve

# Step 4: Capture outputs
export GCP_WIF_POOL_ID=$(terraform output -raw workload_identity_pool_id)
export GCP_WIF_PROVIDER_ID=$(terraform output -raw workload_identity_provider_id)

# Step 5: Update GitHub secrets
gh secret set GCP_WIF_POOL_ID --body "$GCP_WIF_POOL_ID"
gh secret set GCP_WIF_PROVIDER_ID --body "$GCP_WIF_PROVIDER_ID"
gh secret set GCP_PROJECT_ID --body "$GCP_PROJECT_ID"

# Step 6: Trigger Phase 3 workflow
gh workflow run provision_phase3.yml --ref main

# Step 7: Monitor
gh run list --workflow=provision_phase3.yml --limit=1 --json number,status
```

### Verification
```bash
# Check Workload Identity Pool created
gcloud iam workload-identity-pools list --location=global --project=gcp-eiq

# Check Cloud KMS keyring created
gcloud kms keyrings list --location=us-central1 --project=gcp-eiq

# Check Cloud Storage bucket created
gsutil ls gs://gcp-eiq-terraform-state/
```

---

## Option B: Provide Credentials

### Requirements
- [ ] Access to valid GCP service account key
- [ ] GitHub CLI configured
- [ ] User can export the key file

### Timeline
⏱️  **10-15 minutes total**

### Steps

```bash
# Step 1: Get the service account key
# (From your GCP project, download/export the key)
export SERVICE_ACCOUNT_KEY_FILE="/path/to/sa-key.json"

# Step 2: Validate the key format
cat "$SERVICE_ACCOUNT_KEY_FILE" | jq . > /dev/null || echo "Invalid JSON"

# Step 3: Set GitHub secret
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$(cat "$SERVICE_ACCOUNT_KEY_FILE")"

# Step 4: Also set base64 version for compatibility  
gh secret set GCP_SERVICE_ACCOUNT_KEY_B64 \
  --body "$(cat "$SERVICE_ACCOUNT_KEY_FILE" | base64 -w 0)"

# Step 5: Trigger workflow
gh workflow run provision_phase3.yml --ref main \
  --input use_backend=github-direct

# Step 6: Monitor workflow
watch 'gh run list --workflow=provision_phase3.yml --limit=1 --json number,status,conclusion'

# Step 7: Check results
gh run view [RUN_ID] --log
```

### Expected Output
```
✓ Workflow created
✓ Run #20 (or next number)
✓ Status: IN_PROGRESS → COMPLETED
✓ Result: SUCCESS
✓ Infrastructure created in GCP
```

---

## Option C: Workload Identity (Most Secure)

### Requirements
- [ ] Workload Identity Pool already exists
- [ ] GitHub OIDC provider configured
- [ ] Service account with Workload Identity User binding

### Timeline
⏱️  **15 minutes total**

### Steps

```bash
# Step 1: Verify pool exists
gcloud iam workload-identity-pools describe terraform-pool \
  --location=global --project=gcp-eiq

# Step 2: Verify provider exists
gcloud iam workload-identity-pools providers describe github \
  --location=global \
  --workload-identity-pool=terraform-pool \
  --project=gcp-eiq

# Step 3: Trigger workflow (no secrets needed!)
gh workflow run provision_phase3.yml --ref main \
  --input use_backend=workload-identity

# Step 4: Monitor
watch 'gh run list --workflow=provision_phase3.yml --limit=1'
```

### Advantages
✅ No secrets to manage  
✅ Ephemeral tokens (15 min lifetime)  
✅ Most secure (0 credential exposure)  
✅ Audit trail automatic  

---

## Decision Criteria

| Option | Effort | Security | Speed | Best For |
|--------|--------|----------|-------|----------|
| A | Medium | High | 5 min | Internal teams with GCP access |
| B | Low | Medium | 10 min | External teams managing credentials |
| C | Low | Highest | 15 min | Zero-trust, production environments |

---

## Architecture Compliance

All options maintain 6 architecture principles:

✅ **Immutable:** Steps documented, audit trail in GitHub  
✅ **Ephemeral:** OIDC tokens used, ephemeral keys when needed  
✅ **Idempotent:** Terraform state-based, safe to rerun  
✅ **No-Ops:** Workflows fully automated  
✅ **Hands-Off:** GitHub Actions execution  
✅ **GSM/Vault/KMS:** Multi-layer support across all options  

---

## Troubleshooting

### "terraform init" fails
```bash
# Solution: Check backend configuration
cd infra
rm -rf .terraform terraform.tfstate*
terraform init
```

### "Invalid credentials" error
```bash
# Solution: Validate key format
cat /path/to/sa-key.json | jq . 

# Should see:
# {
#   "type": "service_account",
#   "project_id": "gcp-eiq",
#   "private_key": "...",
#   "client_email": "...",
#   ...
# }
```

### Workflow still fails
```bash
# Check logs:
gh run view [RUN_ID] --log | tail -50

# Check secrets are set:
gh secret list --repo kushin77/self-hosted-runner
```

---

## Next Steps After Success

1. ✅ Verify infrastructure created in GCP
2. ✅ Test OIDC token with GCP resources
3. ✅ Close issue #1813 (unblock tracking)
4. ✅ Merge PRs #1802, #1807
5. ✅ Update master status (Phase 3 complete)
6. ✅ Start Phase 4 (if applicable)

---

**Choose your option above and execute within 1 hour to complete Phase 3.**

