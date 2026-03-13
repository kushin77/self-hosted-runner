# Cloud Build ↔ GitHub Integration Manual Setup Guide

**Status:** Ready for manual admin authorization (non-interactive creation blocked).

## Summary
- ✅ Cloud Build API enabled
- ✅ Cloud Build service account roles configured (run.admin, artifactregistry.admin, storage.admin, KMS)
- ✅ Cloud Build trigger script prepared
- ⏳ **BLOCKED:** GitHub App connection requires interactive OAuth authorization in GCP Console

## Quick Admin Steps

### Step 1: Authorize Cloud Build GitHub App
1. Open GCP Console: https://console.cloud.google.com/cloud-build/repositories?project=nexusshield-prod
2. Click **"Connect Repository"** (top right button)
3. Select **"GitHub"** as the source
4. Click **"Authorize"** and sign in to your GitHub account (akushnir)
5. Grant Cloud Build access to your repositories

### Step 2: Link the Repository
1. After authorization, you'll see a list of your repositories
2. Find and select: **`kushin77/self-hosted-runner`**
3. Click **"Connect selected repository"** or **"Create connection"**
4. Wait for confirmation message ("Successfully connected")

### Step 3: Create Cloud Build Trigger
Once the repository is connected, run this command from the repo root:

```bash
bash scripts/ops/setup-cloud-build-trigger.sh --project nexusshield-prod
```

This script will:
- ✓ Create a trigger named `main-build-trigger`
- ✓ Configure it to build on pushes to `main` branch
- ✓ Use `cloudbuild.yaml` as the build configuration
- ✓ Assign necessary IAM roles to Cloud Build service account
- ✓ Display Cloud Run services and trigger details

### Step 4: Verify Trigger Created
```bash
gcloud builds triggers list --project=nexusshield-prod --format=table
```

Expected output: A row for `main-build-trigger` with repository `kushin77/self-hosted-runner` and branch `main`.

### Step 5: Test the Trigger (Optional)
Manually trigger a build:
```bash
gcloud builds submit --config=cloudbuild.yaml --project=nexusshield-prod --region=us-central1
```

Or push to main:
```bash
git push origin main
```

This should automatically start a Cloud Build and deploy to Cloud Run (if cloudbuild.yaml includes deployment steps).

## Files Provided

| File | Purpose |
|------|---------|
| `scripts/ops/setup-cloud-build-trigger.sh` | Main trigger/SA setup script |
| `scripts/ops/create-trigger-via-api.sh` | REST API alternative (for troubleshooting) |
| `scripts/ops/CLOUD_BUILD_CONNECTION_README.md` | Connection steps reference |
| `cloudbuild.yaml` | Build configuration (already in repo) |
| `terraform/org_admin/cloud_build_triggers.tf` | (Optional) IaC for triggers |

## Governance Enforcement

Once integrated:
- ✅ **No GitHub Actions** — Direct Cloud Build deploys (`.github/ACTIONS_DISABLED_NOTICE.md`)
- ✅ **No Release Workflows** — Direct deployments (`.github/RELEASES_BLOCKED`)
- ✅ **Immutable** — All deployments logged to audit trail
- ✅ **Hands-off** — Cloud Scheduler triggers automation; no manual steps
- ✅ **Multi-credential failover** — GSM → Vault → KMS per architecture

## Troubleshooting

| Issue | Resolution |
|-------|-----------|
| "No GitHub repositories connected" | Re-run step 1-2 (authorization might have timed out) |
| `gcloud builds triggers create github` returns INVALID_ARGUMENT | Repository not in connection; complete step 2 again |
| Trigger created but not firing on push | Check branch pattern (`^main$`), verify webhook registered (console → Triggers → select trigger → view webhook) |
| Cloud Build fails with permission errors | Run setup script again to re-assign roles, or manually grant service account permissions |

## Next Steps

1. **Admin:** Follow Quick Admin Steps above (5 min)
2. **DevOps/CI Owner:** Verify trigger with `gcloud builds triggers list`
3. **All:** Push changes to `main` — Cloud Build will auto-deploy
4. **Observability:** Monitor Cloud Build → Cloud Run pipeline in the GCP Console

## Contact

If you encounter any issues:
- Check [Cloud Build documentation](https://cloud.google.com/build/docs/first-steps/build-push-docker-image)
- Review terraform configurations: `terraform/org_admin/cloud_build_triggers.tf`
- Check Cloud Build logs: https://console.cloud.google.com/cloud-build/builds?project=nexusshield-prod

---

**Last Updated:** 2026-03-13
**Governance Enforcement:** ✅ Immutable, Idempotent, No-Ops, Hands-Off, Direct Deploy, Multi-credential Failover
