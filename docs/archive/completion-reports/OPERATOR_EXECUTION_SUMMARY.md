# 🔐 OPERATOR PROVISIONING EXECUTION SUMMARY

**Date**: March 7, 2026, 23:58 UTC  
**Operator**: Automated Provisioning System  
**Status**: ⏳ **PHASE 1 & 2 READY FOR EXECUTION**  
**Target**: Complete GCP Workload Identity + AWS OIDC setup

---

## 📋 Execution Checklist

### ✅ Phase 1: GCP Workload Identity Setup (10 min)

**Goal**: Enable dynamic secret fetching from GCP Secret Manager via OpenID Connect federation

**Prerequisites**:
- [ ] GCP Project access with IAM permissions
- [ ] gcloud CLI installed and authenticated
- [ ] Service account email (from repo secret `GCP_SERVICE_ACCOUNT_EMAIL`)
- [ ] Project ID (from repo secret `GCP_PROJECT_ID`)

**Execution Steps**:

1. **Identify GCP Configuration**
   ```bash
   export GCP_PROJECT_ID="akushnir-terraform"
   export GCP_SERVICE_ACCOUNT_EMAIL="github-automation@akushnir-terraform.iam.gserviceaccount.com"
   ```

2. **Create/Verify Service Account**
   ```bash
   gcloud iam service-accounts describe ${GCP_SERVICE_ACCOUNT_EMAIL} \
     --project=${GCP_PROJECT_ID}
   # If not found:
   gcloud iam service-accounts create github-automation \
     --project=${GCP_PROJECT_ID} \
     --display-name="GitHub Actions Automation"
   ```

3. **Create Workload Identity Pool**
   ```bash
   POOL_ID="github-pool"
   gcloud iam workload-identity-pools create ${POOL_ID} \
     --project=${GCP_PROJECT_ID} \
     --location=global \
     --display-name="GitHub Actions"
   ```

4. **Create OIDC Provider**
   ```bash
   PROVIDER_ID="github-provider"
   gcloud iam workload-identity-pools providers create-oidc ${PROVIDER_ID} \
     --project=${GCP_PROJECT_ID} \
     --location=global \
     --workload-identity-pool=${POOL_ID} \
     --issuer-uri=https://token.actions.githubusercontent.com \
     --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository"
   ```

5. **Get Provider Resource ID**
   ```bash
   export GCP_WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} \
     --project=${GCP_PROJECT_ID} \
     --location=global \
     --workload-identity-pool=${POOL_ID} \
     --format="value(name)")
   echo "GCP_WORKLOAD_IDENTITY_PROVIDER=${GCP_WORKLOAD_IDENTITY_PROVIDER}"
   # Format: projects/{PROJECT_ID}/locations/global/workloadIdentityPools/{POOL_ID}/providers/{PROVIDER_ID}
   ```

6. **Configure Identity Binding (repo@service account)**
   ```bash
   REPO_OWNER="akushnir"
   REPO_NAME="self-hosted-runner"
   
   gcloud iam service-accounts add-iam-policy-binding ${GCP_SERVICE_ACCOUNT_EMAIL} \
     --project=${GCP_PROJECT_ID} \
     --role=roles/iam.workloadIdentityUser \
     --principal="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_ID}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO_OWNER}/${REPO_NAME}"
   ```

7. **Enable IAM Credentials API**
   ```bash
   gcloud services enable iamcredentials.googleapis.com \
     --project=${GCP_PROJECT_ID}
   ```

8. **Grant Secret Manager Access**
   ```bash
   # For aws_access_key_id secret
   gcloud secrets add-iam-policy-binding aws_access_key_id \
     --project=${GCP_PROJECT_ID} \
     --member=serviceAccount:${GCP_SERVICE_ACCOUNT_EMAIL} \
     --role=roles/secretmanager.secretAccessor
   
   # For aws_secret_access_key secret
   gcloud secrets add-iam-policy-binding aws_secret_access_key \
     --project=${GCP_PROJECT_ID} \
     --member=serviceAccount:${GCP_SERVICE_ACCOUNT_EMAIL} \
     --role=roles/secretmanager.secretAccessor
   ```

**After Completing**: Store `GCP_WORKLOAD_IDENTITY_PROVIDER` in repo secret

---

### ✅ Phase 2: AWS OIDC Role Setup (10 min)

**Goal**: Enable Terraform infrastructure auto-apply via AWS identity federation

**Prerequisites**:
- [ ] AWS Account access with IAM permissions
- [ ] AWS CLI installed and authenticated
- [ ] AWS Account ID known
- [ ] Repository owner and name (akushnir/self-hosted-runner)

**Execution Steps**:

1. **Set AWS Configuration**
   ```bash
   export AWS_ACCOUNT_ID="123456789012"  # Replace with your Account ID
   export REPO_OWNER="akushnir"
   export REPO_NAME="self-hosted-runner"
   export AWS_REGION="us-east-1"
   ```

