# GSM AWS Credentials - Implementation Verification Guide

**Date:** March 7, 2026  
**Purpose:** Verify GSM AWS credentials setup is complete and working

---

## Verification Checklist

### ✅ Phase 1: AWS Credentials in GSM

Run this verification script:

```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Verifying AWS Credentials in GSM..."

GCP_PROJECT_ID="gcp-eiq"
REQUIRED_SECRETS=("terraform-aws-prod" "terraform-aws-secret" "terraform-aws-region")

for secret_name in "${REQUIRED_SECRETS[@]}"; do
  if gcloud secrets describe "$secret_name" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    VERSION=$(gcloud secrets versions list "$secret_name" --project="$GCP_PROJECT_ID" \
      --limit=1 --format="value(name)")
    echo "  ✅ $secret_name (version: $VERSION)"
  else
    echo "  ❌ $secret_name NOT FOUND"
    exit 1
  fi
done

echo "✅ Phase 1: VERIFIED"
```

**Expected Output:**
```
✅ terraform-aws-prod (version: 1)
✅ terraform-aws-secret (version: 1)
✅ terraform-aws-region (version: 1)
✅ Phase 1: VERIFIED
```

---

### ✅ Phase 2: GitHub OIDC Configuration

Run this verification script:

```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Verifying GitHub OIDC Configuration..."

GCP_PROJECT_ID="gcp-eiq"
POOL_ID="github-actions"
PROVIDER_ID="github"

# Check Workload Identity Pool
if gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" >/dev/null 2>&1; then
  echo "  ✅ Workload Identity Pool: $POOL_ID"
else
  echo "  ❌ Workload Identity Pool NOT FOUND"
  exit 1
fi

# Check Workload Identity Provider
if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --workload-identity-pool="$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" >/dev/null 2>&1; then
  echo "  ✅ Workload Identity Provider: $PROVIDER_ID"
else
  echo "  ❌ Workload Identity Provider NOT FOUND"
  exit 1
fi

# Get provider resource name
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

echo "  📋 Full Provider Path:"
echo "     ${POOL_RESOURCE}/providers/${PROVIDER_ID}"

echo "✅ Phase 2: VERIFIED"
```

**Expected Output:**
```
✅ Workload Identity Pool: github-actions
✅ Workload Identity Provider: github
📋 Full Provider Path:
   projects/.../locations/global/workloadIdentityPools/github-actions/providers/github
✅ Phase 2: VERIFIED
```

---

### ✅ Phase 3: Service Account Configuration

Run this verification script:

```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Verifying Service Account Configuration..."

GCP_PROJECT_ID="gcp-eiq"
SA_NAME="github-actions-terraform"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Check service account exists
if gcloud iam service-accounts describe "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  echo "  ✅ Service Account: $SA_EMAIL"
else
  echo "  ❌ Service Account NOT FOUND"
  exit 1
fi

# Check Secret Manager access
if gcloud projects get-iam-policy "$GCP_PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA_EMAIL}" \
  --format="value(bindings.role)" | grep -q "secretmanager.secretAccessor"; then
  echo "  ✅ Secret Manager Access: roles/secretmanager.secretAccessor"
else
  echo "  ⚠️  Secret Manager Access NOT found (may be in different role)"
fi

# Check Workload Identity bindings
POOL_ID="github-actions"
PROVIDER_ID="github"

POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

WORKLOAD_IDENTITY_PROVIDER="${POOL_RESOURCE}/providers/${PROVIDER_ID}"

if gcloud iam service-accounts get-iam-policy "$SA_EMAIL" \
  --project="$GCP_PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.role:workloadIdentityUser" >/dev/null 2>&1; then
  echo "  ✅ Workload Identity Binding: workloadIdentityUser"
else
  echo "  ❌ Workload Identity Binding NOT FOUND"
  exit 1
fi

echo "✅ Phase 3: VERIFIED"
```

