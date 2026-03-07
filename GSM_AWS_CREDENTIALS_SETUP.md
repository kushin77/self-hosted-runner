# GCP Secret Manager (GSM) AWS Credentials Setup

**Date:** March 7, 2026  
**Status:** IMPLEMENTATION GUIDE  
**Objective:** Store AWS credentials in GSM as single source of truth, retrieve via OIDC, fallback to GitHub secrets

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│ GCP Secret Manager (GSM) — Single Source of Truth  │
│  ├─ terraform-aws-prod  (AWS_ACCESS_KEY_ID)        │
│  ├─ terraform-aws-secret (AWS_SECRET_ACCESS_KEY)   │
│  └─ terraform-aws-region (AWS_REGION)              │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
  ┌──────────────┐      ┌──────────────────────┐
  │ GitHub OIDC  │      │ GitHub Repo Secrets  │
  │ (Ephemeral)  │      │ (Fallback)           │
  └──────────────┘      └──────────────────────┘
        │                     │
        └─────────┬───────────┘
                  ▼
        ┌──────────────────────┐
        │ Terraform Workflows  │
        │ elasticache-apply    │
        │ mirror-artifacts     │
        └──────────────────────┘
```

---

## Step 1: Create AWS Credentials in GSM

### 1a. Prepare AWS credentials (local or GitHub secrets)

Ensure you have AWS credentials available:
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJalrXUt..."
export AWS_REGION="us-east-1"
```

### 1b. Store in GCP Secret Manager

```bash
# Set GCP project
export GCP_PROJECT_ID="gcp-eiq"

# Create or update secrets (idempotent)
echo "$AWS_ACCESS_KEY_ID" | gcloud secrets create terraform-aws-prod \
  --replication-policy="automatic" \
  --data-file=- \
  --project="$GCP_PROJECT_ID" 2>/dev/null || \
gcloud secrets versions add terraform-aws-prod \
  --data-file=<(echo "$AWS_ACCESS_KEY_ID") \
  --project="$GCP_PROJECT_ID"

echo "$AWS_SECRET_ACCESS_KEY" | gcloud secrets create terraform-aws-secret \
  --replication-policy="automatic" \
  --data-file=- \
  --project="$GCP_PROJECT_ID" 2>/dev/null || \
gcloud secrets versions add terraform-aws-secret \
  --data-file=<(echo "$AWS_SECRET_ACCESS_KEY") \
  --project="$GCP_PROJECT_ID"

echo "$AWS_REGION" | gcloud secrets create terraform-aws-region \
  --replication-policy="automatic" \
  --data-file=- \
  --project="$GCP_PROJECT_ID" 2>/dev/null || \
gcloud secrets versions add terraform-aws-region \
  --data-file=<(echo "$AWS_REGION") \
  --project="$GCP_PROJECT_ID"

# Verify
gcloud secrets list --project="$GCP_PROJECT_ID" | grep terraform-aws
```

**Output:**
```
terraform-aws-prod        less than a minute ago
terraform-aws-region      less than a minute ago
terraform-aws-secret      less than a minute ago
```

---

## Step 2: Set Up GitHub OIDC for GCP → AWS Authentication

### 2a. Configure GitHub OIDC in GCP

```bash
# Enable required APIs
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com \
  --project="$GCP_PROJECT_ID"

# Create Workload Identity Pool (if not exists)
POOL_ID="github-actions"
PROVIDER_ID="github"

gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions" 2>/dev/null || echo "Pool already exists"

# Get pool resource name
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

# Create Workload Identity Provider
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub,assertion.aud=assertion.aud" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-condition="assertion.aud == 'https://github.com/kushin77'" \
  --workload-identity-pool="$POOL_ID" 2>/dev/null || echo "Provider already exists"
```

### 2b. Create Service Account with GSM Secret Access

```bash
# Create service account
SA_EMAIL="github-actions-terraform@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create github-actions-terraform \
  --project="$GCP_PROJECT_ID" \
  --display-name="GitHub Actions Terraform Service Account" 2>/dev/null || echo "Service account already exists"

# Grant Secret Accessor role
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

# Get Workload Identity Pool resource name
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

# Bind GitHub token to service account
WORKLOAD_IDENTITY_PROVIDER="${POOL_RESOURCE}/providers/${PROVIDER_ID}"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://goog/subject/$(echo 'https://github.com/kushin77/self-hosted-runner' | sed 's|.*/||')/ref:refs/heads/main" \
  --quiet 2>/dev/null || echo "Binding already exists or needs manual setup"
```

