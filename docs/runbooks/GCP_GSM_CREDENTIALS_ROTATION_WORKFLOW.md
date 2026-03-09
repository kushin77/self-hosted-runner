# GCP Secret Manager (GSM) Secrets Integration & Rotation

**Version:** 1.0  
**Last Updated:** 2026-03-08  
**Status:** Hands-off, fully automated (OIDC-based, ephemeral, idempotent)

---

## Overview

This guide establishes GCP Secret Manager (GSM) as the **single source of truth** for all sensitive credentials used in GitHub Actions CI/CD workflows. All secrets are fetched dynamically at runtime, never stored in GitHub, and accessed via **Workload Identity Federation (OIDC)** — eliminating the need for long-lived service account keys.

### Design Principles

✅ **Immutable:** Secrets defined once in GSM, versioned, audited  
✅ **Ephemeral:** Loaded into memory only when needed, never persisted to disk  
✅ **Idempotent:** All operations safe to rerun (no state drift)  
✅ **No-ops:** Repeated syncs return same secrets (deterministic)  
✅ **Fully Automated:** Weekly sync (cron) + manual rotation triggers  
✅ **Hands-off:** Workload Identity Federation (OIDC) — no keys, no human access required  

---

## Architecture

```
┌─────────────────────────────────┐
│  GitHub Actions Workflow        │
│  (gsm-secrets-sync.yml)         │
│  (Runs weekly, Monday 02:00 UTC)│
└────────────┬────────────────────┘
             │
             │ OIDC Token Exchange
             │ (Workload Identity Federation)
             │
             ↓
┌─────────────────────────────────┐
│  Google Cloud Platform          │
│  ├─ Workload Identity Provider  │
│  ├─ Service Account             │
│  └─ Secret Manager              │
│     ├─ github-pat               │
│     ├─ aws-access-key-id        │
│     ├─ aws-secret-access-key    │
│     ├─ docker-username          │
│     ├─ docker-password          │
│     ├─ terraform-cloud-token    │
│     └─ gcp-service-account-key  │
└─────────────────────────────────┘
```

---

## Workflow: `gsm-secrets-sync.yml`

### Trigger Schedule

- **Automatic:** Every Monday at 02:00 UTC (cron: `0 2 * * 1`)
- **Manual:** Via `workflow_dispatch` with optional `force_rotation` flag

### Job: `sync-secrets`

1. **Checkout repository** — pull latest workflow definitions
2. **Authenticate via Workload Identity** — exchange GitHub OIDC token for GCP credential
3. **Validate secrets exist** — verify all 7 GSM secrets are accessible
4. **Fetch secrets** — retrieve latest versions from GSM (idempotent operation)
5. **Sync to GitHub Secrets** — *optional*, if GitHub Secrets sync needed
6. **Audit log** — record sync completion timestamp

### Job: `verify-gsm-access`

Health check to confirm GSM connectivity and list available secrets.

---

## Secrets Managed

| Secret | Purpose | Rotation | Owner |
|--------|---------|----------|-------|
| `github-pat` | GitHub API authentication | Quarterly | DevOps |
| `aws-access-key-id` | AWS IAM | Quarterly | DevOps |
| `aws-secret-access-key` | AWS IAM | Quarterly | DevOps |
| `docker-username` | Docker Hub/Registry auth | Annually or on compromise | DevOps |
| `docker-password` | Docker Hub/Registry auth | Annually or on compromise | DevOps |
| `terraform-cloud-token` | Terraform Cloud API | Quarterly | DevOps |
| `gcp-service-account-key` | GCP fallback (ephemeral) | Monthly | DevOps |

---

## Setup Instructions

### 1. Create GCP GSM Secrets

```bash
PROJECT_ID=$(gcloud config get-value project)
gcloud secrets create github-pat \
  --data-file=- \
  --labels="managed-by=automation,env=ci-cd" \
  --project="$PROJECT_ID"

# Repeat for each secret:
# aws-access-key-id, aws-secret-access-key, docker-username, docker-password, terraform-cloud-token, gcp-service-account-key
```

### 2. Configure Workload Identity Federation

```bash
PROJECT_ID=$(gcloud config get-value project)
GITHUB_REPO_OWNER="kushin77"
GITHUB_REPO_NAME="self-hosted-runner"

# Create identity pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

# Create identity provider (OIDC)
gcloud iam workload-identity-pools providers create-oidc "github" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub,assertion.aud=assertion.aud,assertion.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Create service account
gcloud iam service-accounts create "github-actions" \
  --project="$PROJECT_ID" \
  --display-name="GitHub Actions Service Account"

SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts describe "github-actions" \
  --project="$PROJECT_ID" \
  --format="value(email)")

# Grant Secret Manager access
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.secretAccessor"

# Grant Secret listing (for audit)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.viewer"

# Create Workload Identity binding
WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools providers describe "github" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --condition="resource.name == \"${WORKLOAD_IDENTITY_PROVIDER}/subject/repo:${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}:ref:refs/heads/main\""
```

