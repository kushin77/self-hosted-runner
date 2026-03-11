# Governance Enforcement Deployment Status — 2026-03-11

## ✅ Completed

### Enforcement Tools
- ✅ `tools/governance-scan.sh` — repository scanner (tags, commits, disallowed actors)
- ✅ `tools/bootstrap-create-trigger.sh` — idempotent Cloud Build trigger creation (with logging)
- ✅ `tools/post-github-comments.sh` — idempotent GitHub issue poster/labeler
- ✅ Initial scan run — no violations detected

### Documentation & Runbooks
- ✅ `governance/ENFORCEMENT.md` — enforcement methodology and Cloud Build guidance
- ✅ `governance/PRIVILEGED_TRIGGER_SETUP.md` — admin runbook with exact commands
- ✅ `governance/NEEDS_TRIGGER_CREATION.md` — immutable audit file
- ✅ `governance/trigger-creation-log.txt` — append-only attempt log

### Infrastructure-as-Code
- ✅ `infra/cloudbuild/main.tf` — Terraform for Cloud Build trigger + Cloud Scheduler
- ✅ `infra/cloudbuild/variables.tf` — Terraform variables (project, location, service account)
- ✅ `infra/cloudbuild/providers.tf` — Terraform provider config
- ✅ `infra/cloudbuild/outputs.tf` — trigger name and scheduler job outputs
- ✅ `infra/cloudbuild/README.md` — Terraform usage and security notes

### Audit Trail
- ✅ CSV mapping of auto-removed releases: `governance/auto-removals-2026-03-11.csv`
- ✅ Audit issue #2619 created to collect and track scan results
- ✅ Action-required issue #2623 created to track trigger deployment
- ✅ All artifacts committed to main (commit: f515502f7)

## 🚫 Blocked — Awaiting Credentials

### Cloud Build Trigger Creation
**Status:** Attempted automated creation returned PERMISSION_DENIED.
**Active Account:** `monitoring-uchecker@nexusshield-prod.iam.gserviceaccount.com`
**Required Roles:** `roles/cloudbuild.builds.editor` (or `roles/cloudbuild.admin`) + `roles/secretmanager.secretAccessor`

**Next Steps (Pick One):**

**Option A — Admin Grants Roles (Fast)**
Grant the active account the required roles:
```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:monitoring-uchecker@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.admin"

gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:monitoring-uchecker@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```
After granting, the automation agent will re-run `./tools/bootstrap-create-trigger.sh` to create the trigger, validate the first run, and close issue #2623.

**Option B — Admin Runs Terraform (Recommended for IaC)**
```bash
cd infra/cloudbuild
terraform init
terraform apply -var="project=nexusshield-prod" \
                -var="scheduler_service_account=PROJECT_NUMBER@cloudscheduler.gserviceaccount.com"
```
After Terraform creates the trigger, post the trigger name and first-run build ID to issue #2623; automation will validate and close the issue.

**Option C — Admin Runs One-Off Command**
```bash
gcloud beta builds triggers create github \
  --name="gov-scan-trigger" \
  --repo-name="self-hosted-runner" \
  --repo-owner="kushin77" \
  --branch-pattern="^main$" \
  --build-config="governance/cloudbuild-gov-scan.yaml" \
  --description="Governance scanner (automatic scheduled runner)." \
  --project=nexusshield-prod

gcloud beta builds triggers run gov-scan-trigger --branch=main --project=nexusshield-prod
```

### GitHub Issue Updates
**Status:** `GITHUB_TOKEN` not available in current environment.
**Issues Pending:** #2619 (audit), #2623 (action-required)
**Prepared Comments:** `tools/post-github-comments.sh` (idempotent, ready to run when token is available)

## Architecture & Guarantees

- **Immutable:** Append-only logs (`governance/trigger-creation-log.txt`), immutable artifacts in git, GitHub comments create immutable audit trails.
- **Ephemeral:** Cloud Build runs are ephemeral; outputs are logged to GitHub and stored in `governance/`.
- **Idempotent:** All scripts check for existing resources (trigger, scheduler job) and skip creation if already present.
- **No-Ops:** Once the trigger is created, it runs automatically on daily schedule (03:00 UTC) — no manual intervention needed.
- **Fully Automated & Hands-Off:** Governance scanner detects violations (disallowed actors: bots, GitHub Actions, PR-based releases) and posts findings to audit issue #2619.
- **Direct Development, Direct Deployment:** No GitHub Actions used; enforcement runs in Cloud Build via scheduled trigger. No PR-based releases allowed (prevent-releases automation).

## Next Action

An administrator should choose Option A, B, or C above and execute. Once the Cloud Build trigger is created and first-run completes, post the trigger name and build ID to issue #2623; automation will close the issue and mark enforcement operational.

See also:
- `governance/PRIVILEGED_TRIGGER_SETUP.md` — detailed admin runbook
- `governance/ENFORCEMENT.md` — enforcement design
- `infra/cloudbuild/README.md` — Terraform usage
