# Cloud Build Trigger & Branch Protection Setup Guide

This guide provides exact `gcloud` and GitHub API commands to complete the governance enforcement setup.

## Prerequisites

- `gcloud` CLI authenticated with `nexusshield-prod` GCP project owner privileges
- `gh` CLI authenticated with admin token (repo settings access)
- Bash shell

## Configuration Variables

```bash
# GCP Configuration
export GCP_PROJECT="nexusshield-prod"
export GCP_REGION="us-central1"
export GITHUB_OWNER="kushin77"
export GITHUB_REPO="self-hosted-runner"
export GITHUB_TOKEN="<your-github-admin-token>"  # Required for gh CLI
```

---

## Step 1: Create Cloud Build Triggers

### 1.1 Create Policy-Check Trigger (runs on every push to main)

**Purpose:** Prevent commits that add or modify `.github/workflows/` files (governance enforcement).

```bash
gcloud builds triggers create github \
  --name=policy-check-trigger \
  --description="Policy check: block .github/workflows modifications (governance)" \
  --repo-name="${GITHUB_REPO}" \
  --repo-owner="${GITHUB_OWNER}" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild/policy-check.yaml" \
  --project="${GCP_PROJECT}" \
  --status=ENABLED
```

**Verify:**
```bash
gcloud builds triggers describe policy-check-trigger --project="${GCP_PROJECT}"
```

### 1.2 Create Direct-Deploy Trigger (runs on successful policy check)

**Purpose:** Build, scan, and deploy to Cloud Run (canary 10% → promote 100%).

```bash
gcloud builds triggers create github \
  --name=direct-deploy-trigger \
  --description="Direct deployment: build → scan → canary → smoke tests → promote (no GitHub Actions)" \
  --repo-name="${GITHUB_REPO}" \
  --repo-owner="${GITHUB_OWNER}" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild/direct-deploy.yaml" \
  --project="${GCP_PROJECT}" \
  --status=ENABLED
```

**Verify:**
```bash
gcloud builds triggers describe direct-deploy-trigger --project="${GCP_PROJECT}"
```

### 1.3 List All Triggers

```bash
gcloud builds triggers list --project="${GCP_PROJECT}" --filter="name:(policy-check|direct-deploy)"
```

---

## Step 2: Configure Branch Protection on main

### 2.1 Require Cloud Build Status Checks

This ensures that commits to `main` are validated by both Cloud Build triggers before merging.

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  /repos/${GITHUB_OWNER}/${GITHUB_REPO}/branches/main/protection \
  -f "required_status_checks={strict:true,contexts:['policy-check-trigger','direct-deploy-trigger']}" \
  -f "required_pull_request_reviews=null" \
  -f "dismiss_stale_reviews=false" \
  -f "require_code_owner_reviews=true" \
  -f "require_last_push_approval=false" \
  -f "allow_force_pushes=false" \
  -f "allow_deletions=false" \
  -f "enforce_admins=true" \
  -f "required_linear_history=false"
```

**Expected output:**
```json
{
  "url": "https://api.github.com/repos/kushin77/self-hosted-runner/branches/main/protection",
  "required_status_checks": {
    "enforcement_level": "everyone",
    "contexts": [
      "policy-check-trigger",
      "direct-deploy-trigger"
    ]
  },
  ...
}
```

### 2.2 Verify Branch Protection

```bash
gh api /repos/${GITHUB_OWNER}/${GITHUB_REPO}/branches/main/protection --pretty
```

---

## Step 3: Grant Required IAM Roles

### 3.1 Grant Cloud Build SA Access to Deploy

```bash
# Allow Cloud Build to deploy to Cloud Run
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GCP_PROJECT}@cloudbuild.gserviceaccount.com" \
  --role="roles/run.admin" \
  --quiet

# Allow Cloud Build to manage Cloud Run services
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GCP_PROJECT}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" \
  --quiet

# Allow Cloud Build access to Secret Manager
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GCP_PROJECT}@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

# Allow Cloud Build to write logs
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GCP_PROJECT}@cloudbuild.gserviceaccount.com" \
  --role="roles/logging.logWriter" \
  --quiet
```

### 3.2 Verify Roles

```bash
gcloud projects get-iam-policy "${GCP_PROJECT}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:cloudbuild.gserviceaccount.com"
```

### 3.3 Grant Cloud Run Deployer SA Permissions (for log access)

```bash
# Ensure deployer-run service account exists
gcloud iam service-accounts create deployer-run \
  --display-name="Cloud Run deployment operator (direct-deploy)" \
  --project="${GCP_PROJECT}" || true

# Grant it permissions to read Cloud Build logs
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:deployer-run@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/logging.viewer" \
  --quiet

# Grant it permissions to manage Cloud Run (for health checks)
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:deployer-run@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/run.viewer" \
  --quiet
```

---

## Step 4: Merge Enforcement PRs

Once Cloud Build triggers are created and tested, merge the enforcement PRs:

```bash
# Merge policy-check PR
gh pr merge 2782 --squash --delete-branch --auto