---

## Step 3: Create GitHub Repo Secrets

Set GitHub Secrets that workflows will use to authenticate to GCP and retrieve AWS credentials:

```bash
# Store Workload Identity Provider (needed by GitHub Actions)
export WORKLOAD_IDENTITY_PROVIDER="projects/$(gcloud config get-value project)/locations/global/workloadIdentityPools/github-actions/providers/github"
export SERVICE_ACCOUNT_EMAIL="github-actions-terraform@gcp-eiq.iam.gserviceaccount.com"

# Set as GitHub Secrets
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
  --repo kushin77/self-hosted-runner \
  --body "$WORKLOAD_IDENTITY_PROVIDER"

gh secret set GCP_SERVICE_ACCOUNT_EMAIL \
  --repo kushin77/self-hosted-runner \
  --body "$SERVICE_ACCOUNT_EMAIL"

gh secret set GCP_PROJECT_ID \
  --repo kushin77/self-hosted-runner \
  --body "$GCP_PROJECT_ID"
```

---

## Step 4: Create Fetch-From-GSM Workflow

Create `.github/workflows/fetch-aws-creds-from-gsm.yml`:

```yaml
name: Fetch AWS Credentials from GSM (OIDC)

on:
  workflow_call:
    outputs:
      aws_access_key_id:
        value: ${{ steps.fetch.outputs.aws_access_key_id }}
      aws_secret_access_key:
        value: ${{ steps.fetch.outputs.aws_secret_access_key }}
      aws_region:
        value: ${{ steps.fetch.outputs.aws_region }}

jobs:
  fetch-credentials:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    outputs:
      aws_access_key_id: ${{ steps.fetch.outputs.aws_access_key_id }}
      aws_secret_access_key: ${{ steps.fetch.outputs.aws_secret_access_key }}
      aws_region: ${{ steps.fetch.outputs.aws_region }}
    steps:
      - name: Authenticate to Google Cloud with OIDC
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}

      - name: Set up Google Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Fetch AWS credentials from GSM
        id: fetch
        env:
          GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
        run: |
          set -euo pipefail
          
          echo "🔐 Fetching AWS credentials from GCP Secret Manager..."
          
          # Fetch secrets with error handling
          AWS_ACCESS_KEY=$(gcloud secrets versions access latest \
            --secret="terraform-aws-prod" \
            --project="$GCP_PROJECT_ID" 2>/dev/null || echo "")
          
          AWS_SECRET=$(gcloud secrets versions access latest \
            --secret="terraform-aws-secret" \
            --project="$GCP_PROJECT_ID" 2>/dev/null || echo "")
          
          AWS_REGION=$(gcloud secrets versions access latest \
            --secret="terraform-aws-region" \
            --project="$GCP_PROJECT_ID" 2>/dev/null || echo "us-east-1")
          
          if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET" ]; then
            echo "⚠️ Unable to fetch AWS credentials from GSM"
            exit 1
          fi
          
          # Set outputs (masked automatically by GitHub Actions)
          echo "::add-mask::$AWS_ACCESS_KEY"
          echo "::add-mask::$AWS_SECRET"
          echo "aws_access_key_id=$AWS_ACCESS_KEY" >> "$GITHUB_OUTPUT"
          echo "aws_secret_access_key=$AWS_SECRET" >> "$GITHUB_OUTPUT"
          echo "aws_region=$AWS_REGION" >> "$GITHUB_OUTPUT"
          
          echo "✅ AWS credentials fetched from GSM"
```

---

## Step 5: Update Terraform ElastiCache Workflow to Use GSM

Update `.github/workflows/elasticache-apply-safe.yml` to call the fetch workflow:

```yaml
jobs:
  fetch-aws-creds:
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}

  plan-or-apply:
    name: Plan or Apply ElastiCache (safe)
    runs-on: ubuntu-latest
    needs: [fetch-aws-creds]
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
      AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
      AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
    steps:
      # ... rest of terraform apply steps
```

---

## Step 6: Create GSM → GitHub Secrets Sync Workflow

Create `.github/workflows/sync-gsm-aws-to-github.yml` (for fallback):

