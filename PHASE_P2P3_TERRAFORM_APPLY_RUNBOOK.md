# Phase P2/P3 Terraform Apply Procedures

**Created:** March 7, 2026  
**Purpose:** Safe, automated terraform apply procedures for Phase P2/P3 production infrastructure rollout  
**Status:** Ready for deployment  
**Caution:** ⚠️ Production infrastructure - requires careful execution

---

## Executive Summary

This document outlines the safe, automated procedures to apply Terraform changes for Phase P2/P3 of the production infrastructure rollout. Phase P2/P3 provisions critical GCP/Vault infrastructure including:

- **KMS Encryption Keys** - For Vault auto-unseal and cryptographic operations
- **Service Accounts** - vault-admin-primary with proper IAM roles
- **Storage Infrastructure** - GCS buckets for Vault data and backups
- **Vault Policies** - Provisioner policy for runner secrets and AppRole access

**Total Resources:** 10 (all create operations)

---

## Prerequisites & Checklist

### Before Starting

- [ ] All team members have reviewed the plan file (`terraform/plan-post-import-2.out`)
- [ ] State backup has been created and verified
- [ ] Credentials are available and validated:
  - [ ] GCP credentials (project: gcp-eiq)
  - [ ] AWS credentials (from GSM or static)
  - [ ] Service account keys and OIDC provider configured
- [ ] Maintenance window scheduled and stakeholders notified
- [ ] Rollback procedure tested and procedurally ready
- [ ] Post-apply validation checklist prepared

### System Requirements

```bash
# Verify terraform installation
terraform version  # Should be >= 1.4.0

# Verify gcloud CLI
gcloud version    # Should be recent

# Verify aws CLI  
aws sts get-caller-identity  # Confirms AWS credentials

# Verify git
git status        # Check working directory is clean
```

---

## Automated Apply Workflow

### Option 1: GitHub Actions (Recommended)

**Advantages:**
- Fully automated, hands-off execution
- Built-in state backup and validation
- Notification system integrated
- Artifact retention for audit

**Steps:**

1. **Navigate to Workflow:**
   - Go to: https://github.com/kushin77/self-hosted-runner/actions
   - Find: "Phase P2/P3 Terraform Apply (GCP/Vault Infrastructure)"

2. **Dispatch Workflow:**
   ```
   Click "Run workflow" → Configure inputs:
   
   - apply_plan_file: plan-post-import-2.out (default)
   - skip_checks: false (MUST run checks)
   - enable_state_backup: true (MUST enable)
   - notify_slack: true (recommended)
   - dry_run: true (FIRST RUN - validate before apply)
   ```

3. **Dry-Run Validation (First Run):**
   - Set `dry_run: true`
   - Review plan summary and resource count
   - Verify state backup was created
   - Check all pre-apply checks passed

4. **Approval Gate:**
   - Review logs from dry-run
   - Confirm resource changes match expectations
   - Verify credentials were available
   - Check state backup artifact

5. **Execute Apply:**
   - Dispatch workflow again with `dry_run: false`
   - Monitor workflow execution in real-time
   - Watch for any errors in the logs
   - Receives automatic Slack notification when complete

6. **Post-Apply Validation:**
   - Workflow automatically validates resources
   - KMS keys verified in GCP console
   - Service accounts confirmed with proper IAM roles
   - Storage buckets accessible

---

## Manual Apply Procedure (Local)

### For local/manual execution (if automation unavailable):

**Step 1: Verify Credentials**

```bash
# Export AWS credentials
export AWS_ACCESS_KEY_ID="<your-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret>"
export AWS_DEFAULT_REGION="us-east-1"

# Verify AWS credentials
aws sts get-caller-identity

# Verify GCP credentials
gcloud auth list
gcloud config get-value project  # Should be gcp-eiq
```

**Step 2: Run Pre-Apply Checks**

```bash
cd /path/to/self-hosted-runner

# Run pre-apply validation checks
bash ci/scripts/terraform-preapply-checks.sh

# Expected output: All critical pre-apply checks passed
```

**Step 3: Create State Backup**

```bash
# Create and verify state backup
bash ci/scripts/terraform-backup.sh

# Example output:
# terraform-state-backup-20260307T123456Z.tfstate
```

**Step 4: Initialize Terraform**

