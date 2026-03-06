#200 — MASTER DEPLOYMENT TASK: Hands-Off GitLab Runner Migration (Approved & Ready)

**Status**: Open  
**Owner**: Platform/CI operator  
**Approval Date**: March 6, 2026  
**Approval Statement**: "all the above is approved - proceed now no waiting - use best practices and your recommendations"

---

## PURPOSE

Execute the fully automated, hands-off GitLab Runner deployment with zero manual intervention during deployment. All infrastructure, scripts, documentation, and safety procedures are complete and verified.

---

## PREREQUISITES CHECKLIST

Before starting, operator must confirm:

- [ ] Access to GCP project `gcp-eiq` with Secret Manager API enabled
- [ ] Service account with `secretmanager.secretAccessor` role created
- [ ] GitLab Maintainer/Owner access to target group/project
- [ ] kubectl configured with current, reachable cluster context
- [ ] Current kubeconfig file (will be stored in GCP Secret Manager)
- [ ] Short-lived GitLab Runner registration token (from GitLab Admin panel)
- [ ] Read `HANDS_OFF_DEPLOYMENT_GUIDE.md` (5 min)
- [ ] Read `OPERATIONAL_READINESS_SUMMARY.md` (2 min)

---

## DEPLOYMENT PHASES (Pick One Path)

### Path A: GCP Secret Manager (Recommended) ⭐
**Security**: Highest  
**Scope**: Fully hands-off  
**Issues to Complete**:
- [ ] #102: GCP Secret Manager Setup
- [ ] #101: Configure GitLab CI Variables (GitLab portion)
- [ ] #103: Trigger CI Deploy Job
- [ ] #104: Post-Deploy Validation
- [ ] #105: Migration & Decommissioning (after successful validation)

**Timeline**: 15-20 minutes total (5 min setup + 2 min config + 2-5 min deployment + 5 min validation)

### Path B: Direct GitLab Variables
**Security**: Medium (secrets in GitLab UI, masked/protected)  
**Scope**: Fully hands-off  
**Issues to Complete**:
- [ ] #101: Configure GitLab CI Variables (encode kubeconfig)
- [ ] #103: Trigger CI Deploy Job
- [ ] #104: Post-Deploy Validation
- [ ] #105: Migration & Decommissioning (after successful validation)

**Timeline**: 10-15 minutes total (1 min encode + 1 min config + 2-5 min deployment + 5 min validation)

### Path C: Local Testing (Optional, for validation before production)
**Use If**: You want to smoke-test locally first  
**Issues to Complete**:
- [ ] Run: `REG_TOKEN=glrt-... ./scripts/ci/hands_off_orchestrate.sh deploy`
- [ ] Run: `./scripts/ci/hands_off_orchestrate.sh validate`
- [ ] Then proceed to Path A or B for production

---

## STEP-BY-STEP EXECUTION

### Step 1: Verify Repository Status

```bash
cd /home/akushnir/self-hosted-runner
./scripts/ci/pre_deploy_health_check.sh
# Expected output: "Health check PASSED"
```

**Success Criteria**: Script outputs "✓ Health check PASSED" with all checks green.

**Issues Related**: None (verification step only)

---

### Step 2: Choose Deployment Path & Read Relevant Guide

**For Path A (GCP Secret Manager)**:
```bash
# Read in this order:
1. HANDS_OFF_DEPLOYMENT_GUIDE.md (section: Quick Start)
2. OPERATIONAL_READINESS_SUMMARY.md (section: Path A)
3. issues/102-gsm-secrets-setup.md
4. issues/101-deploy-via-ci.md
5. issues/103-trigger-ci-deploy.md
6. issues/104-post-deploy-validation.md
```

**For Path B (Direct Variables)**:
```bash
# Read in this order:
1. HANDS_OFF_DEPLOYMENT_GUIDE.md (section: Quick Start, Path B note)
2. OPERATIONAL_READINESS_SUMMARY.md (section: Path B)
3. issues/101-deploy-via-ci.md (GitLab variables section)
4. issues/103-trigger-ci-deploy.md
5. issues/104-post-deploy-validation.md
```