### 3. Add GitHub Secrets (for workflow reference)

Store these **GitHub Secrets** (these are *references*, not the actual credentials):

| Secret | Value |
|--------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `WIF_PROVIDER` | Workload Identity Provider resource name |
| `WIF_SERVICE_ACCOUNT_EMAIL` | Service account email |

```bash
gh secret set GCP_PROJECT_ID --body "$PROJECT_ID"
gh secret set WIF_PROVIDER --body "$WORKLOAD_IDENTITY_PROVIDER"
gh secret set WIF_SERVICE_ACCOUNT_EMAIL --body "$SERVICE_ACCOUNT_EMAIL"
```

---

## Rotation Procedures

### Quarterly Rotation (GitHub PAT, AWS Keys, Terraform Cloud Token)

1. **Open GCP Secret Manager console:**
   ```
   https://console.cloud.google.com/security/secret-manager/secret?project=$PROJECT_ID
   ```

2. **For each secret to rotate:**
   - Click secret name
   - Click **"New version"**
   - Paste new value
   - Click **"Add secret version"**
   - (Old versions remain for audit; can be disabled)

3. **Trigger sync:**
   ```bash
   gh workflow run gsm-secrets-sync.yml --repo kushin77/self-hosted-runner --ref main
   ```

4. **Verify in CI/CD logs:** Next workflow run will fetch rotated secrets automatically.

### Emergency Rotation (Compromise)

```bash
# Example: rotate Docker credentials immediately
gcloud secrets versions add docker-password \
  --data-file=- \
  --project="$PROJECT_ID" 
  # Paste new password at prompt

# Trigger manual sync
gh workflow run gsm-secrets-sync.yml --repo kushin77/self-hosted-runner --ref main --input force_rotation=true
```

---

## Idempotency & Safety

### Why Rerunning is Safe

1. **GSM fetch is deterministic:** Multiple calls to `gcloud secrets versions access` return identical secret values.
2. **No modifications during fetch:** The sync workflow only *reads* secrets; it does not modify them.
3. **Secrets are immutable once fetched:** No logic to "merge" or "conflate" old/new secrets; latest version is always used.
4. **Workflow stores nothing to disk:** All secrets in memory only (via GitHub Actions environment); cleared on job end.

### Test Idempotency

```bash
# Run the workflow twice in succession
gh workflow run gsm-secrets-sync.yml --repo kushin77/self-hosted-runner --ref main
gh workflow run gsm-secrets-sync.yml --repo kushin77/self-hosted-runner --ref main

# Both should complete successfully with identical results
# No modifications to GitHub Secrets or GCP GSM secrets
```

---

## Monitoring & Auditing

### View Sync Logs

```bash
gh run list --repo kushin77/self-hosted-runner --workflow=gsm-secrets-sync.yml --limit=10
```

### View GCP GSM Audit Logs

```bash
gcloud logging read "resource.type=secretmanager.googleapis.com AND protoPayload.methodName=google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion" \
  --project="$PROJECT_ID" \
  --limit=50 \
  --format=json
```

### Rotation History

```bash
# List all versions of a secret
gcloud secrets versions list github-pat --project="$PROJECT_ID"

# Show who accessed a secret (from audit logs)
gcloud logging read "resource.type=secretmanager.googleapis.com AND protoPayload.request.parent=projects/*/secrets/github-pat" \
  --project="$PROJECT_ID" \
  --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName)"
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Workload identity credentials not found" | Verify WIF provider and service account email in GitHub Secrets match GCP setup. |
| "Secret not found in GSM" | Confirm secret exists: `gcloud secrets describe <secret-id> --project=$PROJECT_ID` |
| "Permission denied when accessing secret" | Verify service account has `roles/secretmanager.secretAccessor` role. |
| "Workflow never triggers (scheduled)" | Check workflow is on default branch (`main`); enable Actions in repo settings. |
| "Secret rotated but workflow still uses old value" | Secrets are fetched *at workflow runtime*. Next run will use latest version. |

---

## Best Practices

1. **Never commit secrets to repo** — all credentials in GSM only.
2. **Use secret version history** — keep old versions for audits; disable (don't delete) if compromised.
3. **Rotate regularly** — set calendar reminders for quarterly rotations.
4. **Test rotation before critical changes** — run sync workflow manually after rotation.
5. **Use Workload Identity Federation** — avoid long-lived service account keys.
6. **Monitor access logs** — audit who accessed which secrets and when.
7. **Keep CI/CD logs clean** — never print secrets in workflow logs (GitHub Actions automatically masks).

---

## References

- [Google Cloud Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [GitHub Actions Workload Identity Federation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Google Workload Identity Federation](https://cloud.google.com/docs/authentication/workload-identity-federation)

---

**End of Document**

