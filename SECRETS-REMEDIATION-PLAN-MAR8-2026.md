# 🔐 Secrets Issues Remediation Plan (March 8, 2026)

## Executive Summary

**Status:** ALERT 🔴  
**Date:** 2026-03-08 05:15 UTC  
**Total Open Issues:** 47 secrets-related  
**Blocking Issues:** 2  
**Critical Failures:** All credential rotation workflows failing

---

## 🚨 IMMEDIATE CRITICAL ISSUES (FIX NOW)

### ❌ Issue #1464: Credential Rotation Failure - GCP Authentication Error

**Severity:** CRITICAL  
**Status:** 5 consecutive runs FAILED (last 1 hour)  
**Runs Failing:**
- credential-rotation-monthly.yml: 5/5 FAILED
- vault-kms-credential-rotation.yml: 3/3 FAILED

**Root Cause:**
```
gcloud.secrets.list Error:
"Unable to acquire impersonated credentials"
"Gaia id not found for email ***" (404)
```

**Why This Matters:**
- Vault-KMS-GSM credential rotation is completely broken
- Credentials cannot be synchronized across systems
- System is exposed to static credential risk
- Operator provisioning is blocked

**Fix Steps:**

1. **Verify GCP Service Account Exists**
   ```bash
   # Check which service account email is in the rotation workflow
   grep -i "GCP_SERVICE_ACCOUNT_EMAIL\|gcp.email\|impersonate" \
     .github/workflows/vault-kms-credential-rotation.yml
   
   # Verify the account exists in your GCP project
   gcloud iam service-accounts list --project=YOUR_PROJECT_ID
   ```

2. **Fix Workload Identity Federation (WIF) Configuration**
   ```bash
   # Verify WIF is properly set up
   gcloud iam workload-identity-pools list --location=global \
     --project=YOUR_PROJECT_ID
   
   # Verify WIF service account has GSM permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID \
     --flatten=bindings[].members \
     --filter='bindings.members:serviceAccount:YOUR_SA_EMAIL'
   ```

3. **Update Workflow Configuration**
   - Edit `.github/workflows/vault-kms-credential-rotation.yml`
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
   - Verify GCP_WORKLOAD_IDENTITY_PROVIDER is correct
   - Test with manual dispatch: `gh workflow run vault-kms-credential-rotation.yml --ref main`

4. **Validate the Fix**
   ```bash
   # Monitor the run
   gh run list --repo kushin77/self-hosted-runner \
     --workflow=vault-kms-credential-rotation.yml --limit 1
   ```

---

### ❌ Issue #1420: Missing AWS Credentials (Terraform Blocked)

**Severity:** HIGH / BLOCKING  
**Status:** Open (Awaiting Operator Action)  
**Impact:** Terraform pipeline cannot deploy

**Missing Secrets:**
- `AWS_ROLE_TO_ASSUME` — Not configured
- `AWS_REGION` — Not configured

**Fix Steps:**

1. **Add AWS_ROLE_TO_ASSUME**
   ```bash
   gh secret set AWS_ROLE_TO_ASSUME \
     --repo kushin77/self-hosted-runner \
     --body "arn:aws:iam::ACCOUNT_ID:role/github-actions-terraform"
   ```

2. **Add AWS_REGION**
   ```bash
   gh secret set AWS_REGION \
     --repo kushin77/self-hosted-runner \
     --body "us-east-1"
   ```

3. **Verify Secrets Were Set**
   ```bash
   gh secret list --repo kushin77/self-hosted-runner | grep AWS
   ```

4. **Trigger Terraform Pipeline Manually**
   ```bash
   gh workflow run terraform-plan.yml \
     --repo kushin77/self-hosted-runner --ref main
   ```

5. **Monitor Success**
   ```bash
   # Should see plan in issue #1384 comments within 5 minutes
   gh issue view 1384 --repo kushin77/self-hosted-runner
   ```

---

## 📋 CRITICAL ARCHITECTURE ISSUES (THIS WEEK)

### Issue #1474: Governance Consolidation Phase 2

**Problem:** Duplicate and overlapping workflows causing race conditions

**Overlaps Identified:**
1. **Readiness Checks** 
   - `pre-deployment-readiness-check.yml` (every 30m)
   - `deployment-readiness-check.yml` (weekly)
   - **Action:** MERGE into one parametrized workflow

2. **Secrets Sync**
   - `gcp-gsm-sync-secrets.yml` (every 15m)
   - `auto-activation-cascade.yml` (every 5m)
   - **Action:** CONVERT to event-driven (no polling)

3. **Remediation & Activation**
   - `remediation-dispatcher.yml` (every 5m)
   - `auto-activation-cascade.yml` (every 5m)
   - **Action:** COORDINATE or MERGE

4. **Terraform Orchestration**
   - `terraform-auto-apply.yml`
   - `full-deployment-orchestration.yml`
   - `phase-p3-pre-apply-orchestrator.yml`
   - **Action:** SERIALIZE with concurrency guards

