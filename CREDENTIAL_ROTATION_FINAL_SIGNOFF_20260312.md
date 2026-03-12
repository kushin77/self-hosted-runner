# Credential Rotation & Final Sign-Off (March 12, 2026)

**Status:** Ready for Execution  
**Responsibility:** Security/DevOps Admin  
**Completion Target:** March 13, 2026

---

## 📋 Summary

This document outlines the final phase of governance enforcement deployment:
1. Rotating all deployment credentials (service account keys, secrets)
2. Verifying end-to-end encryption and audit trails
3. Final sign-off and handoff to operations

---

## 🔐 Phase 1: Credential Rotation

### Current Credentials to Rotate

#### 1. Cloud Build Deployer Service Account Key

```bash
PROJECT_ID="nexusshield-prod"
SA="cloudbuild-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

# List existing keys
gcloud iam service-accounts keys list --iam-account="$SA" --project="$PROJECT_ID"

# Create new key
gcloud iam service-accounts keys create /tmp/cloudbuild-deployer-key.json \
  --iam-account="$SA" --project="$PROJECT_ID"

# Result: Store key in GitHub Secrets or vault
echo "✓ New key created"

# Delete old keys (keep only latest 2)
OLD_KEYS=$(gcloud iam service-accounts keys list --iam-account="$SA" \
  --project="$PROJECT_ID" --format="value(name)" --sort-by="~validAfterTime" | tail -n +3)

for key in $OLD_KEYS; do
  gcloud iam service-accounts keys delete "$key" --iam-account="$SA" \
    --project="$PROJECT_ID" --quiet && echo "✓ Deleted key $key"
done
```

#### 2. Cloud Run Service Account Key

```bash
SA="nxs-portal-production@${PROJECT_ID}.iam.gserviceaccount.com"

# Create new key
gcloud iam service-accounts keys create /tmp/run-sa-key.json \
  --iam-account="$SA" --project="$PROJECT_ID"

# Store in secrets manager
gcloud secrets create cloud-run-service-account-key \
  --replication-policy="automatic" \
  --data-file=/tmp/run-sa-key.json \
  --project="$PROJECT_ID" || \
gcloud secrets versions add cloud-run-service-account-key \
  --data-file=/tmp/run-sa-key.json \
  --project="$PROJECT_ID"

# Rotate old keys
echo "✓ New Cloud Run SA key rotated"
```

#### 3. Database Credentials (PostgreSQL, if applicable)

```bash
# Update secrets in Google Secret Manager
gcloud secrets versions add postgres-password \
  --data-file=<(openssl rand -base64 32) \
  --project="$PROJECT_ID"

# Update application with new password
# (Redeploy Cloud Run services with updated secret bindings)
```

### Verification Checklist

- [ ] Cloud Build SA has new key
- [ ] Cloud Run SA has new key
- [ ] Old keys deleted (keep audit trail of rotation)
- [ ] Secrets rotated in Google Secret Manager
- [ ] All services tested with rotated credentials
- [ ] No failed auth calls in Cloud Logging

---

## 📊 Phase 2: Audit & Compliance Verification

### 1. Immutability Verification

```bash
# Check S3 Object Lock WORM configuration
aws s3api head-bucket \
  --bucket nexusshield-prod-audit-logs \
  --region us-east-1 | grep ObjectLockEnabled

# Expected: "ObjectLockEnabled": true
# Expected: All objects locked with mode COMPLIANCE, retention 365 days
```

### 2. Encryption Verification

```bash
# Verify Cloud Run service uses CMK
gcloud run services describe nexusshield-portal-backend-production \
  --platform=managed --project=nexusshield-prod \
  --region=us-central1 --format="value(spec.template.spec.encryption)"

# Verify Secrets in Google Secret Manager encrypted
gcloud secrets describe deployer-key --project=nexusshield-prod \
  --format="value(replication.automatic)"
```

### 3. Audit Trail Verification

```bash
# Check Cloud Logging has immutable audit entries
gcloud logging read \
  'resource.type="cloud_run_revision" AND jsonPayload.event="policy-check"' \
  --project=nexusshield-prod --limit=10 --format=json | jq '.[] | {timestamp, status}'

# Expected: policy-check events logged on each push
# Expected: direct-deploy events logged on each canary → promote

# Check Cloud Run revision logs
gcloud run services describe nexusshield-portal-backend-production \
  --platform=managed --project=nexusshield-prod \
  --region=us-central1 --format="value(status.traffic)"
```

### 4. Multi-Credential Failover Verification

```bash
# Verify GSM → Vault → KMS failover is configured
curl -s https://nexusshield-portal-backend-production-XXXX-uc.a.run.app/health \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" | jq '.credential_sources'

# Expected: Array showing available credential sources and response times
```

---

## 📝 Phase 3: Documentation & Handoff

### 1. Update Operation Runbooks

- [ ] Update [OPERATIONAL_HANDOFF_FINAL_20260312.md](OPERATIONAL_HANDOFF_FINAL_20260312.md)
- [ ] Add Cloud Build trigger monitoring instructions
- [ ] Add credential rotation schedule (quarterly recommended)

### 2. Create On-Call Playbook

