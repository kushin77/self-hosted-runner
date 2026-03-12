# Direct Deployment: Cloud Build + Terraform Only

**Effective date:** March 12, 2026  
**Status:** ENFORCED

## Policy

Deployment **must** follow this path:
```
Commit to main
  ↓
(Branch protection: CODEOWNERS + Cloud Build required)
  ↓
Cloud Build triggers
  ↓
Terraform plan/apply (IaC)
  ↓
Cloud Run / GKE / Cloud Functions deployed
  ↓
Audit logged to Cloud Logging (JSONL)
```

### Characteristics

✅ **No GitHub Actions** — Cloud Build only  
✅ **No release workflows** — Direct git → build → deploy  
✅ **No manual approval gates** — CODEOWNERS review + automated build  
✅ **No long-lived credentials** — OIDC ephemeral tokens only  
✅ **No GitHub Releases** — Versioning via git tags, not GitHub releases  
✅ **Immutable audit trail** — All builds/deploys in Cloud Logging  
✅ **Hands-off** — Post-approval, zero manual intervention  

## Branch Protection Requirements

All PRs to `main` must have:

1. ✅ **CODEOWNERS approval** — At least one code owner approves
2. ✅ **Cloud Build status** — Specified Cloud Build trigger passes
3. ✅ **Conversations resolved** — All PR comments addressed
4. ✅ **Up-to-date branch** — No conflicts with main
5. ❌ **GitHub Actions disabled** — No GitHub Actions CI allowed

## Deployment Flow

### Step 1: Developer commits to feature branch

```bash
git checkout -b feat/my-feature
# ..make changes..
git add .
git commit -m "feat: add new feature"
git push origin feat/my-feature
```

### Step 2: Open PR to main

```bash
gh pr create --base main --head feat/my-feature \
  --title "feat: add new feature" \
  --body "Closes #1234"
```

**Automatic:** Cloud Build trigger runs (see PR status checks)

### Step 3: Review + approve

CODEOWNERS review the PR. CODEOWNERS must approve.

### Step 4: Merge to main

Once approved and Cloud Build passes:

```bash
gh pr merge --squash
```

**Automatic:** 
- Commit lands on `main`
- Cloud Build trigger fires immediately
- Terraform plan runs
- Terraform apply (IaC) deploys
- All logs → Cloud Logging (immutable)

### Step 5: Status + Observability

Monitor deployment:

```bash
# View live Cloud Build logs
gcloud builds log $(gcloud builds list --limit 1 --format='value(id)')

# View deployment in Cloud Logging
gcloud logging read "resource.type=cloud_run_revision" \
  --project=YOUR_PROJECT --limit=20
```

## No Release Workflow

❌ **DO NOT:**
- Use GitHub Releases
- Create release branches
- Use npm/pypi publish via Actions
- Tag images in GitHub Container Registry from Actions

✅ **DO:**
- Tag commits: `git tag v1.2.3 && git push origin v1.2.3`
- Cloud Build picks up tags automatically (via trigger)
- Cloud Build builds + pushes image to GCR/ECR
- Cloud Logging records the build + deploy

## Credential Injection (No secrets in code)

```bash
# DO NOT do this:
echo "DB_PASSWORD=secret123" >> .env  # ❌ BLOCKED by .gitignore

# DO this:
# Store in GSM:
gcloud secrets create db-password --data-file=/dev/stdin

# Reference in cloudbuild.yaml:
secretsManagerConfigs:
  - versionName: projects/$PROJECT_ID/secrets/db-password/versions/latest
    env: 'DB_PASSWORD'
```

## Terraform State Management

Terraform state is **locked** and **remote**:

```bash
# State stored in GCS (locked, not in repo)
gsutil ls gs://YOUR_TF_STATE_BUCKET/

# State access via Workload Identity (OIDC, no keys)
# All changes audit-logged
gcloud logging read "resource.type=gcs_bucket" \
  --filter="protoPayload.resourceName=~/YOUR_TF_STATE_BUCKET/"
```

## Blocking Rules

These commits will **NOT** merge:

1. ✅ If CODEOWNERS approval is missing
2. ✅ If Cloud Build status is not passing
3. ✅ If `.github/workflows/*.yml` files are added (blocked at merge time)
4. ✅ If plaintext secrets detected (gitleaks)
5. ✅ If PR is not up-to-date with main

## References

- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Terraform Cloud](https://www.terraform.io/cloud)
- [Issue #2778: Disable GitHub Actions](https://github.com/kushin77/self-hosted-runner/issues/2778)
- [Issue #2780: Branch Protection Enforcement](https://github.com/kushin77/self-hosted-runner/issues/2780)
