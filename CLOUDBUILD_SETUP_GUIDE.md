# Cloud Build Setup & Trigger Configuration Guide

**Date:** March 12, 2026  
**Status:** Ready for deployment  
**Responsibility:** Platform/DevOps Admin

---

## 📋 Overview

This guide provides step-by-step instructions for setting up Cloud Build repository connections and creating automated CI/CD triggers for the governance enforcement pipeline.

### What You're Setting Up
1. **Cloud Build ↔ GitHub Connection** (one-time OAuth)
2. **policy-check trigger** — blocks commits with prohibited GitHub Actions workflows
3. **direct-deploy trigger** — builds, scans, canary-deploys, and promotes services

---

## 🔧 Manual Setup: Cloud Build Repository Connection

> **ℹ️ Note:** This is a one-time setup. Once complete, you won't need to repeat it.

### Step 1: Navigate to Cloud Console

1. Open [Cloud Console](https://console.cloud.google.com)
2. Select project **`nexusshield-prod`** from the project selector
3. Navigate to **Cloud Build → Repositories**

### Step 2: Connect Your Repository

1. Click **"Connect Repository"** button
2. Select **GitHub** as the source
3. Click **"Authorize GitHub App"**
   - You'll be redirected to GitHub's OAuth authorization screen
   - Grant the required permissions (repo access, workflow access)
4. Return to Cloud Console and select the repository:
   - **Owner:** `kushin77`
   - **Repository:** `self-hosted-runner`
5. Click **"Connect Selected Repository"**

**Expected Outcome:**  
You should see the repository listed with a green checkmark in the Repositories table.

---

## ⚙️ Automated Trigger Creation

### Step 3: Run the Trigger Setup Script

Once the repository connection is complete, run:

```bash
bash scripts/setup-cloudbuild-triggers.sh
```

**What this script does:**
- ✅ Verifies the repository connection exists
- ✅ Creates the `policy-check-trigger` (on every push to main)
- ✅ Creates the `direct-deploy-trigger` (builds and deploys)
- ✅ Confirms both triggers are active

**Expected Output:**
```
[SETUP] HH:MM:SS Starting Cloud Build trigger setup...
[SETUP] HH:MM:SS Step 1/4: Verifying Cloud Build repository connection...
[✓] Repository connection verified
[SETUP] HH:MM:SS Step 2/4: Creating policy-check trigger...
[✓] Created policy-check-trigger
[SETUP] HH:MM:SS Step 3/4: Creating direct-deploy trigger...
[✓] Created direct-deploy-trigger
[SETUP] HH:MM:SS Step 4/4: Verifying triggers...
[✓] All triggers created successfully

✅ Cloud Build setup complete!
```

---

## 📊 Verification Checklist

After completing the setup, verify everything is working:

### 1. Verify Triggers Are Created
```bash
gcloud builds triggers list --project=nexusshield-prod --region=us-central1 \
  --format="table(name,filename,branch_name)"
```

Expected output:
```
NAME                    | FILENAME                    | BRANCH_NAME
policy-check-trigger    | cloudbuild/policy-check.yaml | main
direct-deploy-trigger   | cloudbuild/direct-deploy.yaml | main
```

### 2. Test Policy-Check Trigger

Create a test workflow file to verify the policy-check gate:

```bash
# Create a test GitHub Actions workflow
mkdir -p .github/workflows
cat > .github/workflows/test.yml << 'EOF'
name: Test Workflow
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "This violates the no-workflows policy"
EOF

# Push to main
git add .github/workflows/test.yml
git commit -m "test: Attempt to add workflow (should be blocked)"
git push origin main

# This should trigger policy-check and FAIL
# Check the build:
gcloud builds log --stream <BUILD_ID> --project=nexusshield-prod
```

Expected behavior:
- Build starts automatically
- `cloudbuild/policy-check.yaml` runs
- Build FAILS with message: "Detected github workflows in commit"
- The push succeeds (git history includes commit) but the build fails
- Revert the test workflow:

```bash
git revert HEAD
git push origin main
```

### 3. Test Direct-Deploy Trigger

Direct-deploy runs on successful policy-check:

```bash
# Make a legitimate code change
echo "# Updated README" >> README.md

git add README.md
git commit -m "docs: Update README"
git push origin main

# This should trigger:
# 1. policy-check → PASS (no workflows added)
# 2. direct-deploy → runs full pipeline
```

Monitor the build:
```bash
gcloud builds list --project=nexusshield-prod --region=us-central1 \
  --limit=5 --format="table(id,status,substitutions._BRANCH_NAME)"
```

### 4. Verify Smoke Tests Pass

The direct-deploy pipeline includes smoke tests. Check Cloud Run logs:

```bash
gcloud run services describe nexusshield-portal-backend-production \
  --platform=managed --project=nexusshield-prod --region=us-central1
```

---

## 🚨 Troubleshooting

### Issue: "Repository connection does not exist" Error

**Cause:** Cloud Build ↔ GitHub connection not completed  
**Solution:** Return to Step 2 and complete the OAuth authorization

### Issue: Triggers Not Firing Automatically

**Cause:** GitHub webhook not configured  
**Solution:**
```bash
# Verify webhook in GitHub repo settings:
# Settings → Webhooks → Should see Cloud Build webhook
# If missing, re-run the setup script

bash scripts/setup-cloudbuild-triggers.sh
```

### Issue: Direct-Deploy Failing

**Check:**
1. Cloud Build logs for specific error:
   ```bash
   gcloud builds log --stream <BUILD_ID> --project=nexusshield-prod
   ```

2. Service account permissions:
   ```bash
   gcloud projects get-iam-policy nexusshield-prod \
     --flatten="bindings[].members" \
     --filter="bindings.members:cloudbuild-deployer@"
   ```

3. Cloud Run service status:
   ```bash
   gcloud run services list --project=nexusshield-prod
   ```

---

## 📈 Monitoring & Maintenance

### View Build History
```bash
gcloud builds list --project=nexusshield-prod --region=us-central1 --limit=20
```

### View Specific Build Logs
```bash
gcloud builds log --stream <BUILD_ID> --project=nexusshield-prod
```

### Update Triggers
If you need to modify a trigger (e.g., change branch pattern):

```bash
# Delete and recreate
gcloud builds triggers delete policy-check-trigger \
  --project=nexusshield-prod --region=us-central1

# Then re-run the setup script
bash scripts/setup-cloudbuild-triggers.sh
```

---

## 🎯 Success Criteria

All of the following should be true:
- ✅ Cloud Build repository connection shown in Cloud Console
- ✅ Both triggers listed in `gcloud builds triggers list`
- ✅ Policy-check trigger blocks commits with `.github/workflows/` changes
- ✅ Direct-deploy trigger automatically runs on successful policy-check
- ✅ Smoke tests pass in direct-deploy pipeline
- ✅ Cloud Run services updated with new versions on each deploy

---

## 📞 Support

For issues or questions:
1. Check Cloud Build logs: `gcloud builds log --stream <BUILD_ID>`
2. Review Cloud Run service status
3. Verify IAM roles on service account: `gcloud projects get-iam-policy nexusshield-prod`
4. Check GitHub webhook configuration in repo settings

---

**Last Updated:** March 12, 2026  
**Maintained by:** Platform Engineering Team
