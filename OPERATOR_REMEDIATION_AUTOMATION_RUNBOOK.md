# 🔧 Operator Remediation & Automation Runbook

**Last Updated**: March 7, 2026  
**Status**: Fully Hands-Off Automation — Awaiting operator provisioning to unlock apply workflows

---

## 📌 Overview

This repository's CI/CD automation is **fully hands-off and idempotent**—all workflows are self-sustaining and auto-healing. However, three key credential/identity configurations must be provisioned by operators to enable the final phase: **Terraform auto-apply via AWS OIDC and dynamic secret fetching via GCP Workload Identity**.

**Current State**:
- ✅ All workflows parse correctly (no YAML/expression errors)
- ✅ Dry-run paths produce portable plan artifacts (JSON + binary)
- ✅ Approval gates and safety checks in place
- ⏳ **Blocked**: GSM/GCP Workload Identity & AWS OIDC role provisioning

---

## 🎯 Phase 1: Enable GCP Workload Identity for GSM Secret Fetch

### Symptoms
- `fetch-aws-creds-from-gsm.yml` fails with: `HTTP 404: [no body]` from `generateAccessToken` API
- `system-status-aggregator.yml` reports: GCP Workload Identity = ❌ Not configured
- Issue #1309: "Terraform auto-apply blocked by GSM fetch failure"

### Prerequisites
- GCP project ID (from repo secret `GCP_PROJECT_ID`)
- GCP service account email (from repo secret `GCP_SERVICE_ACCOUNT_EMAIL`)
- Workload Identity Provider resource ID (from repo secret `GCP_WORKLOAD_IDENTITY_PROVIDER`)

### Steps to Remediate

#### 1.1 Verify GCP Service Account Exists
```bash
gcloud iam service-accounts list \
  --project=${GCP_PROJECT_ID} \
  --filter="email:${GCP_SERVICE_ACCOUNT_EMAIL}"
```
**Expected**: Service account is listed, status = ENABLED.

**If missing**, create it:
```bash
gcloud iam service-accounts create github-automation \
  --project=${GCP_PROJECT_ID} \
  --display-name="GitHub Actions Automation"
export GCP_SERVICE_ACCOUNT_EMAIL="github-automation@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
# Store in repo secret: GCP_SERVICE_ACCOUNT_EMAIL
```

#### 1.2 Verify Workload Identity Provider Exists
```bash
gcloud iam workload-identity-pools providers list \
  --project=${GCP_PROJECT_ID} \
  --location=global
```
**Expected**: Provider resource matches the ID in `GCP_WORKLOAD_IDENTITY_PROVIDER` secret.

**If missing**, create it:
```bash
POOL_ID="github-pool"
PROVIDER_ID="github-provider"

# Create the pool
gcloud iam workload-identity-pools create ${POOL_ID} \
  --project=${GCP_PROJECT_ID} \
  --location=global \
  --display-name="GitHub Actions"

# Create the provider
gcloud iam workload-identity-pools providers create-oidc ${PROVIDER_ID} \
  --project=${GCP_PROJECT_ID} \
  --location=global \
  --workload-identity-pool=${POOL_ID} \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository"

# Get the full provider resource ID
gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} \
  --project=${GCP_PROJECT_ID} \
  --location=global \
  --workload-identity-pool=${POOL_ID} \
  --format="value(name)"
# Output format: projects/{PROJECT_ID}/locations/global/workloadIdentityPools/{POOL_ID}/providers/{PROVIDER_ID}
# Store in repo secret: GCP_WORKLOAD_IDENTITY_PROVIDER
```

#### 1.3 Configure Service Account → Workload Identity Binding
```bash
POOL_ID="github-pool"
PROVIDER_ID="github-provider"
REPO_OWNER="akushnir"
REPO_NAME="self-hosted-runner"

gcloud iam service-accounts add-iam-policy-binding ${GCP_SERVICE_ACCOUNT_EMAIL} \
  --project=${GCP_PROJECT_ID} \
  --role=roles/iam.workloadIdentityUser \
  --principal="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO_OWNER}/${REPO_NAME}"
```

#### 1.4 Enable IAM Credentials API (required for `generateAccessToken`)
```bash
gcloud services enable iamcredentials.googleapis.com \
  --project=${GCP_PROJECT_ID}
```