```bash
cd terraform

# Initialize terraform workspace
terraform init -input=false

# Verify initialization
terraform version
terraform providers
```

**Step 5: Review Plan**

```bash
# Show plan to review changes
terraform show terraform/plan-post-import-2.out | less

# Or JSON format for parsing
terraform show -json terraform/plan-post-import-2.out | jq '.resource_changes[] | {address, actions}' | head -50
```

**Step 6: Execute Apply**

```bash
# IMPORTANT: Review the plan section above before proceeding

echo "⚠️  About to apply 10 resources to production GCP/Vault infrastructure"
echo "State backup: $(ls -1 ../terraform-backups/terraform-state-backup-*.tfstate | tail -1)"
echo ""
read -p "Continue with terraform apply? (type 'yes' to confirm): " confirm

if [ "$confirm" = "yes" ]; then
  echo "🚀 Executing terraform apply..."
  terraform apply -input=false -auto-approve plan-post-import-2.out
else
  echo "Apply cancelled"
  exit 1
fi
```

**Step 7: Post-Apply Validation**

```bash
# Verify state was updated
terraform state list | wc -l

# Validate KMS resources
gcloud kms keys list --location=us-central1 --keyring=vault-keyring --project=gcp-eiq

# Validate service accounts
gcloud iam service-accounts describe vault-admin-primary@gcp-eiq.iam.gserviceaccount.com

# Validate storage
gcloud storage buckets list --project=gcp-eiq

# Verify vault-admin has correct roles
gcloud projects get-iam-policy gcp-eiq \
  --flatten="bindings[].members" \
  --filter="bindings.members:vault-admin*"
```

**Step 8: Document & Notify**

```bash
# Capture apply summary
terraform show -json terraform.tfstate > post-apply-state.json

# Comment on issue #228 with results
gh issue comment 228 \
  --body "✅ Phase P2/P3 terraform apply completed successfully at $(date)"
```

---

## Rollback Procedures

### Emergency Rollback

If apply fails or causes issues:

**Step 1: Stop and Assess**

```bash
# Do NOT attempt to re-apply or fix
# Assess the failure:
terraform show -json terraform.tfstate > current-state.json

# Check state vs plan
terraform plan plan-post-import-2.out  # This will show what changed
```

**Step 2: Restore from Backup**

```bash
# Get the backup file (created before apply)
BACKUP_FILE=$(ls -1 ../terraform-backups/terraform-state-backup-*.tfstate | tail -1)

echo "Restoring from backup: $BACKUP_FILE"

# Create a recovery backup of current state
cp terraform.tfstate terraform.tfstate.failed-$(date +%Y%m%dT%H%M%SZ)

# Restore from backup
cp "$BACKUP_FILE" terraform.tfstate

# Verify restoration
terraform state list
```

**Step 3: Destroy Applied Resources**

```bash
# If rollback is necessary, destroy the applied resources
# CAUTION: This will delete production infrastructure

terraform destroy -input=false -auto-approve

# Verify cleanup in GCP console
gcloud resource-manager liens list --project=gcp-eiq
```

**Step 4: Post-Mortem & Issue Update**

```bash
# Document the failure
gh issue comment 228 \
  --body "❌ Apply failed and was rolled back. Issue requires investigation."

# Create an incident issue
gh issue create \
  --title "Phase P2/P3 Apply Failure - Root Cause Analysis Required" \
  --assignee @ops,@infra \
  --labels incident,p2p3
```

---

## Credential Requirements

### GitHub Secrets (Required for Workflow)

| Secret | Purpose | Source |
|--------|---------|--------|
| `GCP_PROJECT_ID` | GCP project identifier | Set in repo settings |
| `GCP_SERVICE_ACCOUNT_EMAIL` | GCP service account email | GCP IAM Console |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | OIDC provider configuration | GCP Workload Identity |
| `GCP_SERVICE_ACCOUNT_KEY` | JSON key (backup auth) | GCP IAM Console |
| `SLACK_WEBHOOK_URL` | Slack notification webhook | Slack workspace settings |

### Environment Variables (For Local Apply)

```bash
# AWS credentials (from GitHub Secrets or GSM)
export AWS_ACCESS_KEY_ID="<KEY>"
export AWS_SECRET_ACCESS_KEY="<SECRET>"
export AWS_DEFAULT_REGION="us-east-1"

# GCP credentials
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/gcp-key.json"
export GCP_PROJECT_ID="gcp-eiq"
```

