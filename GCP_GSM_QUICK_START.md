# GCP GSM Quick Start Guide

**Estimated Setup Time**: 30-45 minutes  
**Status**: ✅ Production Ready  
**Last Updated**: March 8, 2026

---

## Quick Links
- [Full Integration Guide](GCP_GSM_INTEGRATION_GUIDE.md)
- [Architecture Details](GCP_GSM_ARCHITECTURE.md)
- [Troubleshooting](GCP_GSM_INTEGRATION_GUIDE.md#troubleshooting)

---

## 5-Minute Setup

### Prerequisites Checklist
- [ ] Google Cloud Project (active)
- [ ] GitHub repository owner access
- [ ] `gcloud` CLI installed locally
- [ ] `gh` CLI configured

### Setup Steps

#### 1. Create GCP Service Account (3 min)
```bash
PROJECT_ID="your-project-id"

# Create service account
gcloud iam service-accounts create github-gsm-manager \
  --project="$PROJECT_ID" \
  --display-name="GitHub GSM Manager"

# Get full email
SERVICE_ACCOUNT="github-gsm-manager@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant secret admin permissions
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.admin"
```

#### 2. Setup OIDC (5 min)
```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

# Create OIDC provider
gcloud iam workload-identity-pools providers create-oidc \
  "github-provider" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant workload identity permissions
gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_ID/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_ORG/YOUR_REPO"

# Get workload identity provider
PROVIDER=$(gcloud iam workload-identity-pools describe github-pool \
  --project="$PROJECT_ID" \
  --location=global \
  --format='value(name)')
echo "PROVIDER: $PROVIDER"
```

#### 3. Add GitHub Secrets (2 min)
```bash
# Get values
PROJECT=$(gcloud config get-value project)
SERVICE_ACCOUNT=$(gcloud iam service-accounts list --filter="email:github-gsm-manager@" --format="value(email)")
PROVIDER="projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

# Add secrets
gh secret set GCP_PROJECT_ID --body "$PROJECT"
gh secret set GCP_SERVICE_ACCOUNT_EMAIL --body "$SERVICE_ACCOUNT"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$PROVIDER"
```

#### 4. Configure Secret Sync (1 min)
```bash
# Add secrets you want to sync
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$(cat /path/to/key.json)"
gh secret set AWS_OIDC_ROLE_ARN --body "arn:aws:iam::ACCOUNT:role/github-oidc"

# That's it! System does the rest
```

---

## Verify Setup (2 min)

### Test 1: Manual Sync Trigger
```bash
gh workflow run gcp-gsm-sync-secrets.yml

# Check status
gh run list --workflow=gcp-gsm-sync-secrets.yml --limit 1
```

### Test 2: Verify in GSM
```bash
gcloud secrets list --filter="labels.gh-saas-sync:true"
```

### Test 3: Check Issue #1381
```bash
gh issue view 1381

# Should show recent sync status comments
```

✅ **If all three tests pass, you're ready!**

---

## Daily Operations

### Add a New Secret to GSM
```bash
# 1. Add to GitHub
gh secret set NEW_SECRET_NAME --body "secret-value"

# 2. Update sync script (one-time)
nano scripts/automation/gcp-gsm-sync.sh
# Add to secrets_to_sync array:
#   "NEW_SECRET_NAME:gsm-secret-name"

# 3. Next sync cycles automatically (or trigger)
gh workflow run gcp-gsm-sync-secrets.yml

# 4. Verify in GSM
gcloud secrets versions access latest --secret="gsm-secret-name"
```

### Rotate a Credential
```bash
# 1. Generate new value in source system
# (e.g., AWS IAM, GCP service account, etc.)

# 2. Update GitHub secret
gh secret set SECRET_NAME --body "new-value"

# 3. System automatically:
#    - Syncs to GSM (next 15-min cycle)
#    - Creates new version
#    - Keeps old version for 30 days
#    - Archives if 3+ versions exist

# 4. Verify
gcloud secrets versions list SECRET_NAME
```

### Check Rotation Status
```bash
# View rotation audit report
gh workflow run gcp-gsm-rotation.yml

# Or check issue #1381 for daily updates
gh issue view 1381 --comments | grep -A 30 "Rotation Check"
```

---

## Emergency Procedures

### Step 1: Suspected Breach
```bash
# Option A: Comment on any issue
# @github-actions /breach gcp-service-account

# Option B: Manual workflow trigger
gh workflow run gcp-gsm-breach-recovery.yml \
  -f action=compromise \
  -f secret_name=aws-oidc-role-arn \
  -f reason="github_leak_detected"
```

### Step 2: System Response (Automatic)
- ✅ Secret revoked in < 2 minutes
- ✅ All versions destroyed
- ✅ Incident report generated
- ✅ High-priority issue created
- ✅ Slack notification sent (if configured)

### Step 3: Operator Actions
1. Review incident report (issue #XXXX)
2. Investigate how breach happened
3. Generate new credential in source system
4. Update GitHub secret
5. Monitor for unauthorized usage

---

## Common Tasks Reference

| Task | Command |
|------|---------|
| **List synced secrets** | `gcloud secrets list --filter="labels.gh-saas-sync:true"` |
| **Get secret value** | `gcloud secrets versions access latest --secret="SECRET_NAME"` |
| **Rotate all secrets** | `gh workflow run gcp-gsm-breach-recovery.yml -f action=mass-rotate` |
| **View sync logs** | `gh run view $(gh run list --workflow=gcp-gsm-sync-secrets.yml --limit 1 --json databaseId --jq '.[0].databaseId') --log` |
| **Check rotation dates** | `gcloud secrets versions list SECRET_NAME --format="table(name,create_time,state)"` |
| **Force rotation check** | `gh workflow run gcp-gsm-rotation.yml` |
| **Revoke secret** | `gh workflow run gcp-gsm-breach-recovery.yml -f action=revoke -f secret_name=SECRET_NAME` |
| **Check compliance** | `gh issue view 1381` |

---

## Status Dashboard

Check system health:

```bash
echo "=== GCP GSM System Status ==="

echo "✓ Sync Status:"
gh run view $(gh run list --workflow=gcp-gsm-sync-secrets.yml --limit 1 --json databaseId --jq '.[0].databaseId') --json conclusion

echo ""
echo "✓ Synced Secrets:"
gcloud secrets list --filter="labels.gh-saas-sync:true" --format="table(name,created)" | tail -10

echo ""
echo "✓ Rotation Status:"
gh run view $(gh run list --workflow=gcp-gsm-rotation.yml --limit 1 --json databaseId --jq '.[0].databaseId') --json conclusion

echo ""
echo "✓ Tracking Issues:"
gh issue list --search "label:gcp-gsm" --limit 5
```

---

## Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| **Sync fails with auth error** | Verify GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT_EMAIL secrets are set |
| **Secret not syncing** | Add to `secrets_to_sync` array in gcp-gsm-sync.sh, commit, redeploy |
| **Rotation check fails** | Run `gcloud secrets list` manually to verify GSM access |
| **Emergency response not triggering** | Add `emergency` label to issue, use `/breach` command in comment |
| **Can't see sync logs** | Check issue #1381 comments, or use `gh run view --log` |

---

## Important Configuration Files

```
.github/workflows/
├── gcp-gsm-sync-secrets.yml      ← Runs every 15 min
├── gcp-gsm-rotation.yml           ← Runs daily at 2 AM UTC
├── gcp-gsm-breach-recovery.yml    ← Manual trigger for emergencies
└── store-slack-to-gsm.yml         ← Store leaked secrets

scripts/automation/
├── gcp-gsm-sync.sh               ← Core sync logic
├── gcp-gsm-rotation.sh           ← Rotation checks
└── gcp-gsm-emergency-recovery.sh ← Emergency response
```

---

## Key Behaviors (No Manual Setup Needed)

### Automatic Every 15 Minutes
- Sync GitHub secrets → GCP Secret Manager
- Create new versions if changed
- Archive audit logs
- Update issue #1381

### Automatic Daily (2 AM UTC)
- Check all secrets against TTL policy
- Create rotation issues for overdue credentials
- Archive old versions (keep 3)
- Generate compliance report

### Automatic On Breach Detection
- Revoke compromised secret (< 2 min)
- Destroy all versions
- Create incident issue
- Notify via Slack

---

## Next Steps

1. **Complete Setup** (above)
2. **Verify Sync** works (see "Verify Setup")
3. **Test Rotation** manually: `gh workflow run gcp-gsm-rotation.yml`
4. **Monitor Issue #1381** for auto-updates
5. **Read Full Guide** if you need deeper knowledge (link above)

---

## Support

| Type | Channel |
|------|---------|
| **Setup Help** | See [GCP_GSM_INTEGRATION_GUIDE.md](GCP_GSM_INTEGRATION_GUIDE.md) |
| **Architecture Questions** | See [GCP_GSM_ARCHITECTURE.md](GCP_GSM_ARCHITECTURE.md) |
| **Bug Report** | Open issue with label `gcp-gsm` |
| **Emergency** | Use `/breach` comment or `gh workflow run gcp-gsm-breach-recovery.yml` |

---

**Remember**: This system is fully automated and hands-off once configured. Your only job is to:
1. Keep GitHub secrets updated (add/refresh values)
2. Monitor issue #1381 for rotation alerts
3. Respond to emergency incidents

Everything else happens automatically. 🚀