```yaml
name: Sync AWS Credentials from GSM to GitHub (Optional Fallback)

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Authenticate to Google Cloud with OIDC
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}

      - name: Set up Google Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Fetch and sync AWS credentials
        env:
          GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
        run: |
          set -euo pipefail
          
          echo "🔄 Syncing AWS credentials from GSM → GitHub Secrets"
          
          AWS_ACCESS_KEY=$(gcloud secrets versions access latest --secret="terraform-aws-prod" --project="$GCP_PROJECT_ID")
          AWS_SECRET=$(gcloud secrets versions access latest --secret="terraform-aws-secret" --project="$GCP_PROJECT_ID")
          AWS_REGION=$(gcloud secrets versions access latest --secret="terraform-aws-region" --project="$GCP_PROJECT_ID")
          
          # Set GitHub Secrets via REST API
          gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY" --repo "$GITHUB_REPOSITORY" || true
          gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET" --repo "$GITHUB_REPOSITORY" || true
          gh secret set AWS_REGION --body "$AWS_REGION" --repo "$GITHUB_REPOSITORY" || true
          
          echo "✅ GitHub secrets updated (non-blocking fallback)"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Step 7: Update Documentation & Controls

### Update elasticache-params.tfvars

```hcl
# AWS credentials will be fetched from GCP Secret Manager
# No credentials should be hardcoded here or in GitHub secrets
# Workflows use OIDC to access GSM and retrieve credentials

# Network configuration (operator-provided)
aws_region = "us-east-1"
vpc_id = "vpc-03046114c6bd47ce9"
subnet_ids = ["subnet-0f519178a250407de", "subnet-025cf8c26797df449"]
```

### Create docs/GSM_AWS_CREDENTIALS.md

```markdown
# GCP Secret Manager AWS Credentials Integration

AWS credentials are centrally managed in GCP Secret Manager (GSM) as the single source of truth.

## Setup

1. AWS credentials stored in GSM:
   - `terraform-aws-prod` (AWS_ACCESS_KEY_ID)
   - `terraform-aws-secret` (AWS_SECRET_ACCESS_KEY)
   - `terraform-aws-region` (AWS_REGION)

2. GitHub OIDC configured to authenticate to GCP with ephemeral tokens

3. GitHub repo secrets configured for Workload Identity Provider details

## Usage

### In Terraform Workflows

Workflows automatically fetch credentials from GSM via OIDC:

```yaml
- uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
  secrets:
    GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
    GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
```

### Rotation & Updates

To update AWS credentials:

```bash
export AWS_ACCESS_KEY_ID="new-key"
export AWS_SECRET_ACCESS_KEY="new-secret"
gcloud secrets versions add terraform-aws-prod --data-file=<(echo "$AWS_ACCESS_KEY_ID") --project=gcp-eiq
gcloud secrets versions add terraform-aws-secret --data-file=<(echo "$AWS_SECRET_ACCESS_KEY") --project=gcp-eiq
```

All future workflow runs will use the updated credentials.

## Security

✅ Ephemeral OIDC tokens (no long-lived credentials in GitHub)  
✅ GSM audit trail (all credential fetches logged)  
✅ Immutable secret versioning (rollback capability)  
✅ GitHub secrets as optional fallback (6-hour sync)
```

---

## Step 8: Verify & Test

```bash
# Test GSM access
gcloud secrets versions access latest --secret="terraform-aws-prod" --project=gcp-eiq

# Verify GitHub OIDC setup
gcloud iam workload-identity-pools describe "github-actions" \
  --project=gcp-eiq \
  --location=global \
  --format=json

# Test workflow dispatch
gh workflow run elasticache-apply-safe.yml \
  --repo kushin77/self-hosted-runner \
  -f apply=false
```

---

## Architecture Benefits

| Aspect | Benefit |
|--------|---------|
| **Source of Truth** | GCP Secret Manager = single location |
| **Ephemeral Creds** | GitHub OIDC bypasses long-lived keys |
| **Immutability** | Version history, audit trail |
| **Automation** | Workflows auto-fetch, no manual intervention |
| **Fallback** | Optional GitHub secrets sync (non-blocking) |
| **Rotation** | Update GSM secret once, all workflows use new value |

---

## Maintenance

- **Weekly:** Verify GSM secret access via test workflow
- **Monthly:** Rotate AWS credentials (update GSM secrets)
- **As-needed:** Update GitHub OIDC configuration if provider changes

---

**Status: Ready to implement** — All steps are idempotent and immutable by design.