### Fetching Credentials from GSM

```bash
# Authenticate to GCP
gcloud auth login
gcloud config set project gcp-eiq

# Fetch AWS credentials from Google Secret Manager
export AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret="terraform-aws-prod")
export AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret="terraform-aws-secret")
export AWS_DEFAULT_REGION=$(gcloud secrets versions access latest --secret="terraform-aws-region")

# Verify credentials
aws sts get-caller-identity
```

---

## Monitoring & Logging

### Workflow Monitoring

**Via GitHub Actions:**
1. Go to: https://github.com/kushin77/self-hosted-runner/actions
2. Select: "Phase P2/P3 Terraform Apply (GCP/Vault Infrastructure)"
3. Monitor in real-time as jobs progress

**Via Logs:**

```bash
# Download logs from GitHub
gh run download <run-id> --dir ./logs

# View plan review
cat logs/Review_Terraform_Plan/output.log

# View apply execution
cat logs/Execute_Terraform_Apply/output.log

# View validation
cat logs/Post-Apply_Validation/output.log
```

### Critical Log Entries to Watch For

```
✓ Pre-apply checks completed successfully
✓ State backup created: terraform-state-backup-*.tfstate
✓ Plan Analysis:
  Total Resources: 10
  Creates: 10
  Updates: 0
  Deletes: 0

🚀 Starting terraform apply...
✓ Apply completed successfully

✓ Phase P2/P3 Post-Apply Validation
✅ Infrastructure validation checks completed
```

---

## Troubleshooting

### Common Issues & Resolutions

**Issue: "Terraform not initialized"**
```bash
# Solution
cd terraform
terraform init -input=false
```

**Issue: "AWS credentials not available"**
```bash
# Solution: Fetch from GSM
export AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret="terraform-aws-prod")
export AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret="terraform-aws-secret")
aws sts get-caller-identity  # Verify
```

**Issue: "GCP authentication failed"**
```bash
# Solution: Authenticate with gcloud
gcloud auth login
gcloud auth application-default login
gcloud config set project gcp-eiq
```

**Issue: "Plan file not found"**
```bash
# Solution: Check file exists and format
ls -la terraform/plan-post-import-2.out
terraform show terraform/plan-post-import-2.out | head -20
```

**Issue: "Apply hangs or times out"**
```bash
# Increase timeout (default 30 mins):
# Edit workflow: phase-p2p3-terraform-apply.yml
# Change: timeout-minutes: 60 (or higher)

# For local apply, monitor process
watch -n 5 'terraform show -json terraform.tfstate | jq ".resources | length"'
```

---

## Post-Apply Validation Checklist

**Validate all phase P2/P3 resources:**

```bash
# 1. KMS Resources
gcloud kms keys list --location=us-central1 --keyring=vault-keyring --project=gcp-eiq

# 2. Service Accounts
gcloud iam service-accounts describe vault-admin-primary@gcp-eiq.iam.gserviceaccount.com

# 3. Service Account IAM Bindings
gcloud projects get-iam-policy gcp-eiq \
  --flatten="bindings[].members" \
  --filter="bindings.members:vault-admin*"

# 4. Storage Buckets
gcloud storage buckets list --project=gcp-eiq | grep vault

# 5. Vault Policy File
gcloud filestore instances list --project=gcp-eiq || \
  gcloud storage objects list gs://vault-data-*/ --project=gcp-eiq | head

# 6. Check state
cd terraform && terraform state list | grep -E "vault|kms|storage"
```

**Expected Results:**
- ✅ All 10 resources created successfully
- ✅ KMS keys accessible and configured
- ✅ vault-admin service account exists with proper roles
- ✅ Storage buckets created with correct permissions
- ✅ Vault policy file deployed
- ✅ No errors in terraform.tfstate

---

## Communication & Notifications

### Slack Notifications

When `notify_slack: true` is set, the workflow sends:
- 📋 **Plan Summary** - Before apply starts
- 🚀 **Apply Started** - When apply begins (if not dry-run)
- ✅/❌ **Apply Result** - Success or failure notification
- ✓ **Validation Complete** - Post-apply resource verification