**Remediation Steps:**

```bash
# 1. Identify all overlapping workflows
find .github/workflows -name "*.yml" | sort

# 2. Check for duplicate triggers
grep -h "^on:" .github/workflows/*.yml

# 3. Add concurrency guards to critical paths
# Edit each workflow to include:
concurrency:
  group: deployment-${{ github.ref }}
  cancel-in-progress: false

# 4. Convert polling to event-driven
# Replace cron schedules with:
on:
  workflow_dispatch: {}
  repository_dispatch:
    types: [event-name]
```

---

### Issue #1439: Multi-layer Credential Management

**Status:** Strategic Planning  
**Type:** Feature/Architecture  
**Scope:** Zero-static-secrets with 3-layer failover

**Architecture:**
```
┌─────────────────────────────────────────────────────┐
│          External Secret Systems                     │
├─────────────────────────────────────────────────────┤
│ Layer 1: HashiCorp Vault (Primary)                  │
│ ├─ OIDC auth from GitHub Actions                   │
│ ├─ AWS secret engine                               │
│ ├─ GCP secret engine                               │
│ └─ 24h credential TTL (ephemeral)                  │
├─────────────────────────────────────────────────────┤
│ Layer 2: AWS KMS (Secondary)                        │
│ ├─ Envelope encryption                             │
│ ├─ 30-day automatic key rotation                   │
│ ├─ <500ms latency SLA                              │
│ └─ CloudTrail audit logging                        │
├─────────────────────────────────────────────────────┤
│ Layer 3: GCP Secret Manager (Tertiary/Sync)         │
│ ├─ Workload Identity Federation                    │
│ ├─ Sync from Vault on change                       │
│ ├─ Health checks & desync alerts                   │
│ └─ Failover detection                              │
├─────────────────────────────────────────────────────┤
│ GitHub Actions (No Static Secrets)                  │
│ ├─ Auth: OIDC to external system                  │
│ ├─ Fetch: Dynamic at runtime only                  │
│ ├─ Duration: <1 hour (ephemeral)                   │
│ └─ Audit: 100% logged to Issues                    │
└─────────────────────────────────────────────────────┘
```

**Implementation Tasks:**

- [ ] Deploy HashiCorp Vault (HA) or use managed service
- [ ] Configure OIDC auth for GitHub Actions
- [ ] Setup AWS KMS key + rotation
- [ ] Setup GCP GSM + WIF
- [ ] Create sync workflow (Vault ↔ GSM)
- [ ] Implement health checks
- [ ] Setup failover detection
- [ ] Convert workflows to use external systems
- [ ] Remove all GitHub secrets
- [ ] Documentation (5 runbooks)

**Timeline:** 2-3 weeks  
**Blocks:** Phase 3 Batch 3

---

### Issue #1441: Secret Management Path Selection

**Decision Required:** Choose ONE of three paths

**Option 1: GCP Secret Manager (GSM) ✅ EASIEST**
- **For:** Teams already on GCP + Workload Identity
- **Setup:** 30 minutes
- **Complexity:** Low
- **Runbook:** [docs/GSM_SYNC.md](docs/GSM_SYNC.md)
- **Trigger:** `gh workflow run gsm-sync-run.yml --ref main`

**Option 2: HashiCorp Vault 🔒 ENTERPRISE**
- **For:** Organizations with Vault deployed
- **Setup:** 1-2 hours (AppRole) or 30 min (OIDC)
- **Complexity:** Medium
- **Runbook:** [docs/VAULT_SYNC.md](docs/VAULT_SYNC.md)
- **Trigger:** `gh workflow run vault-sync-run.yml --ref main`

**Option 3: AWS KMS 🏢 MOST INTEGRATED**
- **For:** AWS-native teams
- **Setup:** 45 minutes
- **Complexity:** Low-Medium
- **Runbook:** [docs/KMS_DECRYPT.md](docs/KMS_DECRYPT.md)
- **Trigger:** `gh workflow run kms-decrypt-run.yml --ref main`

**Decision Steps:**
1. Review three options above
2. Comment on issue #1441 with choice
3. Provide required credentials/access
4. Run corresponding setup workflow
5. Monitor it through completion

---

## 📊 CURRENT STATE ANALYSIS

### What's Working ✅
- Secrets health checks (hourly)
- Auto-remediation (5 minutes)
- Comprehensive validation
- Immutable GitHub Issues audit trail
- Manual secret syncing (on-demand)

### What's Broken ❌
- Credential rotation (GCP auth error)
- Terraform pipeline (AWS secrets missing)
- Overlapping workflows (race conditions)
- Event-driven sync (partially implemented)

### What's Missing 🟡
- HashiCorp Vault deployment
- KMS integration ready
- GSM-Vault reconciliation
- Multi-layer failover
- Zero static secrets mode

---

## 🎯 RESOLUTION ROADMAP

