# Ops Finalization Runbook: DR Automation Final Steps

**Date Created:** 2026-03-06  
**Status:** Ready for Ops Finalization  
**Last Updated:** 2026-03-06T18:32:07Z  

## Overview

All core DR automation has been implemented and validated via a credential-less dry-run (RTO: 45m, RPO: 15m). The system is **immutable, sovereign, ephemeral, and idempotent**. The remaining steps are purely manual credential provisioning and finalization tasks that ops must complete to enable the automated schedule and key rotation.

---

## Remaining Steps (Ops Only)

### Step 1: Create GitLab API Token

**Why:** Required to create the quarterly `dr-dryrun` pipeline schedule and to store the rotated GitHub deploy key (private) as a protected GitLab CI variable.

**Option A: Via GitLab Web UI (Recommended)**

1. Log into GitLab as a project owner or maintainer.
2. Navigate to **Project** → **Settings** → **Access Tokens**.
3. Click **Add project access token**.
4. Configure:
   - **Name:** `ci-dr-automation-token`
   - **Scopes:** `api` (minimum required)
   - **Expiry:** 90 days (recommended; rotate after each use in rotation scripts)
5. Copy the generated token.
6. Store it securely in Google Secret Manager (see Step 2 below).

**Option B: Via GitLab API (requires existing admin or API token)**

```bash
# This requires authentication; only run on a secured ops host
GITLAB_API_URL="https://gitlab.com/api/v4"
EXISTING_ADMIN_TOKEN="..."  # admin token with token creation scope
PROJECT_ID="..."  # your GitLab project ID

curl --request POST "${GITLAB_API_URL}/projects/${PROJECT_ID}/access_tokens" \
  --header "PRIVATE-TOKEN: ${EXISTING_ADMIN_TOKEN}" \
  -d "name=ci-dr-automation-token&scopes=api&expires_at=2026-06-06"
```

### Step 2: Store Token in Google Secret Manager

Run this command **once** to store the token (run on a secured ops host with gcloud auth):

```bash
# Set your GitLab API token
GITLAB_API_TOKEN="<PASTE_YOUR_TOKEN_HERE>"

# Create or update the secret in GCP project gcp-eiq
echo -n "$GITLAB_API_TOKEN" | gcloud secrets create gitlab-api-token --data-file=- --project=gcp-eiq || \
echo -n "$GITLAB_API_TOKEN" | gcloud secrets versions add gitlab-api-token --data-file=- --project=gcp-eiq

echo "Token stored in GSM. Verifying..."
gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq | wc -c
```

### Step 3: Create the Quarterly DR Schedule

**Environment:** Any host with `gcloud` configured (project=gcp-eiq) and access to this repo.

**Prerequisite:** `gitlab-api-token` must be in GSM (Step 2).

**Run the idempotent schedule creator:**

```bash
cd /path/to/self-hosted-runner

# Set environment; these can come from GSM or env
export SECRET_PROJECT=gcp-eiq
export GITLAB_API_URL="https://gitlab.com/api/v4"
export PROJECT_ID="<YOUR_GITLAB_PROJECT_ID>"  # e.g., 12345
# GITLAB_API_TOKEN will be fetched from GSM automatically by the script

# Run the script (idempotent; safe to run multiple times)
./scripts/ci/create_dr_schedule.sh

# Check the created schedule in GitLab:
# Project → CI/CD → Schedules → should show a DR dry-run scheduled quarterly
```

### Step 4: Rotate GitHub Deploy Key

**Purpose:** Generate a new SSH keypair, upload the public key to the GitHub backup repo, and store the private key as a protected GitLab CI variable.

**Environment:** Any host with `gcloud` configured and access to this repo.

**Prerequisite:** `github-token` and `gitlab-api-token` both in GSM.

**Run the idempotent key rotation:**

```bash
cd /path/to/self-hosted-runner

# Set environment
export SECRET_PROJECT=gcp-eiq
export GITHUB_REPO="akushnir/self-hosted-runner"  # or your GitHub backup repo
export GITLAB_API_URL="https://gitlab.com/api/v4"
export GROUP_ID="<YOUR_GITLAB_GROUP_ID>"  # e.g., 1 (group or project ID)
# GITHUB_TOKEN and GITLAB_API_TOKEN will be fetched from GSM automatically

# Run the script (idempotent; checks for existing keys)
./scripts/ci/rotate_github_deploy_key.sh

# Verify:
# A) GitHub repo settings → Deploy keys → check for a new key named "ci-mirror-<timestamp>"
# B) GitLab project → Settings → CI/CD → Variables → check for `GITHUB_MIRROR_SSH_KEY` (protected, masked)
```

