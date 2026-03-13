# Native Cloud Build Triggers Setup Guide

**Status**: Ready for org-admin execution  
**Prerequisites**: gcloud CLI + GitHub CLI authenticated  
**Time**: ~15 minutes  
**Date**: March 13, 2026  

---

## Quick Start (For Org Admin)

```bash
# 1. Clone or navigate to repository root
cd /path/to/self-hosted-runner

# 2. Set GCP project
export GCP_PROJECT=nexusshield-prod

# 3. Run setup script
bash scripts/setup/setup-native-cloud-build-triggers.sh
```

The script will:
- ✅ Authorize Cloud Build GitHub App (opens browser for OAuth)
- ✅ Create `policy-check-trigger` (governance validation)
- ✅ Create `direct-deploy-trigger` (production deployment)
- ✅ Apply branch protection rules
- ✅ Verify triggers are active

---

## Prerequisites

### Required Tools
```bash
# Google Cloud SDK
gcloud --version
# ⚠️ Run `gcloud init` if not configured

# GitHub CLI
gh --version
gh auth login
# ⚠️ Ensure authenticated with correct GitHub account
```

### Required Permissions
- **GCP**: org.admin or Cloud Build editor on project `nexusshield-prod`
- **GitHub**: Repository admin on `kushin77/self-hosted-runner`

---

## Step-by-Step Manual Setup (if script fails)

### Step 1: Create GitHub Connection

```bash
gcloud builds connections create github \
  --region=global \
  --name=github-connection \
  --project=nexusshield-prod
```

**Expected Output**:
```
Authorization flow starting...
[URL to authorize GitHub App]
```

Copy the URL, paste in browser, authorize Cloud Build GitHub App for `kushin77` organization.

### Step 2: Create Policy Check Trigger

```bash
gcloud builds triggers create github \
  --name="policy-check-trigger" \
  --region=global \
  --repo-owner=kushin77 \
  --repo-name=self-hosted-runner \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.policy-check.yaml \
  --project=nexusshield-prod \
  --service-account=projects/nexusshield-prod/serviceAccounts/prod-deployer@nexusshield-prod.iam.gserviceaccount.com
```

### Step 3: Create Direct Deploy Trigger

```bash
gcloud builds triggers create github \
  --name="direct-deploy-trigger" \
  --region=global \
  --repo-owner=kushin77 \
  --repo-name=self-hosted-runner \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml \
  --project=nexusshield-prod \
  --service-account=projects/nexusshield-prod/serviceAccounts/prod-deployer@nexusshield-prod.iam.gserviceaccount.com
```

### Step 4: Verify Triggers Created

```bash
gcloud builds triggers list \
  --project=nexusshield-prod \
  --filter="name:(policy-check-trigger OR direct-deploy-trigger)" \
  --format="table(name, filename, branch_name)"
```

**Expected Output**:
```
NAME                    FILENAME                      BRANCH_NAME
policy-check-trigger    cloudbuild.policy-check.yaml  main
direct-deploy-trigger   cloudbuild.yaml               main
```

### Step 5: Apply Branch Protection

Run from repository root:

```bash
TOKEN=$(gh auth token)

curl -X PUT "https://api.github.com/repos/kushin77/self-hosted-runner/branches/main/protection" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": ["policy-check-trigger", "direct-deploy-trigger"]
    },
    "required_pull_request_reviews": {
      "require_code_owner_reviews": true,
      "required_approving_review_count": 1
    },
    "enforce_admins": true,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "required_conversation_resolution": true,
    "restrictions": null
  }'
```

---

## Verification

### Test Cloud Build Workflow

```bash
# 1. Make a test commit
git commit --allow-empty -m "test: verify cloud build triggers"

# 2. Push to main
git push origin main

# 3. Watch Cloud Build
gcloud builds log $(gcloud builds list --limit=1 --format='value(id)') \
  --project=nexusshield-prod \
  --stream

# 4. Verify GitHub status
gh api repos/kushin77/self-hosted-runner/commits/main/status --jq '.state, .statuses[].context'
```

### Verify Branch Protection

```bash
# Check if main branch is protected
gh api repos/kushin77/self-hosted-runner/branches/main/protection \
  --jq '{protected: .protected, strict: .required_status_checks.strict, contexts: .required_status_checks.contexts}'
```

**Expected Output**:
```json
{
  "protected": true,
  "strict": true,
  "contexts": [
    "direct-deploy-trigger",
    "policy-check-trigger"
  ]
}
```

---

## Troubleshooting

### Issue: "INVALID_ARGUMENT: Request contains an invalid argument"

**Cause**: GitHub connection not authorized yet  
**Solution**: Run Step 1 first to authorize GitHub App

### Issue: Triggers not appearing in list

**Cause**: Region mismatch or connection not established  
**Solution**: 
```bash
# Verify connection exists
gcloud builds connections list --region=global --project=nexusshield-prod

# Check trigger list with more detail
gcloud builds triggers list --project=nexusshield-prod --format=json | jq .
```

### Issue: Branch protection API returns 422 error

**Cause**: Missing or invalid context names  
**Solution**: 
- Verify triggers are created: `gcloud builds triggers list`
- Ensure context names match exactly: `policy-check-trigger`, `direct-deploy-trigger`
- Try manual setup via GitHub Settings → Branches → main

### Issue: Git push doesn't trigger build

**Cause**: Native trigger not connected properly  
**Solution**:
- Webhook fallback is active: `cb-webhook-receiver` service
- Check Cloud Run logs: `gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=cb-webhook-receiver" --limit=50 --project=nexusshield-prod`

---

## Current System State

### Operational Components
✅ **Webhook Receiver** (`cb-webhook-receiver`) — active and monitoring  
✅ **Cloud Build Pipelines** — configured and ready  
✅ **GSM Secrets** — 26+ verified and accessible  
✅ **Service Accounts** — IAM roles granted (secretAccessor, cryptoKeyEncrypter, run.admin)  

### Pending Components
⏳ **GitHub Connection** — requires OAuth authorization  
⏳ **Native Triggers** — ready to create after OAuth  
⏳ **Branch Protection** — ready to apply after triggers exist  

---

## Rollback (If Needed)

```bash
# Delete triggers
gcloud builds triggers delete policy-check-trigger \
  --region=global --project=nexusshield-prod
gcloud builds triggers delete direct-deploy-trigger \
  --region=global --project=nexusshield-prod

# Delete connection
gcloud builds connections delete github-connection \
  --region=global --project=nexusshield-prod

# Remove branch protection
TOKEN=$(gh auth token)
curl -X DELETE "https://api.github.com/repos/kushin77/self-hosted-runner/branches/main/protection" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Support

For issues:
1. Check [CLOUD_BUILD_GOVERNANCE_IMPLEMENTATION_20260313.md](../../CLOUD_BUILD_GOVERNANCE_IMPLEMENTATION_20260313.md)
2. Review Cloud Build logs: `gcloud builds list --project=nexusshield-prod --limit=20 --format=json`
3. Check webhook receiver logs: `gcloud logging read 'resource.type="cloud_run_revision"' --project=nexusshield-prod --limit=100`
4. Post issue: `gh issue create --title "Cloud Build trigger setup issue" --body "..."`

---

**Status**: Ready for org-admin execution  
**Maintained**: March 13, 2026  
**Next Step**: Run `bash scripts/setup/setup-native-cloud-build-triggers.sh`