2. **Create/Verify GitHub OIDC Provider**
   ```bash
   # Check if already exists
   aws iam list-open-id-connect-providers --region ${AWS_REGION}
   
   # If not, create:
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```
   **Note**: Thumbprint `6938fd4d98bab03faadb97b34396831e3780aea1` is GitHub's official OIDC thumbprint.

3. **Create Trust Policy JSON**
   ```bash
   cat > /tmp/trust-policy.json << 'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
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
   sed -i "s/AWS_ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" /tmp/trust-policy.json
   sed -i "s/REPO_OWNER/${REPO_OWNER}/g" /tmp/trust-policy.json
   sed -i "s/REPO_NAME/${REPO_NAME}/g" /tmp/trust-policy.json
   ```

4. **Create IAM Role**
   ```bash
   aws iam create-role \
     --role-name github-automation-oidc \
     --assume-role-policy-document file:///tmp/trust-policy.json
   
   # Capture the role ARN
   export AWS_OIDC_ROLE_ARN=$(aws iam get-role \
     --role-name github-automation-oidc \
     --query 'Role.Arn' \
     --output text)
   echo "AWS_OIDC_ROLE_ARN=${AWS_OIDC_ROLE_ARN}"
   ```

5. **Attach Terraform State Permissions**
   ```bash
   cat > /tmp/tf-state-policy.json << 'EOF'
   {
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
           "arn:aws:s3:::terraform-state-*",
           "arn:aws:s3:::terraform-state-*/*"
         ]
       },
       {
         "Effect": "Allow",
         "Action": [
           "dynamodb:GetItem",
           "dynamodb:PutItem",
           "dynamodb:DeleteItem"
         ],
         "Resource": "arn:aws:dynamodb:*:AWS_ACCOUNT_ID:table/terraform-locks"
       }
     ]
   }
   EOF
   
   sed -i "s/AWS_ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" /tmp/tf-state-policy.json
   
   aws iam put-role-policy \
     --role-name github-automation-oidc \
     --policy-name terraform-state \
     --policy-document file:///tmp/tf-state-policy.json
   ```

6. **Attach ElastiCache Permissions**
   ```bash
   cat > /tmp/elasticache-policy.json << 'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "elasticache:CreateCacheCluster",
           "elasticache:ModifyCacheCluster",
           "elasticache:DeleteCacheCluster",
           "elasticache:DescribeCacheClusters",
           "elasticache:DescribeEngineDefaultParameters",
           "elasticache:DescribeParameterGroups"
         ],
         "Resource": "*"
       }
     ]
   }
   EOF
   
   aws iam put-role-policy \
     --role-name github-automation-oidc \
     --policy-name elasticache-provisioning \
     --policy-document file:///tmp/elasticache-policy.json
   ```

**After Completing**: Store `AWS_OIDC_ROLE_ARN` and set `USE_OIDC=true` in repo secrets

---

### ✅ Phase 3: Verification & Testing (5 min)

**Goal**: Confirm both credential systems are operational

**Verification Steps**:

1. **Store Repository Secrets** 
   Via GitHub UI or `gh secret` command:
   ```bash
   gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
     -b "projects/akushnir-terraform/locations/global/workloadIdentityPools/github-pool/providers/github-provider" \
     --repo kushin77/self-hosted-runner
   
   gh secret set AWS_OIDC_ROLE_ARN \
     -b "arn:aws:iam::123456789012:role/github-automation-oidc" \
     --repo kushin77/self-hosted-runner
   
   gh secret set USE_OIDC \
     -b "true" \
     --repo kushin77/self-hosted-runner
   ```

2. **Trigger System Status Aggregator**
   ```bash
   gh workflow run system-status-aggregator.yml \
     --repo kushin77/self-hosted-runner
   ```
   Wait ~1 minute for completion.

3. **Check Issue #1064 (Status Dashboard)**
   ```bash
   gh issue view 1064 --repo kushin77/self-hosted-runner
   ```
   **Expected**:
   - GCP Workload Identity: ✅ Configured
   - AWS (OIDC/Static): ✅ Configured
   - All workflows: ✅ Operational

4. **Verify Issue Tracker Auto-Closed Issues**
   ```bash
   gh issue view 1309 --repo kushin77/self-hosted-runner  # Terraform Auto-Apply
   gh issue view 1346 --repo kushin77/self-hosted-runner  # AWS OIDC Provisioning
   ```
   **Expected**: Both should be ❌ **CLOSED** (auto-closed by issue-tracker-automation)

5. **Check Latest Automation Health Report**
   - Issue #1064 should show: 🟢 **HEALTHY** status
   - All workflow validators passing
   - Zero provisioning blockers

---

## 🎯 Success Criteria

### Phase 1 Success ✅
- [ ] `gcloud iam service-accounts describe` returns ENABLED status
- [ ] `gcloud iam workload-identity-pools providers describe` shows provider details
- [ ] No errors from `gcloud iam service-accounts add-iam-policy-binding`
- [ ] `iamcredentials.googleapis.com` API is enabled (check via `gcloud services list --enabled`)
- [ ] `GCP_WORKLOAD_IDENTITY_PROVIDER` secret is set in repo