**Success Criteria**: Operator understands the path chosen and all prerequisites.

**Issues Related**: #102 (Path A only), #101, #103, #104

---

### Step 3: Create GCP Secrets (Path A Only)

**Issue**: #102-gsm-secrets-setup.md

Follow the issue checklist:
```bash
# 1. Create kubeconfig secret
base64 -w0 ~/.kube/config | gcloud secrets versions add kubeconfig-secret --data-file=- --project=gcp-eiq

# 2. Create registration token secret
echo -n "glrt-<YOUR_TOKEN>" | gcloud secrets versions add gitlab-runner-regtoken --data-file=- --project=gcp-eiq

# 3. Create service account key secret (if not already stored)
base64 -w0 ~/.config/gcp/sa-key.json | gcloud secrets versions add gcp-sa-key --data-file=- --project=gcp-eiq

# 4. Verify all three secrets are accessible
gcloud secrets versions access latest --secret=kubeconfig-secret --project=gcp-eiq | head -c20
gcloud secrets versions access latest --secret=gitlab-runner-regtoken --project=gcp-eiq
gcloud secrets versions access latest --secret=gcp-sa-key --project=gcp-eiq | head -c20
```

**Success Criteria**:
- ✅ All three secrets created in GCP Secret Manager
- ✅ All three secrets readable via gcloud CLI

**Issues Related**: #102

---

### Step 4: Configure GitLab CI Protected Variables

**Issue**: #101-deploy-via-ci.md

In GitLab UI (Group or Project → Settings → CI/CD → Variables):

Add four **protected, masked** variables:

| Variable Name | Value | Notes |
|---------------|-------|-------|
| `GCP_PROJECT` | `gcp-eiq` | Project ID |
| `GCP_SA_KEY` | base64-encoded service account JSON | Copy entire base64 string |
| `KUBECONFIG_SECRET_NAME` | `kubeconfig-secret` | Must match GCP secret name |
| `REGTOKEN_SECRET_NAME` | `gitlab-runner-regtoken` | Must match GCP secret name |

**For Path B (Direct Variables)** instead add:
| Variable Name | Value |
|---------------|-------|
| `KUBECONFIG_BASE64` | base64 -w0 ~/.kube/config |
| `REG_TOKEN` | glrt-... (registration token) |

**Success Criteria**:
- ✅ All variables created in GitLab
- ✅ All variables marked as "protected"
- ✅ All variables marked as "masked"
- ✅ Variables saved successfully

**Issues Related**: #101

---

### Step 5: Trigger Deployment Pipeline

**Issue**: #103-trigger-ci-deploy.md

In GitLab UI:

1. Navigate to **Pipelines** (CI/CD → Pipelines)
2. Click **"Run pipeline"**
3. Select branch: **`main`**
4. Click **"Create pipeline"**

**Success Criteria**: Pipeline appears in Pipelines list with status "running" or "pending".

**Issues Related**: #103

---

### Step 6: Start Manual Deploy Job

**Issue**: #103-trigger-ci-deploy.md

In the newly created pipeline:

1. Wait for `.pre` stage jobs to complete (if any)
2. Locate the manual job: **`deploy:sovereign-runner-gsm`** (Path A) or **`deploy:sovereign-runner`** (Path B)
3. Click the **▶ play icon** next to the job name
4. Monitor the job logs in real-time

**Expected Logs**:
```
[GCP Auth] Activating service account...
[Secret Fetch] Fetching kubeconfig secret: kubeconfig-secret
[Secret Fetch] Fetching registration token secret: gitlab-runner-regtoken
[Secret Apply] SealedSecret generated: infra/gitlab-runner/sealedsecret.generated.yaml
[Helm Install] Helm install/upgrade gitlab-runner ...
[Pod Ready] Waiting for pods...
✓ All pods are ready
```