### Step 5: Verify Encrypted Backups (Sample Test)

**Purpose:** Confirm at least one encrypted backup object exists and test decrypt integrity.

**Prerequisites:**
- At least one backup object uploaded to `gs://gcp-eiq-ci-artifacts/`.
- `age` private key (decryption key) accessible.

**Run the backup integrity test:**

```bash
# List objects in the backup bucket
gsutil ls -l gs://gcp-eiq-ci-artifacts/**

# Download and decrypt a sample backup (example; adapt to your backup naming)
gsutil cp gs://gcp-eiq-ci-artifacts/backups/gitlab-backup-20260306.tar.age /tmp/

# Decrypt (requires age private key)
age -d -i ~/.age/key.txt /tmp/gitlab-backup-20260306.tar.age > /tmp/gitlab-backup-20260306.tar

# Verify archive integrity
tar -tzf /tmp/gitlab-backup-20260306.tar | head -20

echo "✓ Backup decrypts successfully."
```

---

## Automation Helpers (Ready to Use)

All scripts are **idempotent** and support GSM secret auto-fetch via `SECRET_PROJECT` env variable:

- `scripts/ci/create_dr_schedule.sh` — Create or verify quarterly `dr-dryrun` schedule.
- `scripts/ci/rotate_github_deploy_key.sh` — Rotate GitHub SSH deploy key and store in GitLab CI.
- `scripts/ci/create_sealedsecret_from_token.sh` — (optional) Create Kubernetes sealed secrets from CI variables.
- `scripts/ci/report_dr_status.sh` — Report DR run status to Slack.
- `ci_templates/dr-dryrun.yml` — GitLab CI template to run the DR dry-run.
- `ci_templates/dr-monitor.yml` — GitLab CI template to monitor and report DR results.

All scripts fetch tokens from GSM (project `gcp-eiq`) if not provided in env:

```bash
export SECRET_PROJECT=gcp-eiq
./scripts/ci/create_dr_schedule.sh  # will fetch gitlab-api-token automatically
```

---

## Final Checklist for Ops

- [ ] **Create GitLab API Token** (Step 1)
- [ ] **Store token in GSM** (Step 2)
- [ ] **Create quarterly schedule** via `scripts/ci/create_dr_schedule.sh` (Step 3)
- [ ] **Rotate GitHub deploy key** via `scripts/ci/rotate_github_deploy_key.sh` (Step 4)
- [ ] **Verify backup integrity** (Step 5)
- [ ] **Confirm CI schedule is active** (GitLab UI: CI/CD → Schedules)
- [ ] **Mark follow-up issues resolved** (issues/906, 907, if created)
- [ ] **Post final Slack summary** (optional; script `scripts/ci/report_dr_status.sh` can do this)

---

## Reference Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Ops Finalization Flow                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 1. Create GitLab Token (web or API)                        │
│    ↓                                                        │
│ 2. Store in GSM (gcloud secrets)                           │
│    ↓                                                        │
│ 3. Run create_dr_schedule.sh (idempotent)                 │
│    ↓                                                        │
│ 4. Run rotate_github_deploy_key.sh (idempotent)           │
│    ↓                                                        │
│ 5. Verify backups (test decrypt)                          │
│    ↓                                                        │
│ [Quarterly dr-dryrun schedule is now active & automated]  │
+                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

**Token fetch fails from GSM:**
```bash
# Confirm secret exists and you have access
gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq

# Check IAM permissions
gcloud projects get-iam-policy gcp-eiq --flatten="bindings[].members" | grep "$(gcloud config get-value account)"
```

**Schedule creation fails:**
```bash
# Test GitLab API access manually
GITLAB_API_TOKEN=$(gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq)
curl -H "PRIVATE-TOKEN: $GITLAB_API_TOKEN" https://gitlab.com/api/v4/projects/<PROJECT_ID>/pipeline_schedules
```

**Deploy key rotation fails:**
- Ensure `GITHUB_REPO` is in format `owner/repo`.
- Ensure GitHub token has `repo` scope (not just `public_repo`).
- Check GitLab token has `api` scope.

---

## Support & Contact

- **Questions about automation?** Review [docs/DR_RUNBOOK.md](/docs/DR_RUNBOOK.md) and [docs/CI_SECRETS_AND_ROTATION.md](/docs/CI_SECRETS_AND_ROTATION.md).
- **Issues or bugs?** Create an issue referencing this runbook.
- **Slack notifications?** Use `scripts/ci/report_dr_status.sh` to post updates to the ops channel.

---

**End of Ops Finalization Runbook.**