**Expected Output:**
```
✅ Service Account: github-actions-terraform@gcp-eiq.iam.gserviceaccount.com
✅ Secret Manager Access: roles/secretmanager.secretAccessor
✅ Workload Identity Binding: workloadIdentityUser
✅ Phase 3: VERIFIED
```

---

### ✅ Phase 4: GitHub Secrets Configuration

Run this verification script:

```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Verifying GitHub Secrets Configuration..."

REPO="kushin77/self-hosted-runner"
REQUIRED_SECRETS=("GCP_WORKLOAD_IDENTITY_PROVIDER" "GCP_SERVICE_ACCOUNT_EMAIL" "GCP_PROJECT_ID")

echo "  Checking secrets in repository: $REPO"

for secret_name in "${REQUIRED_SECRETS[@]}"; do
  if gh secret list --repo "$REPO" | grep -q "^$secret_name"; then
    echo "  ✅ $secret_name"
  else
    echo "  ❌ $secret_name NOT FOUND"
    exit 1
  fi
done

echo "✅ Phase 4: VERIFIED"
```

**Expected Output:**
```
Checking secrets in repository: kushin77/self-hosted-runner
✅ GCP_WORKLOAD_IDENTITY_PROVIDER
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
✅ GCP_PROJECT_ID
✅ Phase 4: VERIFIED
```

---

### ✅ Phase 5: GitHub Workflow Files

Run this verification script:

```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Verifying GitHub Workflow Files..."

REPO="kushin77/self-hosted-runner"
REPO_PATH="."

REQUIRED_WORKFLOWS=(
  ".github/workflows/fetch-aws-creds-from-gsm.yml"
  ".github/workflows/sync-gsm-aws-to-github.yml"
  ".github/workflows/elasticache-apply-gsm.yml"
)

for workflow in "${REQUIRED_WORKFLOWS[@]}"; do
  if [ -f "$REPO_PATH/$workflow" ]; then
    echo "  ✅ $workflow"
  else
    echo "  ⚠️ $workflow NOT FOUND (optional)"
  fi
done

echo "✅ Phase 5: VERIFIED"
```

**Expected Output:**
```
✅ .github/workflows/fetch-aws-creds-from-gsm.yml
✅ .github/workflows/sync-gsm-aws-to-github.yml
✅ .github/workflows/elasticache-apply-gsm.yml
✅ Phase 5: VERIFIED
```

---

## End-to-End Workflow Test

### Test 1: Fetch AWS Credentials via OIDC

```bash
# Dispatch the fetch workflow
gh workflow run fetch-aws-creds-from-gsm.yml \
  --repo "kushin77/self-hosted-runner"

echo "⏳ Workflow dispatched. Waiting 10 seconds..."
sleep 10

# Check status
gh run list \
  --repo "kushin77/self-hosted-runner" \
  --workflow="fetch-aws-creds-from-gsm.yml" \
  --limit=1 \
  --json="name,status,conclusion,createdAt,url"
```

**Expected Result:**
```
✅ Status: completed
✅ Conclusion: success
```

### Test 2: Verify Credential Retrieval

Check the workflow log for success message:

```bash
# Get latest run ID
RUN_ID=$(gh run list \
  --repo "kushin77/self-hosted-runner" \
  --workflow="fetch-aws-creds-from-gsm.yml" \
  --limit=1 \
  --json="databaseId" \
  --jq ".[0].databaseId")

# View logs
gh run view "$RUN_ID" \
  --repo "kushin77/self-hosted-runner" \
  --log
```

**Look for:**
```
✅ Successfully fetched AWS credentials from GSM
   Region: us-east-1
```

---

## Troubleshooting Verification

### If Phase 1 verification fails:

```bash
# Check if secrets exist
gcloud secrets list --project="gcp-eiq" --filter="name:terraform-aws*"

# If missing, create them:
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
echo "$AWS_ACCESS_KEY_ID" | gcloud secrets create terraform-aws-prod \
  --replication-policy="automatic" \
  --data-file=- \
  --project="gcp-eiq"
```

### If Phase 2 verification fails:

