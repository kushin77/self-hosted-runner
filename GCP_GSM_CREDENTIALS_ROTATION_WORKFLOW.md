# GCP Google Secret Manager (GSM) - Credentials Rotation Workflow

## Overview

This document defines the automated, hands-off credentials rotation workflow using Google Cloud Secret Manager (GSM) for the self-hosted runner and related infrastructure.

## Architecture

```
┌─────────────────┐
│ GCP GSM Secret  │  Source of truth for all credentials
└────────┬────────┘
         │
         ├─→ GitHub Actions Secrets (synced via OAuth)
         ├─→ Local .env cache (ephemeral, encrypted)
         └─→ Terraform State (referenced, not stored)
```

## Credential Types Managed by GSM

| Secret Name | Purpose | Rotation Frequency | Owner |
|-------------|---------|-------------------|-------|
| `github-pat-automation` | GH Actions automation token | Quarterly | DevSecOps |
| `gcp-service-account-json` | Terraform/GCP access | Quarterly | DevSecOps |
| `aws-access-key-id` | AWS infrastructure access | Quarterly | DevSecOps |
| `aws-secret-access-key` | AWS infrastructure access | Quarterly | DevSecOps |
| `docker-registry-token` | Docker Hub or ECR auth | Quarterly | Platform |
| `terraform-backend-key` | Encrypted TF state backend | Quarterly | DevSecOps |

## Workflow: Automated Quarterly Rotation

### 1. GSM Secret Creation/Update (Pre-automation)

```bash
# Example: Create or update a secret in GSM
gcloud secrets create github-pat-automation \
  --replication-policy="automatic" \
  --data-file=- <<< "$GITHUB_PAT"

# Or update existing secret
echo -n "$GITHUB_PAT" | gcloud secrets versions add github-pat-automation --data-file=-
```

### 2. Sync GSM → GitHub Secrets (Automated Workflow)

**Workflow:** `.github/workflows/gsm-secrets-sync.yml`

```yaml
name: GSM Secrets Sync

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly check on Sundays
  workflow_dispatch:

permissions:
  contents: write
  id-token: write

jobs:
  sync-secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      
      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
      
      - name: Sync GSM secrets to GitHub
        run: |
          set -e
          for secret_name in \
            github-pat-automation \
            gcp-service-account-json \
            aws-access-key-id \
            aws-secret-access-key \
            docker-registry-token; do
            
            secret_value=$(gcloud secrets versions access latest --secret=$secret_name)
            gh secret set "$secret_name" --body "$secret_value"
            echo "Synced $secret_name"
          done
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Local Ephemeral Cache (CI/Runner)

**In CI jobs and runner startup:**

```bash
# Fetch from GSM at job start (ephemeral, not persisted)
export AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret=aws-access-key-id)
export AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret=aws-secret-access-key)

# Use secret in job
terraform plan

# Secret automatically cleared from memory at job end (no cleanup needed)
```

### 4. Terraform Backend Encryption

**Store encrypted backend state in GCS:**

```hcl
terraform {
  backend "gcs" {
    bucket  = "terraform-state-prod"
    prefix  = "self-hosted-runner"
    encryption_key = var.gcs_encryption_key  # Fetched from GSM at init
  }
}
```

## Manual Credential Rotation

### For Urgent Rotation (CVE, compromise):

```bash
#!/bin/bash
set -e
SECRET_NAME=$1
NEW_VALUE=$2

# 1. Update GSM
echo -n "$NEW_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=-

# 2. Enable new version (automatic, but can be explicit)
gcloud secrets versions enable $(gcloud secrets versions list $SECRET_NAME --limit=1 --format="value(name)")

# 3. Sync to GitHub (manual or trigger workflow)
gh workflow run gsm-secrets-sync.yml --ref main

# 4. Wait for sync to complete
sleep 30

# 5. Rerun any active jobs that need the new credential
gh run list --repo kushin77/self-hosted-runner --limit 5 --json databaseId | jq '.[].databaseId' | while read id; do
  gh run rerun $id --repo kushin77/self-hosted-runner || true
done

echo "Rotation complete for $SECRET_NAME"
```

## GitHub Actions Integration

### Sample Workflow: Terraform Apply with GSM Secrets

```yaml
name: Terraform Apply (GSM-backed)

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'staging'

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: self-hosted
    environment: ${{ github.event.inputs.environment }}
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      
      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
      
      - name: Load AWS credentials from GSM
        run: |
          export AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret=aws-access-key-id)
          export AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret=aws-secret-access-key)
          echo "AWS_ACCESS_KEY_ID_MASKED=***" >> $GITHUB_ENV
          echo "AWS_SECRET_ACCESS_KEY_MASKED=***" >> $GITHUB_ENV
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      
      - name: Terraform Plan
        run: |
          terraform init
          terraform plan -out=tfplan
      
      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
```

## Immutability & Idempotency

- **No hardcoded secrets** in any repository files.
- **All credentials fetched at runtime** from GSM (immutable source of truth).
- **Rotation workflows are idempotent** (safe to run multiple times).
- **Ephemeral caches** — secrets never persisted on disk or in logs.

## Auditing

### View all secret access logs:

```bash
# Cloud Audit Logs in GCP Console or via gcloud
gcloud logging read "resource.type=secretmanager.googleapis.com AND logName:projects/{PROJECT_ID}/logs/cloudaudit.googleapis.com" \
  --format=json | jq '.'
```

### GitHub Actions secret usage:

All GitHub Actions workflows that use secrets are logged automatically in Actions audit logs. Review via:
```bash
gh api repos/kushin77/self-hosted-runner/audit-log --paginate
```

## Best Practices

1. **Never print secrets in logs.** Always use `${{ secrets.SECRET_NAME }}` masking.
2. **Rotate quarterly** at minimum; immediately for CVEs.
3. **Use separate secrets** for different services (AWS, GCP, Docker, etc.).
4. **Audit rotation logs** regularly (quarterly security review).
5. **Test rotation workflow** in staging before deploying to production.
6. **Encrypt GSM secrets** in transit (automatic via GCP).
7. **Use Workload Identity Federation** (OIDC) instead of service account keys where possible.

## Troubleshooting

### Secret not syncing to GitHub?
- Check GitHub CLI authentication: `gh auth status`
- Verify GSM secret exists: `gcloud secrets list`
- Check workflow logs: `gh run list --repo kushin77/self-hosted-runner`

### Terraform can't access GSM secret?
- Verify service account has `secretmanager.secretAccessor` role
- Check OIDC token issuer is trusted in Workload Identity

### Secret exposed in logs?
- Immediately rotate via: `gcloud secrets versions destroy {VERSION_ID} --secret={SECRET_NAME}`
- Audit Actions workflow for leaked output
- Create incident in tracking issue #1396

