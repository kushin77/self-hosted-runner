# GSM AWS Credentials - Workflow Integration Guide

**Date:** March 7, 2026  
**Purpose:** Update existing GitHub Actions workflows to use GSM credentials  
**Scope:** All workflows that require AWS authentication

---

## Integration Pattern

### Before: Using GitHub Secrets Directly

```yaml
name: Mirror Artifacts (Old Pattern)

on:
  workflow_dispatch:

jobs:
  mirror:
    runs-on: ubuntu-latest
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: ${{ secrets.AWS_REGION }}
    steps:
      - run: aws s3 sync s3://source s3://dest
```

**Problems:**
- ❌ Credentials stored in GitHub (visible to repo admins)
- ❌ Long-lived credentials (valid for 90 days)
- ❌ Manual rotation required
- ❌ No centralized audit trail

---

### After: Using GSM with OIDC

```yaml
name: Mirror Artifacts (New Pattern - GSM OIDC)

on:
  workflow_dispatch:

jobs:
  fetch-aws-creds:
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}

  mirror:
    runs-on: ubuntu-latest
    needs: [fetch-aws-creds]
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
      AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
      AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
    steps:
      - run: aws s3 sync s3://source s3://dest
```

**Benefits:**
- ✅ Credentials only in GSM (never in GitHub)
- ✅ Ephemeral credentials (15-30 min lifetime)
- ✅ Automatic rotation via GSM
- ✅ Centralized audit trail in GCP

---

## Step-by-Step Migration

### Step 1: Add Fetch Job

Add this job to your workflow (copy-paste):

```yaml
jobs:
  fetch-aws-creds:
    name: Fetch AWS Credentials from GSM
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
```

### Step 2: Add Dependency

Add `needs: [fetch-aws-creds]` to the job that uses AWS credentials:

```yaml
  my-aws-job:
    runs-on: ubuntu-latest
    needs: [fetch-aws-creds]  # ← Add this line
    steps: ...
```

### Step 3: Update Environment Variables

Replace GitHub secrets with fetched outputs:

**Before:**
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  AWS_REGION: ${{ secrets.AWS_REGION }}
```

**After:**
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
  AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
  AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
```

### Step 4: Remove Old GitHub Secrets

After verifying the new workflow works, you can delete the old GitHub secrets:

**Keep for 30 days as fallback, then remove:**
- ~~AWS_ACCESS_KEY_ID~~
- ~~AWS_SECRET_ACCESS_KEY~~
- ~~AWS_REGION~~

---

## Example Workflows

### Example 1: Mirror Artifacts Workflow

**File:** `.github/workflows/mirror-artifacts-gsm.yml`

> 📝 *Note:* Several other AWS‑dependent workflows (`terraform-auto-apply`, `terraform-dns-apply`, `ansible-runbooks`, `docker-hub-weekly-backup`, `docker-hub-auto-secret-rotation`, `multi-region-*`, `mirror-release-artifacts`, `docker-hub-cascading-failover-test`, etc.) have already been patched to fetch credentials automatically. Use the pattern below for any additional jobs.*

