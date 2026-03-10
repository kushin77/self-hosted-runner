# 🚀 NexusShield Go-Live Runbook
**Date:** 2026-03-10  
**Status:** Ready for deployment (GCP credentials required)  
**Framework:** Direct Deployment Automation

---

## ⚡ Quick Start (5-10 minutes)

### Step 1: Unblock GCP Credentials (Choose One Method)

#### Method A: Refresh ADC (requires browser)
```bash
gcloud auth application-default login
# Opens browser for OAuth
```

#### Method B: Use Service Account Key (recommended)
```bash
# 1. Obtain service account key from GCP console
#    (Service account: nexusshield-prod)

# 2. Set the credential path
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/nexusshield-sa-key.json

# 3. Verify connection
gcloud auth list
gcloud config set project nexusshield-prod
```

#### Method C: Fix ADC JSON Directly
```bash
# Edit ~/.config/gcloud/application_default_credentials.json
# Ensure it contains the following fields (examples):
# - type: "authorized_user"
# - client_id: "...(from GCP console)..."
# - refresh_token: "...(from oauth flow)..."
cat ~/.config/gcloud/application_default_credentials.json | jq .
```

### Step 2: Run Deployment (1 command)
```bash
bash scripts/go-live-kit/02-deploy-and-finalize.sh
```

**What this does:**
- ✅ Validates GCP credentials
- ✅ Runs Terraform apply (full infrastructure)
- ✅ Deploys containers via Docker Compose
- ✅ Creates Cloud Scheduler jobs
- ✅ Runs final validation (22 tests)
- ✅ Closes GitHub tracking issues
- ✅ Records immutable audit entry
- ✅ Reports operational status

**Expected duration:** 5-10 minutes  
**Expected output:** "✅ GO-LIVE COMPLETE"

---

## 📋 What's Already Done

### Framework & Automation (100% complete)
- ✅ Systemd credential rotation timer (installed + enabled)
- ✅ Systemd git maintenance timer (installed + enabled)
- ✅ Validation test suite (22/22 passing)
- ✅ Encrypted credential cache (`/etc/nexusshield/credcache.enc`)
- ✅ Direct deployment script (`scripts/direct-deploy-no-actions.sh`)
- ✅ Branch protection (main + production)
- ✅ No-GitHub-Actions policy enforced

### Security & Compliance (100% complete)
- ✅ 4-layer credential fallback (GSM → Vault → KMS → local-cache)
- ✅ Immutable JSONL audit logging
- ✅ Secret scanning and redaction
- ✅ All credentials encrypted in transit/at-rest
- ✅ Pre-commit hooks preventing secrets commits

### Documentation (100% complete)
- ✅ Production operational status report
- ✅ Terraform state restore runbook
- ✅ Validation reports
- ✅ Audit trail (GitHub + JSONL)

---

## 🔄 What Step 2 Will Do

### Phase 1: Terraform Apply (2-3 min)
```
Firestore API → Enabled
Service accounts → Created (portal-backend, tfstate-backup)
VPC → Created (nexusshield-vpc)
GCS bucket → Created (terraform-state-backups)
Secret Manager → Configured (firestore-config)
Artifact Registry → Created (portal-backend-repo)
```

### Phase 2: Container Deployment (2-3 min)
```
- Launches docker-compose services
- Starts all container images
- Waits for health checks to pass
- Verifies connectivity
```

### Phase 3: Cloud Scheduler Setup (1 min)
```
- backup-tfstate: Every 6 hours
- health-check-nexusshield: Every 4 hours
- cleanup-stale-resources: Daily 4 AM
```

### Phase 4: Validation & Closure (1 min)
```
- Runs 22-test validation suite
- Closes GitHub issues #2286 #2287
- Records final audit entry
- Displays operational summary
```

---

## ✅ Post-Deployment (Automatic Operations)

Once deployed, the following run **fully hands-off**:

| Task | Schedule | Handler | Status |
|------|----------|---------|--------|
| Credential rotation | Daily 2 AM | Systemd timer | ✅ Active |
| Git maintenance | Weekly Sun 1 AM | Systemd timer | ✅ Active |
| Terraform backup | Every 6 hours | Cloud Scheduler | ⏳ After deploy |
| Health checks | Every 4 hours | Cloud Scheduler | ⏳ After deploy |
| Resource cleanup | Daily 4 AM | Cloud Scheduler | ⏳ After deploy |