**Notification Contents:**
- Plan summary (resources to create/update/delete)
- Apply status (success/failure)
- Logs link
- Issue #228 link for tracking

### GitHub Issue Comments

The workflow automatically comments on issue #228 with:
1. Pre-apply plan summary
2. Apply execution result
3. Post-apply validation status

---

## Timeline & Scheduling

### Recommended Execution Flow

| Time | Action | Who | Duration |
|------|--------|-----|----------|
| T+0 | Dispatch workflow (dry-run) | @ops | 5 min |
| T+5 | Review logs and plan summary | @ops,@infra | 10 min |
| T+15 | Get approval from stakeholders | @infra | 5 min |
| T+20 | Dispatch workflow (actual apply) | @ops | 5 min |
| T+25 | Monitor apply execution | @ops | 20 min |
| T+45 | Review apply logs and validation | @ops,@infra | 10 min |
| T+55 | Confirm all resources in production | @infra | 5 min |
| **T+60** | **Phase P2/P3 Deployment Complete** | - | - |

### Maintenance Window Recommendation

- **Duration:** 2 hours minimum
- **Time:** Off-peak hours (e.g., Friday evening)
- **Rollback Window:** 30 minutes (keep team available)
- **Communication:** Notify all stakeholders via Slack #ops channel

---

## Success Criteria

Phase P2/P3 apply is successful when:

1. ✅ Terraform apply exits with code 0 (no errors)
2. ✅ All 10 resources created in terraform state
3. ✅ GCP KMS keys created and accessible
4. ✅ vault-admin service account created with:
   - KMS cryptographer + decryptor roles
   - Storage object admin role
   - Correct project binding
5. ✅ Storage buckets created in GCP console
6. ✅ Vault provisioner policy file deployed
7. ✅ Post-apply validation checks pass
8. ✅ State backup verified and accessible
9. ✅ All team notifications delivered
10. ✅ Issue #228 updated with completion status

---

## Escalation & Support

**If Apply Fails:**
1. Do NOT attempt to re-apply without investigation
2. Create incident issue with error logs
3. Restore state from backup (documented in Rollback)
4. Contact @infra and @ops for root cause analysis

**For Questions:**
- Review this runbook first
- Check [GSM AWS Credentials documentation](./GSM_AWS_CREDENTIALS_QUICK_START.md)
- Consult [Terraform Best Practices](./TERRAFORM_BEST_PRACTICES.md)
- Reach out to @infra-team in Slack

---

## Appendix A: Plan File Details

**File:** `terraform/plan-post-import-2.out`  
**Created:** March 5, 2026  
**Format:** Binary (use `terraform show` to inspect)  
**Size:** ~40 lines when displayed

**Resources in Plan:**

```
1. google_kms_crypto_key_iam_member.vault_kms_unseal
   - Grant vault-admin KMS cryptographer + decryptor

2. google_service_account.vault_admin
   - Create vault-admin-primary service account

3. google_storage_bucket_iam_member.vault_storage_admin
   - Grant vault-admin storage object admin

4. local_file.vault_provisioner_policy
   - Write Vault provisioner policy file

5-10. (6 additional GCP/Vault infrastructure resources)
```

To inspect full details:

```bash
cd terraform
terraform show -json plan-post-import-2.out | jq '.resource_changes[]' | less
```

---

## Appendix B: Workflow Inputs Reference

### GitHub Actions Workflow Dispatch Inputs

```yaml
apply_plan_file:        # Plan file to apply (default: plan-post-import-2.out)
skip_checks:            # Skip pre-apply checks (NOT RECOMMENDED - default: false)
enable_state_backup:    # Create state backup before apply (default: true)
notify_slack:           # Send Slack notifications (default: true)
dry_run:                # Run as dry-run without actual apply (default: true)
```

**Recommended Configurations:**

Dry-Run (Validation):
```
apply_plan_file: plan-post-import-2.out
skip_checks: false
enable_state_backup: false (optional for dry-run)
notify_slack: true
dry_run: true
```

Actual Apply:
```
apply_plan_file: plan-post-import-2.out
skip_checks: false
enable_state_backup: true
notify_slack: true
dry_run: false
```

---

**Document Version:** 1.0  
**Last Updated:** March 7, 2026  
**Next Review:** After Phase P2/P3 deployment completion