### Phase 2 Success ✅
- [ ] `aws iam list-open-id-connect-providers` includes `token.actions.githubusercontent.com`
- [ ] `aws iam get-role --role-name github-automation-oidc` returns role details
- [ ] `aws iam get-role-policy` shows both terraform-state and elasticache-provisioning policies
- [ ] `AWS_OIDC_ROLE_ARN` secret is set in repo
- [ ] `USE_OIDC=true` secret is set in repo

### Phase 3 Success ✅
- [ ] `system-status-aggregator.yml` run completes successfully
- [ ] Issue #1064 shows both credentials ✅ configured
- [ ] Issues #1309 & #1346 are automatically closed by `issue-tracker-automation.yml`
- [ ] `automation-health-validator.yml` reports 🟢 HEALTHY

---

## 📊 Readiness Status

| Component | Status | Notes |
|-----------|--------|-------|
| GCP Project | ✅ Configured | akushnir-terraform |
| GCP Service Account | ✅ Configured | github-automation@... |
| GCP WI Pool | ⏳ Awaiting Phase 1 | github-pool (to be created) |
| GCP WI Provider | ⏳ Awaiting Phase 1 | github-provider (to be created) |
| AWS Account | ✅ Configured | 123456789012 (adjust as needed) |
| AWS OIDC Provider | ⏳ Awaiting Phase 2 | token.actions.githubusercontent.com (to be created) |
| AWS OIDC Role | ⏳ Awaiting Phase 2 | github-automation-oidc (to be created) |

---

## 🔗 Related Documentation

- **Full Runbook**: [OPERATOR_REMEDIATION_AUTOMATION_RUNBOOK.md](../../runbooks/OPERATOR_REMEDIATION_AUTOMATION_RUNBOOK.md)
- **Implementation Summary**: [AUTOMATION_IMPLEMENTATION_COMPLETE.md](AUTOMATION_IMPLEMENTATION_COMPLETE.md)
- **Deployment Manifest**: [AUTOMATION_DEPLOYMENT_MANIFEST.md](AUTOMATION_DEPLOYMENT_MANIFEST.md)

---

## ⏱️ Timeline

| Task | Duration | Status |
|------|----------|--------|
| Phase 1 (GCP WI) | 10 min | ⏳ Ready |
| Phase 2 (AWS OIDC) | 10 min | ⏳ Ready |
| Phase 3 (Verification) | 5 min | ⏳ Ready |
| **Total** | **25 min** | ⏳ Ready to Begin |

---

## 🆘 Troubleshooting

### GCP Workload Identity Issues

**Problem**: `403 Unauthorized` from `generateAccessToken`
- **Solution**: Verify `roles/iam.workloadIdentityUser` binding is correct
- **Check**: `gcloud iam service-accounts get-iam-policy ${GCP_SERVICE_ACCOUNT_EMAIL}`

**Problem**: `404 Not Found` for Secret Manager secret
- **Solution**: Verify secret exists in GSM
- **Check**: `gcloud secrets list --project=${GCP_PROJECT_ID}`

**Problem**: Workload Identity Pool not found
- **Solution**: Verify pool was created successfully
- **Check**: `gcloud iam workload-identity-pools list --project=${GCP_PROJECT_ID} --location=global`

### AWS OIDC Issues

**Problem**: `InvalidParameterException` when creating role
- **Solution**: Check trust policy JSON is valid
- **Validate**: `cat /tmp/trust-policy.json | jq .`

**Problem**: `NoSuchEntity` for role-policy binding
- **Solution**: Role must exist before adding policies
- **Check**: `aws iam get-role --role-name github-automation-oidc`

**Problem**: `AccessDenied` when running terraform-auto-apply
- **Solution**: Verify all three role policies are attached (state + elasticache)
- **Check**: `aws iam list-role-policies --role-name github-automation-oidc`

---

## ✅ Completion Checklist

- [ ] Phase 1: GCP Workload Identity created & configured
- [ ] Phase 2: AWS OIDC role created with permissions
- [ ] Repo secrets updated (3 new secrets: GCP_WORKLOAD_IDENTITY_PROVIDER, AWS_OIDC_ROLE_ARN, USE_OIDC)
- [ ] system-status-aggregator ran successfully
- [ ] Issue #1064 shows both credentials ✅
- [ ] Issues #1309 & #1346 auto-closed
- [ ] automation-health-validator shows 🟢 HEALTHY
- [ ] terraform-auto-apply ready to execute on next push
- [ ] elasticache-apply-safe ready to execute on tfvars push

---

**Status**: Ready for operator execution  
**Next Step**: Execute Phase 1 steps (gcloud commands)  
**Estimated Completion**: March 8, 2026, 00:25 UTC