All operations are:
- **Immutable:** Append-only audit logs
- **Ephemeral:** Temporary containers clean up after each run
- **Idempotent:** Safe to run repeatedly
- **No-Ops:** Fully automated, zero manual intervention
- **Hands-Off:** No GitHub Actions, no PR workflows

---

## 🔍 Monitoring & Verification

### Check Systemd Timers
```bash
systemctl status nexusshield-credential-rotation.timer
systemctl status nexusshield-git-maintenance.timer
journalctl -u nexusshield-credential-rotation -n 20 -f
```

### Check Container Health
```bash
docker-compose -f docker-compose.phase6.yml ps
docker-compose -f docker-compose.phase6.yml logs --tail=20
```

### Check Cloud Scheduler Jobs
```bash
gcloud scheduler jobs list --project=nexusshield-prod
gcloud scheduler jobs run backup-tfstate --project=nexusshield-prod
```

### Run Validation Manually
```bash
bash scripts/validate-automation-framework.sh
```

---

## 🚨 Troubleshooting

### Issue: "oauth2: token expired"
**Solution:** Refresh credentials:
```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json
gcloud auth list  # verify
bash scripts/go-live-kit/02-deploy-and-finalize.sh
```

### Issue: "Terraform plan failed"
**Solution:** Check state bucket:
```bash
gcloud storage buckets list --project=nexusshield-prod
terraform -chdir=terraform/ refresh -var="gcp_project=nexusshield-prod"
```

### Issue: "Cloud Scheduler job creation failed"
**Solution:** Verify API enabled:
```bash
gcloud services enable cloudscheduler.googleapis.com --project=nexusshield-prod
bash scripts/go-live-kit/02-deploy-and-finalize.sh  # retry
```

### Issue: "Containers not starting"
**Solution:** Check logs:
```bash
docker-compose -f docker-compose.phase6.yml logs
docker-compose -f docker-compose.phase6.yml down && up -d
```

---

## 📞 Support & Escalation

**Immediate Issues:**
1. Check deployment logs: `deployments/deployment_attempts.jsonl`
2. Check GitHub issue comments: #2286, #2287, #2294
3. Run validation: `bash scripts/validate-automation-framework.sh`

**GCP Issues:**
- Verify project: `gcloud config get-value project`
- Check IAM roles: `gcloud projects get-iam-policy nexusshield-prod`
- Check API quota: `gcloud compute project-info describe --project=nexusshield-prod`

**GitHub Issues:**
- All tracking issues have detailed comments with latest status
- Immutable audit trail available in `deployments/`
- All commits use conventional commit messages for easy tracking

---

## 📊 Expected Results (Post-Deployment)

```
Framework Status: ✅ OPERATIONAL
System Uptime: 99.9%
Timers Active: 2/2
Containers Running: 31 (per Phase 6)
Health Checks: Passing
Cloud Scheduler Jobs: 3/3 active
Automation Tests: 22/22 passing
Security Audit: ✅ Passed
Credential Rotation: ✅ Automatic (daily)
State Backup: ✅ Automatic (6-hourly)
```

---

## 🎯 Next Steps

1. **Now:** Choose a credential method (A, B, or C above)
2. **5 min:** Run: `bash scripts/go-live-kit/02-deploy-and-finalize.sh`
3. **10 min:** Verify operational status
4. **Post-deploy:** Monitor timers and scheduler jobs (automatic)

---

## 📝 Immutable Audit Trail

All deployment events recorded in:
- `deployments/deployment_attempts.jsonl` (append-only)
- GitHub issue comments (#2286, #2287, #2294)
- Git commit log (all direct to `main`, no PRs)

Latest commits:
- 06ea6fe84: Production operational status
- 059ff89df: GCP auth blocker audit
- 1d425fb3f: Production handoff summary

---

**Status:** Framework READY ✅ | Awaiting GCP credentials ⏳ | Time to go-live: 10 minutes ⏱️

Execute: `bash scripts/go-live-kit/01-unblock-gcp-credentials.sh` to verify your setup, then run: `bash scripts/go-live-kit/02-deploy-and-finalize.sh` to deploy.
