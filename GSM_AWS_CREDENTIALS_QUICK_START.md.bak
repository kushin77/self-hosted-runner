# GSM AWS Credentials - Quick Start Implementation

**Date:** March 7, 2026  
**Objective:** Set up GCP Secret Manager for AWS credential storage with GitHub OIDC authentication  
**Time:** ~20 minutes to implement

---

## Prerequisites

- ✅ AWS credentials (Access Key ID & Secret Access Key)
- ✅ GCP project (`gcp-eiq`) with IAM permissions
- ✅ `gcloud` CLI installed and authenticated
- ✅ `gh` CLI installed and authenticated with repo:secrets permission
- ✅ GitHub repo: `kushin77/self-hosted-runner`

---

## Phase 1: Create AWS Credentials in GSM (5 mins)

### 1.1 Set Environment Variables

```bash
# Export your AWS credentials
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
export AWS_REGION="us-east-1"                # Your AWS Region

# GCP configuration
export GCP_PROJECT_ID="gcp-eiq"
export GCP_REGION="us-east-1"
```

### 1.2 Create GSM Secrets

```bash
# Create or update terraform-aws-prod (Access Key ID)
echo "$AWS_ACCESS_KEY_ID" | gcloud secrets create terraform-aws-prod \
  --replication-policy="automatic" \
  --data-file=- \
  --project="$GCP_PROJECT_ID" 2>/dev/null || \
gcloud secrets versions add terraform-aws-prod \
  --data-file=<(echo "$AWS_ACCESS_KEY_ID") \
  --project="$GCP_PROJECT_ID"

# Create or update terraform-aws-secret (Secret Access Key)
echo "$AWS_SECRET_ACCESS_KEY" | gcloud secrets create terraform-aws-secret \
  --replication-policy="automatic" \
  --data-file=- \
  --project="$GCP_PROJECT_ID" 2>/dev/null || \
gcloud secrets versions add terraform-aws-secret \
  --data-file=<(echo "$AWS_SECRET_ACCESS_KEY") \
  --project="$GCP_PROJECT_ID"

# Create or update terraform-aws-region (Region)
echo "$AWS_REGION" | gcloud secrets create terraform-aws-region \
  --replication-policy="automatic" \
  --data-file=- \
  --project="$GCP_PROJECT_ID" 2>/dev/null || \
gcloud secrets versions add terraform-aws-region \
  --data-file=<(echo "$AWS_REGION") \
  --project="$GCP_PROJECT_ID"
```

### 1.3 Verify Secrets Created

```bash
gcloud secrets list \
  --project="$GCP_PROJECT_ID" \
  --filter="name:terraform-aws*" \
  --format="table(name,created)"

# Expected output:
# NAME                         CREATED
# terraform-aws-prod           2026-03-07T...
# terraform-aws-region         2026-03-07T...
# terraform-aws-secret         2026-03-07T...
```

---

## Phase 2: Set Up GitHub OIDC for GCP (8 mins)

### 2.1 Enable Required APIs

```bash
gcloud services enable iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$GCP_PROJECT_ID"
```

### 2.2 Create Workload Identity Pool & Provider

```bash
# Set configuration
POOL_ID="github-actions"
PROVIDER_ID="github"
OWNER="kushin77"
REPO="self-hosted-runner"

# Create Workload Identity Pool
gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions" 2>/dev/null || echo "✓ Pool already exists"

# Create Workload Identity Provider
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub OIDC" \
  --attribute-mapping="google.subject=assertion.sub,assertion.aud=assertion.aud" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-condition="assertion.aud == 'https://github.com/$OWNER'" \
  --workload-identity-pool="$POOL_ID" 2>/dev/null || echo "✓ Provider already exists"
```

### 2.3 Create Service Account

```bash
SA_NAME="github-actions-terraform"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
gcloud iam service-accounts create "$SA_NAME" \
  --project="$GCP_PROJECT_ID" \
  --display-name="GitHub Actions Terraform" 2>/dev/null || echo "✓ Service account already exists"

# Grant Secret Manager Secret Accessor role
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

echo "✅ Service account created: $SA_EMAIL"
```

### 2.4 Link GitHub Identity to Service Account

```bash
# Get full resource name of the provider
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

WORKLOAD_IDENTITY_PROVIDER="${POOL_RESOURCE}/providers/${PROVIDER_ID}"

echo "Workload Identity Provider: $WORKLOAD_IDENTITY_PROVIDER"

# Bind GitHub token to service account
# Allow workflows from main branch
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://goog/subject/repo:${OWNER}/${REPO}:ref:refs/heads/main" \
  --quiet 2>/dev/null || echo "✓ Binding already exists"

# Allow workflows from all branches (optional, more permissive)
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://goog/subject/repo:${OWNER}/${REPO}:*" \
  --quiet 2>/dev/null || true

echo "✅ GitHub identity linked to service account"
```

---

## Phase 3: Configure GitHub Secrets (4 mins)

### 3.1 Set Required GitHub Secrets

```bash
REPO="kushin77/self-hosted-runner"

# Get values needed
WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)" | sed "s|$|/providers/$PROVIDER_ID|")

SERVICE_ACCOUNT_EMAIL="github-actions-terraform@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Set secrets in GitHub
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
  --repo "$REPO" \
  --body "$WORKLOAD_IDENTITY_PROVIDER"

gh secret set GCP_SERVICE_ACCOUNT_EMAIL \
  --repo "$REPO" \
  --body "$SERVICE_ACCOUNT_EMAIL"

gh secret set GCP_PROJECT_ID \
  --repo "$REPO" \
  --body "$GCP_PROJECT_ID"

echo "✅ GitHub secrets configured"
echo ""
echo "Secrets set:"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: $WORKLOAD_IDENTITY_PROVIDER"
echo "  GCP_SERVICE_ACCOUNT_EMAIL: $SERVICE_ACCOUNT_EMAIL"
echo "  GCP_PROJECT_ID: $GCP_PROJECT_ID"
```