# Merge CONTRIBUTING update PR
gh pr merge 2784 --squash --delete-branch --auto

# Merge direct-deploy pipeline PR
gh pr merge 2800 --squash --delete-branch --auto
```

---

## Step 5: Rotate Exposed Credentials

Before merging remediation PRs (#2801–#2803), rotate all exposed credentials:

```bash
# For each exposed credential in the remediation PRs:
# 1. Identify the secret name and service in the PR comments
# 2. Rotate using GSM / Vault / AWS KMS

# Example: Rotate GitHub token in GSM
gcloud secrets versions add github-bot-token \
  --data-file=- <<< "$NEW_GITHUB_TOKEN_VALUE" \
  --project="${GCP_PROJECT}"

# Verify new version is active
gcloud secrets versions list github-bot-token --project="${GCP_PROJECT}"
```

---

## Step 6: Merge Remediation PRs (After Credential Rotation)

```bash
# Merge remediation PRs (these remove committed secrets)
gh pr merge 2801 --squash --delete-branch --auto
gh pr merge 2802 --squash --delete-branch --auto
gh pr merge 2803 --squash --delete-branch --auto
```

---

## Step 7: Verify Governance

### 7.1 Test Policy-Check Enforcement

Attempt to add a workflow and verify it's blocked:

```bash
git checkout -b test-policy-violation
echo "name: test" > .github/workflows/test.yml
git add .github/workflows/test.yml
git commit -m "test: attempt to add workflow (should fail)"

# Try to push (will fail on policy check)
git push origin test-policy-violation

# Cleanup
git checkout main
git branch -D test-policy-violation
```

### 7.2 Test Direct Deploy Pipeline

Trigger a manual build to verify the pipeline works:

```bash
gcloud builds submit . \
  --config=cloudbuild/direct-deploy.yaml \
  --project="${GCP_PROJECT}" \
  --substitutions="_ENVIRONMENT=staging"
```

### 7.3 Verify Immutable Audit Trail

Check that deployment events are being logged to Cloud Logging:

```bash
gcloud logging read "resource.type=cloud_run_revision AND logName:direct-deploy-audit" \
  --project="${GCP_PROJECT}" \
  --limit=10 \
  --format=json
```

---

## Step 8: Close Blocking Issues

Once everything is verified, close the blocking ops issues:

```bash
# Close #2684 (Grant IAM permissions)
gh issue close 2684 -c "Completed: Cloud Build SA and deployer-run SA have required IAM roles. Branch protection configured. Governance enforcement active."

# Close any governance enforcement tracking issues
gh issue close 2787 -c "Completed: policy-check-trigger created and active"
gh issue close 2789 -c "Completed: direct-deploy-trigger created and tested"
gh issue close 2791 -c "Completed: Branch protection enforced on main"
```

---

## Troubleshooting

### 7.1 Policy-Check Trigger Not Running

```bash
# List all recent builds
gcloud builds list --project="${GCP_PROJECT}" --limit=10

# Get details of a specific build
gcloud builds log <BUILD_ID> --project="${GCP_PROJECT}"
```

### 7.2 Direct-Deploy Trigger Failures

```bash
# Check Cloud Run service logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=backend" \
  --project="${GCP_PROJECT}" \
  --limit=50

# Check Cloud Build logs
gcloud builds log <BUILD_ID> --project="${GCP_PROJECT}" --stream
```

### 7.3 Verify Branch Protection is Active

```bash
gh api /repos/${GITHUB_OWNER}/${GITHUB_REPO}/branches/main/protection --pretty
```

---

## Summary

**What This Achieves:**

✅ **Immutable:** All deployments logged to Cloud Logging (tamper-proof)
✅ **Ephemeral:** Credentials stored in GSM/Vault (no long-lived secrets in repo)
✅ **Idempotent:** Cloud Build pipelines designed to be re-runnable safely
✅ **No-Ops:** Automated via Cloud Build (no manual deployments)
✅ **Hands-Off:** Push to main → policy-check → canary tests → auto-promote
✅ **GSM/Vault/KMS:** All secrets in Secret Manager (no GitHub secrets)
✅ **Direct-Deploy:** No GitHub Actions, no PR releases
✅ **Multi-tier:** Policy + deployment pipelines enforce governance

**Governance Checklist:**

- ✅ No `.github/workflows/` deployments (policy-check enforces)
- ✅ Cloud Build triggers on main branch
- ✅ Branch protection requires Cloud Build status checks
- ✅ Canary deployment with smoke tests before promotion
- ✅ Immutable audit trail in Cloud Logging
- ✅ Credentials rotated and stored in GSM
- ✅ IAM roles minimally scoped
- ✅ All changes tracked and auditable

---

## Next Steps

1. Run the commands in this guide (Steps 1–3).
2. Test the policy-check trigger (Step 7.1).
3. Merge the enforcement PRs (Step 4).
4. Verify governance with smoke tests (Step 7).
5. Monitor Cloud Logging and Cloud Build for any issues.
6. Document any custom adaptations in your runbooks.

For questions or issues, refer to the governance issues (#2700, #2772–#2776, #2787–#2791).
