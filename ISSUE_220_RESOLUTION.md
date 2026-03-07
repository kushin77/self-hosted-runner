# Issue #220 - Resolution: Terraform Phase 2 Final Plan/Apply Workflow

**Status:** ✅ **READY FOR OPERATOR EXECUTION**

**Issue:** https://github.com/kushin77/self-hosted-runner/issues/220  
**Title:** Run final `terraform plan`/`apply` for Phase 2  
**Completed:** March 7, 2026

## Summary

Issue #220 requested a secure, auditable workflow to run the final Terraform plan and apply for Phase 2, which includes:
- GCP Vault resource imports into Terraform state
- Root-level module validation with required sensitive inputs

### What Was Created

#### 1. GitHub Actions Workflow
**File:** `.github/workflows/terraform-phase2-final-plan-apply.yml`

**Features:**
- ✅ Manual dispatch with optional inputs (`auto_apply`, `varfile_source`)
- ✅ Secure credential handling via GSM Workload Identity
- ✅ AWS credential retrieval from Google Secret Manager
- ✅ GCP credential configuration for GCS Terraform backend
- ✅ Full repository Terraform plan with saved plan file
- ✅ Plan artifact upload to GitHub Actions and MinIO
- ✅ Optional automatic apply with GitHub Environments approval
- ✅ Comprehensive logging and error handling
- ✅ Concurrency controls to prevent simultaneous runs

**Jobs:**
1. `setup` — Validates workflow inputs
2. `fetch-aws-creds` — Retrieves AWS credentials from GSM (reusable workflow)
3. `terraform-plan` — Runs full repository plan
4. `terraform-apply` — Conditionally applies changes (requires approval)
5. `notify-on-completion` — Notifies operator of completion

#### 2. Operator Execution Guide
**File:** `TERRAFORM_PHASE2_PLAN_APPLY_GUIDE.md`

**Contents:**
- Complete overview and prerequisites
- Step-by-step operator checklist
- Required GitHub Secrets configuration
- `terraform.tfvars` template
- Troubleshooting guide
- Security best practices
- Rollback procedures

## How to Use

### For Operators

1. **Configure GitHub Secrets** (Settings → Secrets and Variables → Actions):
   ```
   TERRAFORM_VPC_ID          = "vpc-abc123"
   TERRAFORM_SUBNET_IDS      = ["subnet-1", "subnet-2"]
   TERRAFORM_RUNNER_TOKEN    = "GHR_xxx..."
   AWS_REGION                = "us-east-1"
   GCP_PROJECT_ID            = "gcp-eiq"
   GCP_SA_KEY                = <service-account-json>
   ```

2. **Trigger the workflow**:
   - GitHub Actions → "Terraform Phase 2: Final Plan/Apply" → "Run workflow"
   - Leave `auto_apply` as `false` initially
   - Select `varfile_source` (default: `github-secrets`)

3. **Review the plan**:
   - Download artifacts: "terraform-phase2-plan", "terraform-phase2-summary"
   - Verify changes are intentional
   - Check MinIO upload for audit trail

4. **Apply changes** (if approved):
   - Rerun workflow with `auto_apply=true`
   - Or manually approve in GitHub Environments

### For CI/CD Integration

The workflow can be triggered from CI pipelines or orchestration tools:

```bash
gh workflow run terraform-phase2-final-plan-apply.yml \
  -f auto_apply=false \
  -f varfile_source=github-secrets
```

## Workflow Design Decisions

### 1. **Separate Plan and Apply Jobs**
- Allows for human review between jobs
- Plan artifacts preserved for audit
- Apply requires GitHub Environments approval

### 2. **Credential Handling**
- AWS creds fetched via existing reusable workflow (`fetch-aws-creds-from-gsm.yml`)
- GCP creds passed through environment secrets
- No credentials stored in workflow files

### 3. **Variable Management**
- Supports two sources: GitHub Secrets or MinIO
- Secrets never logged; masked in workflow output
- Template `.tfvars` provided for operators