### TODAY (IMMEDIATE)
- [ ] Fix GCP service account in credential rotation (#1464)
- [ ] Re-run rotation workflow to validate fix
- [ ] Add AWS_ROLE_TO_ASSUME + AWS_REGION secrets (#1420)
- [ ] Verify terraform pipeline resumes

### THIS WEEK (DAYS 2-3)
- [ ] Consolidate overlapping workflows (#1474)
- [ ] Add concurrency guards
- [ ] Convert polling to event-driven
- [ ] Test no duplicate executions

### THIS WEEK (DAYS 3-5)
- [ ] Operator decides path: GSM vs Vault vs KMS (#1441)
- [ ] Document decision in issue
- [ ] Prepare required infrastructure

### NEXT WEEK (DAYS 6-14)
- [ ] Implement full multi-layer architecture (#1439)
- [ ] Setup chosen secret management system
- [ ] Implement 3-way failover
- [ ] Complete documentation (5 runbooks)
- [ ] Full security audit

---

## 🔧 MONITORING & DASHBOARDS

### Health Check Commands

```bash
# View all secrets
gh secret list --repo kushin77/self-hosted-runner

# Check recent credential rotations
gh run list --workflow=credential-rotation-monthly.yml \
  --repo kushin77/self-hosted-runner --limit 5

# Check Vault health (when implemented)
curl -s https://vault.your-domain/v1/sys/health | jq .

# View all failures in past 6 hours
gh run list --status failure --repo kushin77/self-hosted-runner \
  --created=2026-03-08T00:00:00Z

# Get audit trail
gh issue list --repo kushin77/self-hosted-runner \
  --label monitoring
```

### Metrics to Track

| Metric | Current | Target | SLA |
|--------|---------|--------|-----|
| Credential rotation success | 0% | 100% | Daily |
| Vault availability | N/A | 99.9% | 24h avg |
| KMS latency | N/A | <500ms | p99 |
| Failover time | N/A | <5min | p95 |
| Audit coverage | 100% | 100% | Real-time |

---

## 📞 ESCALATION & SUPPORT

### Immediate Help Needed

**GCP Expertise:**
- Fix service account impersonation
- Verify Workload Identity Federation
- Validate GSM permissions
- Contact: devops-gcp@your-org

**AWS Expertise:**
- Provide AWS role ARN for GitHub Actions
- Create IAM policy for Vault->KMS
- Setup cross-account trust (if needed)
- Contact: devops-aws@your-org

**Vault Expertise (if choosing Option 2):**
- Deploy or provide existing Vault endpoint
- Configure OIDC auth
- Setup secret engines
- Contact: devops-vault@your-org

---

## ✅ SUCCESS CRITERIA

- [x] Secrets health checks running
- [x] Auto-remediation framework in place
- [x] Immutable audit trail via GitHub Issues
- [ ] **Credential rotation completing successfully**
- [ ] **AWS secrets populated**
- [ ] **Terraform pipeline deployment working**
- [ ] Overlapping workflows consolidated
- [ ] Event-driven architecture implemented
- [ ] Secret management path chosen & documented
- [ ] Multi-layer architecture deployed
- [ ] Zero static secrets in GitHub
- [ ] Ephemeral credentials (<1 hour TTL)
- [ ] 100% audit trail maintained

---

## 📝 RELATED ISSUES

**Open:**
- #1439 - Multi-layer credential management
- #1441 - Secret management path selection
- #1464 - Credential rotation failure (GCP auth)
- #1420 - AWS secrets missing (Terraform blocked)
- #1474 - Governance consolidation Phase 2
- #1437 - KMS onboarding
- #1475 - Governance testing

**Completed:**
- ✅ #1065/1075 - Secrets health monitoring
- ✅ Secrets comprehensive validation
- ✅ Auto-remediation loops

---

## 🚀 GETTING STARTED

### For Operator

1. **Identify your cloud provider priority:**
   - If GCP: Choose GSM (Option 1)
   - If AWS: Choose KMS (Option 3)
   - If Enterprise: Choose Vault (Option 2)

2. **Provide required information:**
   - GCP project ID, KMS location, keyring, key name
   - OR AWS account ID, role name
   - OR Vault endpoint + auth details

3. **Register your choice:**
   - Reply on issue #1441 with selected option
   - Provide credentials/access
   - We will set up automated sync

### For DevOps/Security

1. **Fix immediate failures:**
   - GCP auth in credential rotation
   - AWS credentials in terraform

2. **Review overlapping workflows:**
   - Prepare consolidation plan for #1474
   - Design concurrency guards

3. **Prepare for Phase 2:**
   - Document multi-layer failover requirements
   - Prepare infrastructure (Vault, KMS, GSM)
   - Write runbooks

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-08 05:15 UTC  
**Status:** ACTIVE / REQUIRES IMMEDIATE ACTION  
**Next Review:** Daily until all critical items resolved