**Job Status**: Expected to be **Passed** (green) when complete.

**Success Criteria**:
- ✅ Job status: **Passed** (green)
- ✅ All logs show successful secret fetch, Helm install, and pod readiness
- ✅ No ERROR or FAILED messages in logs

**Issues Related**: #103

---

### Step 7: Validate Post-Deployment

**Issue**: #104-post-deploy-validation.md

From a terminal with kubectl access:

```bash
# 1. Verify runner pods
kubectl -n gitlab-runner get pods -o wide
# Expected: gitlab-runner-0 (or similar) in Running state

# 2. Check logs
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=100
# Expected: successful registration, ready to accept jobs

# 3. Verify runner in GitLab UI
# Go to Admin > Runners
# Look for: Name ~ "gitlab-runner", Tags: k8s-runner, Status: Online (green)

# 4. Trigger validation pipeline (optional but recommended)
GITLAB_API_TOKEN=<token> PROJECT_ID=<id> ./scripts/ci/trigger_yamltest_pipeline.sh main

# 5. Watch YAMLtest-sovereign-runner job
# Pipeline > Jobs > YAMLtest-sovereign-runner
# Expected: Passed (green)
```

**Success Criteria**:
- ✅ All runner pods in **Running** state
- ✅ Runner visible in GitLab Admin with status **Online** (green)
- ✅ Runner has tags: **k8s-runner, sovereign, ephemeral, immutable**
- ✅ YAMLtest-sovereign-runner job **Passed** (if triggered)

**Issues Related**: #104

---

### Step 8: Plan Runner Migration (After Validation)

**Issue**: #105-runner-migration-decommission.md

After 24-48 hours of successful validation with both old and new runners online:

1. Run critical test pipelines on new runner (20+ jobs to ensure stability)
2. Monitor logs for errors and regressions
3. If stable: Disable legacy runner(s) in GitLab Admin
4. Keep disabled legacy runners for 7-day rollback window
5. After 7 days with no issues: Delete legacy runner registration

**Success Criteria**:
- ✅ 24-48 hours of dual-runner operation with no failures
- ✅ New runner job success rate > 99%
- ✅ Job duration variance < ±10% from baseline
- ✅ Legacy runners disabled after validation period
- ✅ New runner is primary and fully operational

**Issues Related**: #105

---

## SAFETY & ROLLBACK PROCEDURES

### If Deployment Job Fails (Step 6)

1. **Check logs**: Review job logs for specific error (GCP auth, secret not found, Helm error, etc.)
2. **Review issue #103**: "Troubleshooting" section for common issues
3. **Fix root cause**: Address the specific error (wrong secret name, invalid kubeconfig, etc.)
4. **Re-run job**: Click ▶ play icon again to re-trigger (idempotent, safe to re-run)
5. **Escalate if needed**: Review OPERATIONAL_READINESS_SUMMARY.md "Support & Troubleshooting" section

### If Validation Fails (Step 7)

1. **Check pod status**: `kubectl -n gitlab-runner describe pod <pod-name>`
2. **Check logs**: `kubectl -n gitlab-runner logs <pod-name> --previous`
3. **Review issue #104**: "Troubleshooting" section
4. **Options**:
   - Re-run deploy job (idempotent fix)
   - Check if registration token is expired (generate new one, re-run)
   - Verify kubeconfig is current and points to reachable cluster

### If Issues During Migration Period (Step 8)

1. **Within 7-day rollback window**: Re-enable legacy runner, disable new runner
2. **No data loss**: Both runners are stateless; can switch back safely
3. **Investigate**: Review logs and metrics from failure period
4. **Fix and retry**: Once root cause is resolved, repeat Steps 5-7

---

## COMMUNICATION & APPROVAL