### 4. **Audit Trail**
- Plan files uploaded to MinIO with timestamps
- Plan summaries stored in GitHub artifacts (30-day retention)
- All actions logged with `::group::` and `::notice::` markers

### 5. **Safety Guards**
- Validation step ensures critical variables are set
- Concurrency controls prevent race conditions
- Apply locked to `main` branch and production environment
- Plan file integrity verified before apply

## Integration with Existing Workflows

Reuses existing infrastructure:
- ✅ `.github/workflows/fetch-aws-creds-from-gsm.yml` — AWS credential retrieval
- ✅ `.github/scripts/resilience.sh` — Retry logic
- ✅ `scripts/minio/` — MinIO upload/download utilities
- ✅ `terraform/` directory structure — Existing modules and state

**No breaking changes** to existing workflows.

## Pre-Requisites Met

Per issue #220:

- [x] **Requirement:** Full repository-level terraform plan with secrets populated
  - ✅ Workflow runs `terraform plan` on entire repository root
  - ✅ Variables sourced from GitHub Secrets or MinIO

- [x] **Requirement:** Secure variable handling (runner_token, VPC IDs, etc.)
  - ✅ Secrets masked in logs
  - ✅ Variables never committed to git
  - ✅ Terraform marked `runner_token` as sensitive

- [x] **Requirement:** Audit trail and plan artifacts
  - ✅ Plan files uploaded to MinIO with timestamps
  - ✅ GitHub Actions artifacts retained for 30 days
  - ✅ Plan summaries available for review

- [x] **Requirement:** Optional automatic apply with manual approval
  - ✅ `auto_apply` flag controls behavior
  - ✅ Apply job requires GitHub Environments approval
  - ✅ Apply locked to production environment and main branch

- [x] **Requirement:** CI-friendly error handling and reporting
  - ✅ Comprehensive logging with groups
  - ✅ Failure detection and error messages
  - ✅ Artifact uploads on success/failure

## What to Do Next

### Operator Actions
1. **Configure GitHub Secrets** (see guide above)
2. **Review terraform code** in `terraform/` directory
3. **Run the workflow** with `auto_apply=false` first
4. **Inspect plan artifacts** for any unexpected changes
5. **Approve and apply** if plan is verified

### Additional EnhancementsTo Consider
- [ ] Add Slack notifications on plan completion
- [ ] Create GitHub Issue from plan summary automatically
- [ ] Implement terraform cost estimation (via Infracost)
- [ ] Add drift detection scheduled task
- [ ] Create automated rollback workflow

## Testing the Workflow

**Quick validation** (without actual apply):

```bash
# 1. Create test branch
git checkout -b test/terraform-phase2

# 2. Trigger workflow from test branch
gh workflow run terraform-phase2-final-plan-apply.yml \
  -f auto_apply=false \
  --ref test/terraform-phase2

# 3. Check logs
gh run list --workflow=terraform-phase2-final-plan-apply.yml

# 4. Download and verify plan
gh run download -n terraform-phase2-plan
cat terraform-phase2-*.tfplan | terraform show -
```

## Security Considerations

✅ **Implemented:**
- Secrets masked in GitHub Actions logs
- Credentials passed via environment variables (not command line)
- Apply job restricted to main branch
- Approval required via GitHub Environments
- Plan files stored with audit trail
- No hardcoded credentials in workflow files

🔐 **Operator Responsibility:**
- Keep `runner_token` rotated (quarterly minimum)
- Monitor GitHub Actions audit logs
- Verify plan before applying
- Store state backups securely
- Use Workload Identity (GCP) over static service accounts

## Issue Resolution

✅ **Issue #220 Resolved**
- Workflow created per specification
- Operator guide provided
- Secure variable handling implemented
- Audit trail and artifact management configured
- Ready for Phase 2 finalization

---

**Files Created/Modified:**
- ✅ `.github/workflows/terraform-phase2-final-plan-apply.yml` (new)
- ✅ `TERRAFORM_PHASE2_PLAN_APPLY_GUIDE.md` (new)

**Workflow Status:** Ready for production use  
**Last Updated:** March 7, 2026

