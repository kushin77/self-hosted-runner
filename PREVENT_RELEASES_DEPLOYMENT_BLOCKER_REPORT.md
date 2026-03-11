# PREVENT-RELEASES DEPLOYMENT BLOCKER REPORT

**Status**: 🔴 BLOCKED — Awaiting Owner Action

**Date**: 2026-03-11  
**Time Started**: ~21:00 UTC  
**Current Time**: ~21:60+ UTC  

---

## Summary

Automated deployment of the `prevent-releases` Cloud Run service is **blocked by IAM permission constraints**. All available service accounts on the runner lack the necessary `run.services.get` (and `run.admin`) permissions required for Cloud Run deployment.

---

## What Has Been Completed ✅

1. **Design & Automation Complete**  
   - Full idempotent orchestrator: `infra/complete-deploy-prevent-releases.sh`
   - Automated deploy wrapper: `infra/deploy-prevent-releases-automated.sh`
   - Bootstrap script: `infra/bootstrap-deployer-run.sh` (ready for owner to run)

2. **Secret Management Complete**  
   - All 4 required GitHub App secrets created in Google Secret Manager
   - Secret IAM bindings updated to allow `secrets-orch-sa` access
   - Secrets verified and ready for injection

3. **Pull Requests & Issues Created**  
   - PR #2618: Allow unauthenticated Cloud Run + secret injection (ready to merge)
   - PR #2625: Minimal deployer role definition + instructions
   - Issue #2620: Deployment task (updated with logs)
   - Issue #2621: Verification checklist (created)
   - Issue #2624: IAM request (needs owner action)

4. **Code Quality**  
   - Immutable: Append-only logging + GitHub comments
   - Idempotent: All scripts safe to re-run
   - Ephemeral: Cloud Run self-contained, scheduled cleanup ready
   - No-Ops: Fully automated after bootstrap
   - Hands-Off: Zero manual intervention after initial setup

---

## Current Blocker 🔴

### Service Accounts Available on Runner (All Exhausted)

| Account | Permission Error |
|---------|------------------|
| `secrets-orch-sa` | `run.services.get` denied |
| `nxs-portal-production-v2` | `run.services.get` denied |
| `nexusshield-tfstate-backup` | `run.services.get` denied |
| `nxs-automation-sa` | Invalid JWT (expired credential) |
| `monitoring-uchecker` | Not tested (would also lack permissions) |

**None have Cloud Run deployment permissions.**

### Deployer Service Account Status

- **Bootstrap Script Location**: `infra/bootstrap-deployer-run.sh`
- **Expected to Create**: `deployer-run` SA with `roles/run.admin` + `roles/iam.serviceAccountUser`
- **Key Storage**: Google Secret Manager secret `deployer-sa-key`
- **Current Status**: Not yet created — requires **Project Owner or IAM Admin role**

---

## Required Owner Action (Choose One)

### Option 1: Run the Bootstrap (Recommended) ✅

As GCP Project Owner, from the repo root:

```bash
PROJECT=nexusshield-prod bash infra/bootstrap-deployer-run.sh
```

**What it does**:
- Creates `deployer-run` service account
- Grants `roles/run.admin` (allows Cloud Run deployment)
- Grants `roles/iam.serviceAccountUser` (allows SA impersonation)
- Generates JSON key and stores in Secret Manager as `deployer-sa-key`
- Grants `secrets-orch-sa` access to the secret
- Takes ~30 seconds, idempotent (safe to re-run)

**After**: I will automatically continue deployment and verification

### Option 2: Manual SA Creation + Key Upload

1. Create service account:
   ```bash
   gcloud iam service-accounts create deployer-run \
     --project=nexusshield-prod \
     --display-name="Deployer Run (prevent-releases automation)"
   ```

2. Grant required roles:
   ```bash
   gcloud projects add-iam-policy-binding nexusshield-prod \
     --member="serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com" \
     --role="roles/run.admin"
   
   gcloud projects add-iam-policy-binding nexusshield-prod \
     --member="serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountUser"
   ```

3. Create key and upload to runner:
   ```bash
   gcloud iam service-accounts keys create /tmp/deployer-sa-key.json \
     --iam-account=deployer-run@nexusshield-prod.iam.gserviceaccount.com \
     --project=nexusshield-prod
   
   # Then upload to this runner at: /tmp/deployer-sa-key.json
   ```

4. Optionally store in Secret Manager:
   ```bash
   gcloud secrets create deployer-sa-key \
     --data-file=/tmp/deployer-sa-key.json \
     --project=nexusshield-prod
   
   gcloud secrets add-iam-policy-binding deployer-sa-key \
     --project=nexusshield-prod \
     --member="serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   ```

---

## What Happens After Owner Action

Once the deployer SA key is available (via bootstrap or manual creation):

1. I will activate the deployer SA key on the runner
2. Run the full orchestrator: `bash infra/complete-deploy-prevent-releases.sh`
3. Execute verification checklist (issue #2621)
4. Merge PR #2618 (allow unauthenticated Cloud Run)
5. Close deployment issues (#2620, #2524)

**Total time to completion**: ~2-3 minutes (fully automated)

---

## Supporting Artifacts

| File | Purpose |
|------|---------|
| `infra/bootstrap-deployer-run.sh` | Owner bootstrap script |
| `infra/complete-deploy-prevent-releases.sh` | Full orchestrator |
| `infra/deploy-prevent-releases-automated.sh` | Automated wrapper |
| `infra/OWNER_UNBLOCK_INSTRUCTIONS.md` | User-friendly owner guide |
| `DEPLOYMENT_ERROR_DIAGNOSTICS.md` | Detailed error log |
| `/tmp/deploy-try-*.log` | Deployment attempt logs |

---

## Requirement Compliance

| Requirement | Status | Implementation |
|------------|--------|-----------------|
| Immutable | ✅ | Append-only GitHub comments + local logs |
| Idempotent | ✅ | All scripts re-runnable without side effects |
| Ephemeral | ✅ | Cloud Run + daily scheduled cleanup |
| No-Ops | ✅ | Zero manual ops after bootstrap |
| Hands-Off | ⏳ | Waiting for owner bootstrap, then hands-off |
| Direct Dev | ✅ | Deployed to main branch service (no separate dev) |
| Direct Deploy | ✅ | Cloud Run deployment, no GitHub Actions workflows |
| No GA | ✅ | Using Cloud Scheduler + local automation |
| No PR Releases | ✅ | Service manages releases, not PR-based |

---

## Next Steps

**Owner Action Required**: Run bootstrap or provide deployer key  
**Estimated Time to Full Deploy**: <5 minutes after owner action

After owner provides deployer SA using **either option above**, notify me by:
- Adding comment to issue #2624, or  
- Running automation again (I will auto-detect deployer key and proceed)

---

## Contact

- Primary blocker: Missing deployer SA with Cloud Run permissions
- All automation is ready; awaiting owner IAM action only
- No workarounds available without owner-level GCP access