**Who**: Platform/CI operator  
**Status**: ✅ Approved by user  
**Approval Statement**: "all the above is approved - proceed now no waiting"  
**Authority**: Proceed without further approval blocks  
**Timeline**: No waiting; execute immediately upon having prerequisites  

---

## TRACKING & DOCUMENTATION

### As operator progresses, update this issue:

- [ ] **Step 1**: ✓ Health check passed (date: _______)
- [ ] **Step 2**: ✓ Read deployment guides (date: _______)
- [ ] **Step 3**: ✓ GCP secrets created (date: _______)
- [ ] **Step 4**: ✓ GitLab variables configured (date: _______)
- [ ] **Step 5**: ✓ Pipeline triggered (date: _______)
- [ ] **Step 6**: ✓ Deploy job completed (date: _____, status: _______)
- [ ] **Step 7**: ✓ Validation passed (date: _______)
- [ ] **Step 8**: ✓ Migration plan started (date: _______)

---

## SUCCESS CRITERIA (FINAL)

When all steps are complete:

- ✅ Runner pods running in Kubernetes
- ✅ Runner registered in GitLab with correct tags
- ✅ Runner status: **Online** (green)
- ✅ Pre-flight validation (YAMLtest) **Passed**
- ✅ Multiple test pipelines run successfully on new runner
- ✅ No regressions vs. legacy runner
- ✅ Operator confident to proceed with migration

---

## RELATED ISSUES

- **#100**: Runner Migration Plan (background context)
- **#101**: CI Deploy Checklist (GitLab variable setup)
- **#102**: GCP Secret Manager Setup (secret creation)
- **#103**: Trigger CI Deploy Job (deployment execution)
- **#104**: Post-Deploy Validation (verification steps)
- **#105**: Migration & Decommissioning (legacy runner retirement)

---

## REFERENCE DOCUMENTS

- `HANDS_OFF_DEPLOYMENT_GUIDE.md` — Complete 5-step quick start
- `OPERATIONAL_READINESS_SUMMARY.md` — Deployment options & timeline
- `DEPLOYMENT_FINAL_STATUS.md` — Summary & support info
- `infra/gitlab-runner/README.md` — Helm configuration details
- `infra/gitlab-runner/deploy_runbook.md` — Operator runbook

---

## SUPPORT CONTACTS & ESCALATION

**For questions**:
1. Check relevant issue (#101-105) troubleshooting section
2. Review `HANDS_OFF_DEPLOYMENT_GUIDE.md` troubleshooting
3. Run: `./scripts/ci/hands_off_orchestrate.sh help`

**For blockers**:
1. Document specific error in notes below
2. Reference relevant issue (#101-105)
3. Include logs or error output
4. Escalate to platform team

---

## NOTES / PROGRESS LOG

```
[Timeline of operator progress will be recorded here]
```

---

## APPROVAL & SIGN-OFF

**Infrastructure Readiness**: ✓ PASSED (verified 2026-03-06)  
**Documentation Status**: ✓ COMPLETE  
**Scripts & Automation**: ✓ READY  
**Operator Approval**: ✓ APPROVED ("proceed now no waiting")  

🟢 **STATUS**: READY FOR OPERATOR EXECUTION

---

## NEXT IMMEDIATE ACTION

**Operator should**:

1. ✅ Confirm all prerequisites are met (section: "PREREQUISITES CHECKLIST")
2. ✅ Choose deployment path (A, B, or C)
3. ✅ Run Step 1: `./scripts/ci/pre_deploy_health_check.sh`
4. ✅ Begin Step 2: Read deployment guides
5. ✅ Continue through all 8 steps in order

**Estimated Total Time**: 15-20 minutes  
**Automated Time**: 2-5 minutes (CI job execution)  
**Manual Time**: ~10-15 minutes (setup, configuration, validation)

---

**Issue #200 — Master Deployment Task**  
**Created**: 2026-03-06  
**Status**: Ready for Operator Execution  
**Health Check**: PASSED  
**Commitment**: "All the above is approved — proceed now no waiting"