```yaml
name: Mirror Artifacts (GSM Credentials)

on:
  workflow_dispatch:
    inputs:
      source_bucket:
        description: 'Source S3 bucket'
        required: false
        default: 'source-artifacts'
      dest_bucket:
        description: 'Destination S3 bucket'
        required: false
        default: 'dest-artifacts'

jobs:
  # Step 1: Fetch AWS credentials from GSM
  fetch-aws-creds:
    name: Fetch AWS Credentials from GSM
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}

  # Step 2: Mirror artifacts using fetched credentials
  mirror:
    name: Mirror S3 Artifacts
    runs-on: ubuntu-latest
    needs: [fetch-aws-creds]
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
      AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
      AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Install AWS CLI
        uses: unfor19/install-aws-cli-action@v1

      - name: Verify AWS Credentials
        run: |
          echo "🔍 Verifying AWS credentials..."
          aws sts get-caller-identity --region "$AWS_REGION"

      - name: Mirror Artifacts
        run: |
          set -euo pipefail
          
          SOURCE_BUCKET="${{ github.event.inputs.source_bucket }}"
          DEST_BUCKET="${{ github.event.inputs.dest_bucket }}"
          
          echo "📦 Mirroring S3 artifacts..."
          echo "  Source: s3://${SOURCE_BUCKET}"
          echo "  Destination: s3://${DEST_BUCKET}"
          
          aws s3 sync "s3://${SOURCE_BUCKET}" "s3://${DEST_BUCKET}" \
            --region "$AWS_REGION" \
            --delete \
            --metadata "mirrored-date=$(date -u +'%Y-%m-%d')' \
            --exact-timestamps
          
          echo "✅ Mirror completed"

      - name: Verify Mirror
        run: |
          set -euo pipefail
          
          SOURCE_BUCKET="${{ github.event.inputs.source_bucket }}"
          DEST_BUCKET="${{ github.event.inputs.dest_bucket }}"
          
          SOURCE_COUNT=$(aws s3 ls "s3://${SOURCE_BUCKET}" --recursive --region "$AWS_REGION" | wc -l)
          DEST_COUNT=$(aws s3 ls "s3://${DEST_BUCKET}" --recursive --region "$AWS_REGION" | wc -l)
          
          echo "🔍 Verification:"
          echo "  Source count: ${SOURCE_COUNT}"
          echo "  Destination count: ${DEST_COUNT}"
          
          if [ "$SOURCE_COUNT" -eq "$DEST_COUNT" ]; then
            echo "✅ Mirror verified"
          else
            echo "⚠️ Counts differ (may be normal, verify manually)"
          fi
```

### Example 2: ElastiCache Deployment Workflow

**File:** `.github/workflows/elasticache-apply-gsm.yml` (already created)

This workflow shows the full pattern with planning, applying, and validation phases.

### Example 3: Custom Deployment Workflow

**Template for any AWS-based deployment:**

```yaml
name: Deploy Infrastructure (GSM Credentials)

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment'
        required: false
        default: 'prod'
        type: choice
        options:
          - dev
          - staging
          - prod
      apply:
        description: 'Apply changes'
        required: false
        default: false
        type: boolean

jobs:
  # 1. Fetch credentials
  fetch-aws-creds:
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT_EMAIL: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}

  # 2. Plan infrastructure changes
  plan:
    name: Plan Infrastructure
    runs-on: ubuntu-latest
    needs: [fetch-aws-creds]
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
      AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
      AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0
      - run: terraform init
      - run: terraform plan -out=tfplan
      - uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: tfplan

  # 3. Apply (conditional)
  apply:
    name: Apply Infrastructure
    runs-on: ubuntu-latest
    needs: [fetch-aws-creds, plan]
    if: ${{ github.event.inputs.apply == 'true' }}
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-aws-creds.outputs.aws_access_key_id }}
      AWS_SECRET_ACCESS_KEY: ${{ needs.fetch-aws-creds.outputs.aws_secret_access_key }}
      AWS_REGION: ${{ needs.fetch-aws-creds.outputs.aws_region }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: tfplan
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0
      - run: terraform init
      - run: terraform apply tfplan
```

---

## Best Practices

### 1. Always Fetch First

✅ **Correct:**
```yaml
jobs:
  fetch-creds:
    uses: ./.github/workflows/fetch-aws-creds-from-gsm.yml
    secrets: ...

  deploy:
    needs: [fetch-creds]
    env:
      AWS_ACCESS_KEY_ID: ${{ needs.fetch-creds.outputs.aws_access_key_id }}
```

❌ **Incorrect:**
```yaml
jobs:
  deploy:
    env:
      # Don't use GitHub secrets directly
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
```

### 2. Use Concurrency for Safety

```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true
```

Prevents duplicate concurrent deployments.

### 3. Require Plan Review Before Apply

```yaml
jobs:
  apply:
    if: ${{ github.event.inputs.apply == 'true' }}
```

Manual approval via workflow_dispatch input.

### 4. Log for Audit Trail

```yaml
steps:
  - name: Terraform Apply
    run: |
      terraform apply tfplan | tee apply-output.txt
  - uses: actions/upload-artifact@v4
    with:
      name: apply-output
      path: apply-output.txt
```

### 5. Validate After Changes

```yaml
steps:
  - name: Validate Deployment
    run: |
      aws elasticache describe-cache-clusters --region "$AWS_REGION"
```

---

## Testing Your Integration

> 🧠 *Since most known AWS workflows have been auto-migrated, you can focus on running them to validate. If you create new AWS‑using jobs, apply the same fetch pattern.*

### Test 1: Verify Fetch Works