#### 1.5 Grant Service Account Permissions to Fetch Secrets from GSM
```bash
gcloud secrets list --project=${GCP_PROJECT_ID}
# For each secret (e.g., aws_access_key_id, aws_secret_access_key):
gcloud secrets add-iam-policy-binding aws_access_key_id \
  --project=${GCP_PROJECT_ID} \
  --member=serviceAccount:${GCP_SERVICE_ACCOUNT_EMAIL} \
  --role=roles/secretmanager.secretAccessor
```

#### 1.6 Verify Configuration
```bash
# Test Workload Identity exchange
export OIDC_TOKEN=$(curl -H "Authorization: Bearer ${CI_JOB_TOKEN}" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=//iam.googleapis.com/projects/${GCP_PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}" \
  -H "Metadata-Flavor: Google")

# Or via GitHub (in a workflow):
# The token should be available from GITHUB_TOKEN in a workflow

# Test service account can generate access token
gcloud iam service-accounts create-oauth2-token ${GCP_SERVICE_ACCOUNT_EMAIL} \
  --project=${GCP_PROJECT_ID}
```

**Expected Result**: No token generation errors; IAM Credentials API returns a valid access token.

---

## 🎯 Phase 2: Enable AWS OIDC Role for Terraform Auto-Apply

### Symptoms
- `terraform-auto-apply.yml` skips apply phase ("No AWS credentials")
- `system-status-aggregator.yml` reports: AWS (OIDC/Static) = ❌ Not configured
- Issue #1346: "Terraform OIDC role provisioning blocked"

### Prerequisites
- AWS Account ID
- AWS IAM role name (suggested: `github-automation-oidc`)
- GitHub Actions OIDC provider configured in AWS

### Steps to Remediate

#### 2.1 Create GitHub Actions OIDC Provider in AWS

```bash
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"

# Check if OIDC provider already exists
aws iam list-open-id-connect-providers --region ${AWS_REGION}

# If not, create it
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --region ${AWS_REGION}
```

**Note**: The thumbprint `6938fd4d98bab03faadb97b34396831e3780aea1` is GitHub's OIDC thumbprint (verify at https://github.blog/changelog/2021-04-21-github-actions-oidc-provider-for-aws/).

#### 2.2 Create IAM Role for GitHub Actions with Trust Policy

```bash
export AWS_ACCOUNT_ID="123456789012"
export REPO_OWNER="akushnir"
export REPO_NAME="self-hosted-runner"

cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:REPO_OWNER/REPO_NAME:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

# Replace placeholders
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" /tmp/trust-policy.json
sed -i "s/REPO_OWNER/${REPO_OWNER}/g" /tmp/trust-policy.json
sed -i "s/REPO_NAME/${REPO_NAME}/g" /tmp/trust-policy.json

# Create role
aws iam create-role \
  --role-name github-automation-oidc \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --region ${AWS_REGION}

# Capture the role ARN
export AWS_OIDC_ROLE_ARN=$(aws iam get-role --role-name github-automation-oidc --query 'Role.Arn' --output text --region ${AWS_REGION})
echo "AWS_OIDC_ROLE_ARN=${AWS_OIDC_ROLE_ARN}"
# Store in repo secret: AWS_OIDC_ROLE_ARN
```

#### 2.3 Attach Permissions to the Role

```bash
# For Terraform state management (S3 + DynamoDB)
aws iam put-role-policy \
  --role-name github-automation-oidc \
  --policy-name terraform-state \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource": [
          "arn:aws:s3:::my-terraform-state-bucket",
          "arn:aws:s3:::my-terraform-state-bucket/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ],
        "Resource": "arn:aws:dynamodb:*:ACCOUNT_ID:table/terraform-locks"
      }
    ]
  }'

# For ElastiCache resources
aws iam put-role-policy \
  --role-name github-automation-oidc \
  --policy-name elasticache-manage \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "elasticache:*"
        ],
        "Resource": "*"
      }
    ]
  }'

# For VPC resources (if needed for ElastiCache)
aws iam attach-role-policy \
  --role-name github-automation-oidc \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess

# List attached policies to verify
aws iam list-role-policies --role-name github-automation-oidc --region ${AWS_REGION}
```

#### 2.4 Set Repository Secrets