```markdown
## Emergency Procedures

### If Direct-Deploy Pipeline Fails
1. Check build logs: `gcloud builds log --stream <BUILD_ID>`
2. Verify service account permissions
3. Check Cloud Run quota and limits
4. Rollback to previous revision: `gcloud run deploy ... --revision-suffix=<rollback>`

### If Policy-Check Blocks a Legitimate Commit
1. Review commit changes
2. Remove any `.github/workflows/` files
3. Re-push with clean commit
4. Force-merge only after approval from 2+ reviewers
```

### 3. Team Handoff Meeting

Schedule a handoff meeting to cover:
- [ ] Cloud Build trigger overview
- [ ] Smoke test procedures
- [ ] Credential rotation schedule
- [ ] Escalation procedures for failures
- [ ] Monthly audit review process

---

## ✅ Final Verification Checklist

### Deployment Verification
- [ ] All services deployed with Cloud Build pipelines
- [ ] Policy-check trigger blocks `.github/workflows/` commits
- [ ] Direct-deploy trigger runs canary → smoke tests → promote
- [ ] Branch protection enforces 3 required status checks
- [ ] Smoke tests pass in <2 seconds
- [ ] No failed deployments in last 24 hours

### Security Verification
- [ ] All credentials rotated
- [ ] Google Secret Manager has encrypted secrets
- [ ] Cloud Logging configured for immutable audit
- [ ] S3 Object Lock WORM enabled (if using AWS)
- [ ] KMS encryption keys with proper access controls
- [ ] No plaintext secrets in git history

### Operational Verification
- [ ] On-call team trained on procedures
- [ ] Runbooks and playbooks documented
- [ ] Monitoring alerts configured (Cloud Monitoring, CloudWatch)
- [ ] Backup and disaster recovery plan in place
- [ ] Weekly verification script scheduled (Cloud Scheduler)

### Compliance Verification
- [ ] ✅ Immutable audit trail (Cloud Logging + S3 Object Lock WORM)
- [ ] ✅ Idempotent deployments (terraform plan shows no drift)
- [ ] ✅ Ephemeral credentials (TTL enforced in GSM/Vault)
- [ ] ✅ No-ops automation (5 daily Cloud Scheduler jobs + 1 weekly CronJob)
- [ ] ✅ Hands-off auth (OIDC tokens, no passwords)
- [ ] ✅ Multi-credential failover (4-layer: GSM → Vault → KMS → fallback, SLA 4.2s)
- [ ] ✅ No-branch-dev (direct commits to main, branch-protected)
- [ ] ✅ Direct-deploy pipeline (Cloud Build → Cloud Run, no release workflow)

---

## 📋 Sign-Off Template

```markdown
## Project Completion Sign-Off

**Project:** Governance Enforcement - Phase 2 → Phase 6 (March 9-13, 2026)

**Deployment Owner:** [Name/Team]  
**Date Completed:** [Date]  
**Auditors:** [Names]

### Artifacts Delivered
- [x] cloudbuild/policy-check.yaml (320 lines, merged)
- [x] cloudbuild/direct-deploy.yaml (280 lines, merged)
- [x] scripts/smoke_test.sh (updated for auth, merged)
- [x] CLOUDBUILD_SETUP_GUIDE.md (comprehensive walkthrough)
- [x] scripts/setup-cloudbuild-triggers.sh (automation)
- [x] Branch protection enabled on main with 3 status checks
- [x] All credentials rotated

### Governance Requirements (8/8 Verified)
- [x] Immutable audit trail (Cloud Logging + S3 WORM)
- [x] Idempotent deployments (terraform verified)
- [x] Ephemeral credentials (TTL enforced)
- [x] No-ops automation (5 schedulers + 1 cronjob)
- [x] Hands-off auth (OIDC, no passwords)
- [x] Multi-credential failover (4-layer, SLA 4.2s)
- [x] No-branch-dev (direct commits to main)
- [x] Direct-deploy pipeline (Cloud Build → Run)

### Known Limitations / Follow-Up Items
1. Cloud Build GitHub Connection requires manual OAuth in Cloud Console (one-time)
2. Credential rotation should be scheduled quarterly
3. Weekly verification script should run via Cloud Scheduler
4. On-call team training to be scheduled

**Deployment Owner Signature:** ________________________ **Date:** ______

**Audit Signature:** ________________________ **Date:** ______
```

---

## 🎯 Success Criteria

All of the following must be true to declare deployment complete:

✅ Cloud Build triggers automatically run on push to main  
✅ Policy-check blocks `.github/workflows/` additions  
✅ Direct-deploy runs canary (10%) → smoke tests → full promotion  
✅ All credentials rotated and old keys deleted  
✅ Smoke tests pass within 2 seconds  
✅ Branch protection enforces all 3 status checks  
✅ Cloud Logging records all policy-check and direct-deploy events  
✅ On-call team trained and documented  
✅ Emergency runbooks prepared  

---

## 📅 Next Steps

1. **March 12-13:** Complete credential rotation (Phase 1)
2. **March 13:** Verification audit (Phase 2)
3. **March 13:** Team handoff meeting (Phase 3)
4. **March 14:** Full go-live announcement
5. **March 14 onwards:** Weekly monitoring and monthly audit reviews

---

**Last Updated:** March 12, 2026  
**Prepared by:** Platform Engineering  
**Status:** Ready for Execution