```bash
gh workflow run fetch-aws-creds-from-gsm.yml \
  --repo "kushin77/self-hosted-runner"

# Check status
gh run list --repo "kushin77/self-hosted-runner" \
  --workflow="fetch-aws-creds-from-gsm.yml" \
  --limit=1
```

### Test 2: Run Your Updated Workflow

```bash
gh workflow run mirror-artifacts-gsm.yml \
  --repo "kushin77/self-hosted-runner" \
  -f source_bucket=test-source \
  -f dest_bucket=test-dest
```

### Test 3: Verify Credentials in Flow

Check workflow logs for:
- ✅ "Successfully fetched AWS credentials from GSM"
- ✅ "AWS credentials validated (STS accessible)"
- ✅ No GitHub secrets referenced in logs

---

## Rollback Plan

If issues occur, you have options:

### Option 1: Fallback to GitHub Secrets Temporarily

The sync-gsm-aws-to-github.yml workflow syncs credentials to GitHub as fallback:

```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}  # Fallback
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### Option 2: Update GSM Secrets

If AWS credentials need to change:

```bash
echo "$NEW_KEY" | gcloud secrets versions add terraform-aws-prod \
  --data-file=- --project="gcp-eiq"
```

All workflows automatically use new credentials on next run.

### Option 3: Disable Workflow

```bash
gh workflow disable mirror-artifacts-gsm.yml \
  --repo "kushin77/self-hosted-runner"
```

---

## Troubleshooting

### Workflow fails: "Unable to fetch AWS credentials"

**Check:**
1. Are GitHub secrets set?
   ```bash
   gh secret list --repo "kushin77/self-hosted-runner" | grep GCP_
   ```

2. Do GSM secrets exist?
   ```bash
   gcloud secrets list --project="gcp-eiq" | grep terraform-aws
   ```

3. Is service account properly bound?
   ```bash
   gcloud iam service-accounts get-iam-policy \
     "github-actions-terraform@gcp-eiq.iam.gserviceaccount.com" \
     --project="gcp-eiq"
   ```

### AWS API calls fail: "Invalid credentials"

**Check:**
1. Are credentials being masked in logs?
   - Should see `***` for sensitive values

2. Test with simple command:
   ```bash
   aws sts get-caller-identity --region "$AWS_REGION"
   ```

### Workflow runs too slow

**Note:** OIDC authentication adds ~10 seconds overhead (normal)

```
- Fetch OIDC token: ~2 seconds
- Authenticate to GCP: ~3 seconds
- Fetch from GSM: ~3 seconds
- Total: ~8 seconds
```

---

## Monitoring & Maintenance

### Weekly: Review Access Logs

```bash
gcloud logging read \
  "resource.type=secretmanager.googleapis.com AND 
   protoPayload.methodName=google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion" \
  --limit=100 --project="gcp-eiq"
```

### Monthly: Test Credential Fetch

```bash
gh workflow run fetch-aws-creds-from-gsm.yml \
  --repo "kushin77/self-hosted-runner"
```

### Quarterly: Update Documentation

- Update this guide if procedures change
- Document any custom integration patterns

---

## Migration Checklist

- ☐ Create fetch-aws-creds-from-gsm.yml workflow
- ☐ Set GCP secrets in GitHub (WIP, SA email, Project ID)
- ☐ Verify GSM secrets exist (prod, secret, region)
- ☐ Update first workflow (mirror-artifacts or elasticache)
- ☐ Test workflow execution
- ☐ Verify credentials are used correctly
- ☐ Review logs for success message
- ☐ Update related documentation
- ☐ Migrate remaining workflows (one per week)
- ☐ Monitor for 2 weeks
- ☐ Remove old GitHub secrets (optional)

---

## Summary

✅ **Migration Pattern:**
1. Add fetch-aws-creds-from-gsm.yml job
2. Add needs: [fetch-aws-creds] dependency
3. Replace GitHub secrets with fetched outputs
4. Test and verify

✅ **Benefits:**
- Centralized credential management (GSM)
- Ephemeral credentials (OIDC)
- No credentials in GitHub
- Automatic rotation via GSM update
- Comprehensive audit trail

✅ **Timeline:**
- Per-workflow: ~5 minutes to integrate
- Testing: ~2 minutes
- Total migration for 10 workflows: ~1 hour

---

**Next:** Execute Step-by-Step Migration section to update your workflows
