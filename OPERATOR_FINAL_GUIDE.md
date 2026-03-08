# Complete Operator Guide: From RCA to Resolution
**Status:** Ready for Operator Action  
**Est. Time:** 10 minutes

---

## 🎯 Your Goal
Replace placeholder secrets with real values and complete the multi-cloud deployment validation.

---

## 📋 3-Step Process

### **STEP 1: Understand the Issue (2 minutes)**

**What happened?**
- Health-check workflow ran but all layers reported failures
- This is not a bug — it's intentional validation with placeholder secrets
- See: [RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md](./RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md)

**Why placeholders?**
- Validated workflow logic without needing operator's real credentials
- Prevented accidentally creating resources in wrong accounts
- Demonstrated system works before operator invests effort

**Is this blocking production?**
- ❌ No. Primary OIDC deployment is already production-ready
- ⏳ Yes, multi-cloud optional layers need real credentials to complete

---

### **STEP 2: Gather Real Secret Values (5 minutes)**

You need to find 4 values from your infrastructure:

#### **Value 1: GCP_PROJECT_ID**
```bash
# Get your GCP project ID
gcloud config get-value project
```
**Example:** `my-project-123`

#### **Value 2: GCP_WORKLOAD_IDENTITY_PROVIDER**
```bash
# Get the Workload Identity Provider resource name
gcloud iam workload-identity-pools describe github \
  --location=global \
  --format='value(name)'
```
**Example:** `projects/123456789/locations/global/workloadIdentityPools/github/providers/github`

#### **Value 3: VAULT_ADDR**
From your Vault cluster documentation or operations team.
**Example:** `https://vault.internal.example.com:8200`

**Requirements:**
- Must be HTTPS
- Must be reachable from GitHub runners (public or VPN)
- Port 8200 (or your custom port) must be open

#### **Value 4: AWS_KMS_KEY_ID**
```bash
# Get KMS key ARN
aws kms list-keys --query 'Keys[0].KeyId' --output text
# Then get the full ARN
aws kms describe-key --key-id <key-id> --query 'KeyMetadata.Arn' --output text
```
**Example:** `arn:aws:kms:us-east-1:123456789:key/12345678-1234-1234-1234-123456789012`

**Requirements:**
- GitHub Actions role must have `kms:Decrypt` permission
- KMS key must be in same AWS account as GitHub OIDC role

---

### **STEP 3: Deploy Secrets via Script (3 minutes)**

**Option A: Interactive Script (Recommended)**

```bash
bash scripts/remediate-secrets-interactive.sh
```

This will:
1. ✅ Prompt you for each real value
2. ✅ Show summary before applying
3. ✅ Set all 4 repository secrets
4. ✅ Offer to trigger health-check workflow

**Option B: Manual CLI Commands**

```bash
# Set each secret individually
gh secret set GCP_PROJECT_ID -R kushin77/self-hosted-runner -b "YOUR_GCP_PROJECT_ID"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER -R kushin77/self-hosted-runner -b "YOUR_WIF_PROVIDER"
gh secret set VAULT_ADDR -R kushin77/self-hosted-runner -b "YOUR_VAULT_ADDR"
gh secret set AWS_KMS_KEY_ID -R kushin77/self-hosted-runner -b "YOUR_KMS_KEY_ID"

# Verify (values are hidden for security)
gh secret list -R kushin77/self-hosted-runner
```

**Option C: GitHub UI**

1. Go to: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions
2. Click "New repository secret"
3. For each of the 4 secrets above, add the name and real value
4. Click "Add secret"

---

## ✅ Validation Phase

### **Run Pre-Flight Checks**

```bash
bash scripts/validate-secrets-preflight.sh
```

This validates:
- ✅ Secrets are set
- ✅ Required tools installed
- ✅ OIDC environment ready

### **Trigger Health-Check Workflow**

```bash
gh workflow run secrets-health-multi-layer.yml \
  --repo kushin77/self-hosted-runner \
  --ref main
```

Or via GitHub UI:
1. Go to: https://github.com/kushin77/self-hosted-runner/actions
2. Select: `secrets-health-multi-layer.yml`
3. Click: "Run workflow" → "Run workflow"

### **Monitor the Run**

The workflow will take ~2-3 minutes. Watch it here:
https://github.com/kushin77/self-hosted-runner/actions/workflows/secrets-health-multi-layer.yml

**Expected Outcomes:**

| Scenario | Outcome | Next Action |
|----------|---------|-------------|
| All layers ✅ healthy | Perfect! Production ready | Reply to #1691, we close deployment |
| Some layers ⚠️ sealed/unavailable | Partially healthy (acceptable) | Operator fixes infra, re-run later |
| All layers ❌ unhealthy | Check your values | Review logs, troubleshoot (see guide below) |

### **Check Results**

View the full run output:
```bash
RUN_ID=<from workflow page>
gh run view $RUN_ID --repo kushin77/self-hosted-runner --log | tail -200
```