### 3.2 Verify Secrets

```bash
gh secret list --repo "$REPO" | grep GCP_
```

Expected output:
```
GCP_PROJECT_ID           
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
GCP_WORKLOAD_IDENTITY_PROVIDER    
```

---

## Phase 4: Create GitHub Workflows (automated by checkout)

The workflow files are already included in the repository:

- `.github/workflows/fetch-aws-creds-from-gsm.yml` — Fetches AWS credentials from GSM via OIDC
- `.github/workflows/sync-gsm-aws-to-github.yml` — Optional: syncs credentials to GitHub as fallback
- `.github/workflows/elasticache-apply-gsm.yml` — Example: ElastiCache deployment using GSM credentials

These are ready to use immediately.

---

## Phase 5: Verification & Testing (3 mins)

### 5.1 Verify GSM Access

```bash
# Test manual secret retrieval
ACCESSED=$(gcloud secrets versions access latest \
  --secret="terraform-aws-prod" \
  --project="$GCP_PROJECT_ID")

if [ -n "$ACCESSED" ]; then
  echo "✅ GSM secret successfully accessed"
else
  echo "❌ Failed to access GSM secret"
fi
```

### 5.2 Test Workflow (Dry Run)

```bash
# Dispatch fetch-aws-creds-from-gsm.yml workflow manually
gh workflow run fetch-aws-creds-from-gsm.yml \
  --repo "$REPO"

echo "⏳ Workflow dispatched. Check GitHub Actions for results."
echo "   URL: https://github.com/$REPO/actions"
```

### 5.3 Monitor Workflow Execution

```bash
# Wait a few seconds, then check status
sleep 5

gh run list --repo "$REPO" \
  --workflow="fetch-aws-creds-from-gsm.yml" \
  --limit=1 \
  --json="status,conclusion,name,createdAt"
```

---

## Phase 6: Use in Terraform Workflows

### 6.1 Update Your Workflows

To use GSM AWS credentials in any workflow, add this job:

```yaml
jobs:
  fetch-aws-creds:
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}

  your-job:
    needs: [fetch-aws-creds]
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
      AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
      AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
    steps:
      # Your Terraform/AWS steps here
```

### 6.2 Example: Deploy ElastiCache

```bash
gh workflow run elasticache-apply-gsm.yml \
  --repo "$REPO" \
  -f apply=false \
  -f environment=prod
```

This will:
1. ✅ Fetch AWS credentials from GSM using OIDC
2. ✅ Plan Terraform changes
3. ✅ Display results

To apply changes (with approval):

```bash
gh workflow run elasticache-apply-gsm.yml \
  --repo "$REPO" \
  -f apply=true \
  -f environment=prod
```

---

## Troubleshooting

### Issue: "Workload Identity Provider configuration not found"

**Solution:** Verify the Workload Identity Provider name in Phase 2.4:

```bash
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "github-actions" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

echo "Provider resource: ${POOL_RESOURCE}/providers/github"
```

### Issue: "Permission denied: User is not authorized to access this secret"

**Solution:** Verify the service account has Secret Manager access:

```bash
SA_EMAIL="github-actions-terraform@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects get-iam-policy "$GCP_PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA_EMAIL}"
```

Should show `roles/secretmanager.secretAccessor`.

### Issue: Workflow fails with "Unable to fetch AWS credentials from GSM"

**Solution:** 

1. Verify secrets exist:
   ```bash
   gcloud secrets list --project="$GCP_PROJECT_ID" | grep terraform-aws
   ```

2. Test manual fetch:
   ```bash
   gcloud secrets versions access latest --secret="terraform-aws-prod" --project="$GCP_PROJECT_ID"
   ```

3. Check GitHub OIDC token generation in workflow logs

---

## Security Checklist

| Aspect | Status | Notes |
|--------|--------|-------|
| AWS Credentials in GSM | ✅ | Access Key ID & Secret stored securely |
| GitHub OIDC Configured | ✅ | Ephemeral token (no long-lived creds) |
| Service Account Scoped | ✅ | Only Secret Manager access granted |
| Workflow Fetches from GSM | ✅ | Primary credential source |
| GitHub Secrets Fallback | ✅ | Optional 6-hour sync (non-blocking) |
| Audit Trail | ✅ | All GSM accesses logged in GCP |

---

## Next Steps

1. **Rotate AWS Credentials** (every 90 days):
   ```bash
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
   gcloud secrets versions add terraform-aws-prod --data-file=<(echo "$AWS_ACCESS_KEY_ID") --project="$GCP_PROJECT_ID"
   gcloud secrets versions add terraform-aws-secret --data-file=<(echo "$AWS_SECRET_ACCESS_KEY") --project="$GCP_PROJECT_ID"
   ```

2. **Monitor Credential Usage**:
   - Check GCP Audit Logs for "secretmanager.googleapis.com" events
   - Review GitHub Actions workflow logs

3. **Update Documentation**:
   - Add to team runbooks
   - Document credential rotation schedule

---

## Summary

✅ **Completed:**
- AWS credentials stored in GCP Secret Manager
- GitHub OIDC authentication configured
- Workflows set up to fetch credentials
- Fallback GitHub secrets sync available

**Architecture Benefits:**
- Single source of truth (GSM)
- Ephemeral credentials (OIDC)
- Immutable secret versioning
- Comprehensive audit trail
- Easy rotation (update GSM once, all workflows use new creds)

---

**Implementation complete!** → Workflows now fetch AWS credentials from GCP Secret Manager securely.