```bash
# Set the AWS OIDC role ARN (from step 2.2)
gh secret set AWS_OIDC_ROLE_ARN --body "${AWS_OIDC_ROLE_ARN}" \
  --repo ${REPO_OWNER}/${REPO_NAME}

# Enable OIDC mode (if not already enabled)
gh secret set USE_OIDC --body "true" \
  --repo ${REPO_OWNER}/${REPO_NAME}
```

#### 2.5 Verify Configuration

```bash
# Check role exists and has correct trust policy
aws iam get-role --role-name github-automation-oidc --region ${AWS_REGION}

# Check policies are attached
aws iam list-role-policies --role-name github-automation-oidc --region ${AWS_REGION}

# Verify Terraform state bucket is accessible
aws s3 ls s3://my-terraform-state-bucket --region ${AWS_REGION}
```

---

## 🚀 Phase 3: Testing & Validation

### Step 1: Verify System Status

The `system-status-aggregator` will automatically detect and report credential availability every 15 minutes.

```bash
# Manually trigger status aggregator
gh workflow run system-status-aggregator.yml \
  --repo ${REPO_OWNER}/${REPO_NAME}

# Check the report posted to issue #1064
gh issue view 1064 --repo ${REPO_OWNER}/${REPO_NAME} --comments | head -50
```

**Expected Output**:
- GCP Workload Identity: ✅ Configured
- AWS (OIDC/Static): ✅ Configured

### Step 2: Test GSM Fetch Workflow

```bash
gh workflow run fetch-aws-creds-from-gsm.yml \
  --repo ${REPO_OWNER}/${REPO_NAME}

# Wait for run to complete
sleep 30

# Check outputs
gh run list --repo ${REPO_OWNER}/${REPO_NAME} \
  --workflow fetch-aws-creds-from-gsm.yml \
  --limit 1 \
  --json conclusion,status
```

**Expected**: Status = completed, Conclusion = success

### Step 3: Test Terraform Auto-Apply (Dry-Run First)

```bash
# Dispatch with dry-run (default behavior)
gh workflow run terraform-auto-apply.yml \
  --repo ${REPO_OWNER}/${REPO_NAME}

# Check run logs
sleep 30
gh run list --repo ${REPO_OWNER}/${REPO_NAME} \
  --workflow terraform-auto-apply.yml \
  --limit 1 \
  --json conclusion,number

# View plan artifacts
gh run download RUN_ID --repo ${REPO_OWNER}/${REPO_NAME}
```

**Expected**: 
- Job "Terraform Plan" creates artifact `terraform-plan-<run_id>`
- Plan can be reviewed as JSON without local Terraform version matching

### Step 4: Test ElastiCache Safe Apply (Dry-Run)

```bash
# Dispatch with default dry-run
gh workflow run elasticache-apply-safe.yml \
  --repo ${REPO_OWNER}/${REPO_NAME}

# Check outputs
sleep 30
gh run download RUN_ID --repo ${REPO_OWNER}/${REPO_NAME}
ls -lah elastiCache-plan-*
```

**Expected**: 
- Artifact `elastiCache-plan-<run_id>` contains `elastiCache-dryrun.tfplan` + `elastiCache-dryrun.json`
- JSON is renderable without Terraform version matching

### Step 5: Proceed to Apply (Optional Manual Gate)

Once dry-runs pass and plans are reviewed:

```bash
# Terraform auto-apply with full credentials
gh workflow run terraform-auto-apply.yml \
  --repo ${REPO_OWNER}/${REPO_NAME}
# (applies automatically if credentials are present and event is push/dispatch)

# ElastiCache with explicit apply flag
gh workflow run elasticache-apply-safe.yml \
  -f apply=true \
  --repo ${REPO_OWNER}/${REPO_NAME}
```

---

## 🔄 Continuous Operation

Once provisioning is complete, the automation is **fully hands-off**:

### Scheduled Automation
| Automation | Schedule | Purpose |
|-----------|----------|---------|
| System Status Aggregator | Every 15 min | Report overall health |
| Terraform Auto-Apply | On push to `main` (terraform/* paths) | Auto-apply infra changes |
| ElastiCache Apply | On push to `terraform/elasticache-params.tfvars` | Auto-apply cache updates |
| Secret Rotation | Daily 02:00 UTC | Rotate GSM/GitHub secrets |
| Self-Healing | Every 5 min | Auto-recover from failures |
| DR Testing | Daily + Weekly | Disaster recovery validation |

### Key Workflows

**terraform-auto-apply.yml**:
- Triggers on: Push to `terraform/**` or manual dispatch
- Behavior: Detects credentials → Plan → Apply (idempotent)
- Approval gate: Uploads plan artifacts for review before apply
- Failure recovery: Posts to issue #1286, #1309 for tracking

**elasticache-apply-safe.yml**:
- Triggers on: Push to `terraform/elasticache-params.tfvars` or manual dispatch
- Behavior: Validates params → Plan → (optional) Apply
- Approval gate: Requires explicit `apply=true` for on-push applies
- Safety: Backend-free dry-run if credentials unavailable

**system-status-aggregator.yml**:
- Triggers every 15 min
- Collects status from all workflows
- Posts report to issue #1064
- Auto-creates/closes "missing-secrets" issues

---

## 🆘 Troubleshooting

### GSM Fetch Returns 404
**Root Cause**: IAM Credentials API not enabled or service account lacks permissions.

**Fix**:
```bash
# Re-enable API
gcloud services enable iamcredentials.googleapis.com --project=${GCP_PROJECT_ID}

# Verify service account has Workload Identity User role
gcloud iam service-accounts get-iam-policy ${GCP_SERVICE_ACCOUNT_EMAIL} \
  --project=${GCP_PROJECT_ID}
```

### Terraform Credentials Not Detected
**Root Cause**: AWS_OIDC_ROLE_ARN or USE_OIDC secret not set.

**Fix**:
```bash
gh secret list --repo ${REPO_OWNER}/${REPO_NAME} | grep AWS_OIDC_ROLE_ARN

# If missing, set it:
gh secret set AWS_OIDC_ROLE_ARN --body "<ARN>" \
  --repo ${REPO_OWNER}/${REPO_NAME}

gh secret set USE_OIDC --body "true" \
  --repo ${REPO_OWNER}/${REPO_NAME}
```

### Terraform Plan Artifact Not Found
**Root Cause**: Credentials present but plan job failed to render JSON.

**Fix**:
- Check workflow logs for terraform errors
- Ensure Terraform version matches (1.4.0 in workflows)
- Verify terraform directory contains valid *.tf files

### Manual Testing
```bash
# Test GCP auth locally (requires gcloud CLI)
gcloud auth application-default login

# Test AWS OIDC locally (requires aws CLI + GITHUB_TOKEN)
export GITHUB_TOKEN=$(gh auth token)
TOKEN=$(curl -H "Authorization: bearer ${GITHUB_TOKEN}" \
  "https://token.actions.githubusercontent.com/?audience=sts.amazonaws.com")
  
# Exchange GitHub token for AWS credentials
aws sts assume-role-with-web-identity \
  --role-arn ${AWS_OIDC_ROLE_ARN} \
  --role-session-name test \
  --web-identity-token ${TOKEN}
```

---

## ✅ Completion Checklist

After completing all remediation steps, verify:

- [ ] GCP Project ID, Service Account, WI Provider configured in repo secrets
- [ ] GCP IAM Credentials API enabled
- [ ] Service account has `roles/secretmanager.secretAccessor`
- [ ] GitHub OIDC provider created in AWS
- [ ] AWS OIDC role created with trust policy
- [ ] AWS OIDC role ARN stored in repo secret `AWS_OIDC_ROLE_ARN`
- [ ] USE_OIDC secret set to `true`
- [ ] `system-status-aggregator` shows ✅ for GCP and AWS
- [ ] `fetch-aws-creds-from-gsm.yml` completes without 404
- [ ] `terraform-auto-apply.yml` generates plan artifacts (JSON + binary)
- [ ] ElastiCache workflow generates portable dry-run artifacts
- [ ] All issues #1309, #1324, #1346 report success in comments

---

## 📞 Support

For issues during provisioning:
- Check workflow logs: `gh run view RUN_ID --log`
- Review system status report: Issue #1064
- Post investigation comments on relevant issues (#1309, #1346, #1324)

**Automation Status**: Every 15 minutes, `system-status-aggregator.yml` will update issue #1064 with current health. Remediation is complete when all statuses turn ✅.