Look for this section:
```
📊 Health Summary:
  Layer 1 (GSM): [healthy|auth_failed|not_configured]
  Layer 2 (Vault): [healthy|unavailable|sealed|not_configured]
  Layer 3 (KMS): [healthy|unhealthy|not_configured]
  Primary: [GSM|Vault|KMS|NONE]
  Health: [healthy|degraded|unhealthy]
```

---

## 🆘 Troubleshooting

### **Layer 1 (GSM) Still Reports `auth_failed`**

**Possible causes:**
1. GCP_PROJECT_ID is invalid or doesn't exist
2. Workload Identity Provider resource name is incorrect
3. GitHub OIDC not configured in GCP

**Fix:**
```bash
# Verify GCP project ID
gcloud projects list

# Verify WIF provider exists
gcloud iam workload-identity-pools list --location=global

# Check WIF provider details
gcloud iam workload-identity-pools describe github --location=global

# Re-run with corrected values
bash scripts/remediate-secrets-interactive.sh
```

### **Layer 2 (Vault) Still Reports `unavailable`**

**Possible causes:**
1. VAULT_ADDR domain doesn't resolve
2. Vault address is private (not accessible from GitHub runners)
3. Vault port is blocked by firewall

**Fix:**
```bash
# Test connectivity from your local machine
curl -v https://YOUR_VAULT_ADDR/v1/sys/health

# If that works but workflow fails: Vault might be on private network
# Solution: Expose via VPN, proxy, or public endpoint

# Update secret with new address
gh secret set VAULT_ADDR -R kushin77/self-hosted-runner -b "NEW_VAULT_ADDR"
```

### **Layer 3 (KMS) Still Reports `unhealthy`**

**Possible causes:**
1. AWS_KMS_KEY_ID is invalid ARN format
2. Key doesn't exist in AWS account
3. GitHub Actions role lacks `kms:Decrypt` permission

**Fix:**
```bash
# Verify KMS key exists
aws kms describe-key --key-id YOUR_KMS_KEY_ID

# Check GitHub role permissions (ask admin)
# GitHub role must have: kms:Decrypt, kms:GenerateDataKey

# Update with valid key
gh secret set AWS_KMS_KEY_ID -R kushin77/self-hosted-runner -b "VALID_KMS_ARN"
```

### **Workflow Script Errors (Not Placeholder Related)**

If you see script execution errors, check:
1. Required tools installed: `gh`, `curl`, `jq`
2. GitHub token has permissions: `repo:read`, `secrets:read`
3. Network connectivity from runner to external services

---

## 📞 Final Confirmation

Once health-check passes (or partially passes):

1. **Reply to Issue #1691** with:
   - ✅ Real secrets provided
   - ✅ Health-check run link
   - ✅ Result summary (which layers healthy)

2. **Example reply:**
   ```
   ✅ Secrets replaced with real values
   - GCP_PROJECT_ID: my-project-123
   - VAULT accessible at: https://vault.internal
   - AWS KMS key verified
   
   Health-check run: https://github.com/.../runs/22824400000
   Results: Layer 1 ✅ healthy, Layer 2 ⚠️ sealed, Layer 3 ✅ healthy
   
   Ready for deployment completion!
   ```

3. **I will then:**
   - ✅ Close issues #1688 (incident) and #1691 (action)
   - ✅ Mark deployment 100% complete
   - ✅ Provide final sign-off

---

## ⏱️ Expected Timeline

| Step | Component | Est. Time |
|------|-----------|-----------|
| 1 | Read RCA | 2 min |
| 2 | Gather values | 3 min |
| 3 | Run script | 2 min |
| 4 | Health-check runs | 2 min |
| 5 | Review results | 1 min |
| **Total** | **From now to production** | **~10 min** |

---

## 🎉 Success Criteria

Deployment will be **100% complete** when:

✅ All 4 secrets set with real (non-placeholder) values  
✅ Health-check workflow runs successfully  
✅ At least Layer 3 (KMS) reports healthy  
✅ Operator confirms via reply to #1691  

---

## 📚 Additional Resources

- **Full RCA:** [RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md](./RCA_MULTI_LAYER_HEALTH_CHECK_FAILURES.md)
- **Architecture Guide:** [GCP_GSM_ARCHITECTURE.md](./GCP_GSM_ARCHITECTURE.md)
- **Developer Guide:** [DEVELOPER_SECRETS_GUIDE.md](./DEVELOPER_SECRETS_GUIDE.md)
- **Operational Runbook:** [FINAL_OPERATOR_DELIVERY.md](./FINAL_OPERATOR_DELIVERY.md)
- **Issue Tracking:** [#1691 - Action Required](https://github.com/kushin77/self-hosted-runner/issues/1691)

---

**Ready to proceed? Start with Step 1 above, then run the script in Step 3!**

*Generated: 2026-03-08 | Operator Handoff Complete*