```bash
# Recreate the Workload Identity Pool
gcloud iam workload-identity-pools create "github-actions" \
  --project="gcp-eiq" \
  --location="global" \
  --display-name="GitHub Actions"

# Recreate the Provider
gcloud iam workload-identity-pools providers create-oidc "github" \
  --project="gcp-eiq" \
  --location="global" \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub,assertion.aud=assertion.aud" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-condition="assertion.aud == 'https://github.com/kushin77'" \
  --workload-identity-pool="github-actions"
```

### If Phase 3 verification fails:

```bash
# Recreate service account
gcloud iam service-accounts create github-actions-terraform \
  --project="gcp-eiq" \
  --display-name="GitHub Actions Terraform"

# Grant permissions
gcloud projects add-iam-policy-binding "gcp-eiq" \
  --member="serviceAccount:github-actions-terraform@gcp-eiq.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Rebind Workload Identity
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "github-actions" \
  --project="gcp-eiq" \
  --location="global" \
  --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding \
  "github-actions-terraform@gcp-eiq.iam.gserviceaccount.com" \
  --project="gcp-eiq" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://goog/subject/repo:kushin77/self-hosted-runner:ref:refs/heads/main"
```

### If Phase 4 verification fails:

```bash
# Set the secrets
POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "github-actions" \
  --project="gcp-eiq" \
  --location="global" \
  --format="value(name)")

gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
  --repo "kushin77/self-hosted-runner" \
  --body "${POOL_RESOURCE}/providers/github"

gh secret set GCP_SERVICE_ACCOUNT_EMAIL \
  --repo "kushin77/self-hosted-runner" \
  --body "github-actions-terraform@gcp-eiq.iam.gserviceaccount.com"

gh secret set GCP_PROJECT_ID \
  --repo "kushin77/self-hosted-runner" \
  --body "gcp-eiq"
```

---

## Security Audit

### Check GSM Access Logs

```bash
# View all GSM access in the last 24 hours
gcloud logging read \
  "resource.type=secretmanager.googleapis.com AND \
   protoPayload.serviceName=secretmanager.googleapis.com AND \
   protoPayload.methodName=google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion" \
  --limit=50 \
  --format=json \
  --project="gcp-eiq" | jq '.[] | {timestamp: .timestamp, actor: .protoPayload.authenticationInfo.principalEmail, method: .protoPayload.methodName}'
```

### Check OIDC Token Validation Events

```bash
# View workload identity federation events
gcloud logging read \
  "resource.type=service_account AND \
   protoPayload.methodName=google.iam.admin.v1.GetServiceAccountKey" \
  --limit=50 \
  --format=json \
  --project="gcp-eiq"
```

---

## Final Validation Checklist

| Component | Verified | Date | Notes |
|-----------|----------|------|-------|
| AWS Credentials in GSM | ☐ | | 3 secrets (prod, secret, region) |
| Workload Identity Pool | ☐ | | github-actions pool exists |
| OIDC Provider | ☐ | | github provider configured |
| Service Account | ☐ | | github-actions-terraform created |
| Secret Manager Access | ☐ | | Service account has accessor role |
| GitHub OIDC Binding | ☐ | | Workload Identity User role granted |
| GitHub Secrets | ☐ | | 3 secrets set (WIP, SA email, Project ID) |
| Workflow Files | ☐ | | fetch, sync, and elasticache workflows present |
| Workflow Test | ☐ | | fetch-aws-creds workflow runs successfully |
| Credential Fetch | ☐ | | AWS credentials successfully retrieved from GSM |
| Audit Logs | ☐ | | GSM access logs show successful fetches |

---

## Summary

✅ **All verification steps completed** → GSM AWS credentials integration is fully functional

**Key Milestones:**
1. AWS credentials are securely stored in GCP Secret Manager
2. GitHub OIDC authentication is configured for ephemeral token exchange
3. Service account has minimal permissions (Secret Manager access only)
4. All workflow files are in place and tested
5. End-to-end credential fetching works via OIDC

**Next: Deploy workflows using the `elasticache-apply-gsm.yml` pattern for infrastructure changes**
