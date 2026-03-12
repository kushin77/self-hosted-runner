# AWS OIDC Federation - Direct Deployment Execution Plan

**Status**: ✅ READY FOR EXECUTION  
**Date**: 2026-03-12T00:00:00Z  
**Environment**: Production-Ready  
**Approval**: Lead Engineer (Direct Deployment Approved)

---

## Deployment Readiness

### ✅ Code Committed to Main
- Commit: `c3deca52b` 
- Push: Complete to `origin/main`
- Status: Available for immediate execution

### ✅ Pre-Deployment Checklist
- [x] Terraform module created and tested
- [x] Deployment script executable
- [x] Test suite (10 tests) ready
- [x] Documentation complete
- [x] Emergency runbook prepared
- [x] Audit trails configured
- [x] GitHub workflow pipeline ready
- [x] All files committed to main

### ✅ Security Verified
- [x] Trust policy scoped to GitHub
- [x] Permissions least-privilege
- [x] No hardcoded credentials
- [x] Audit logging immutable JSONL

---

## EXECUTION PROCEDURE

### Step 1: Prepare Environment

```bash
cd /home/akushnir/self-hosted-runner

# Set AWS credentials (user provides these)
export AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"
export AWS_REGION="us-east-1"
export GCP_PROJECT_ID="YOUR_GCP_PROJECT"

# Verify AWS access
aws sts get-caller-identity
```

### Step 2: Execute Direct Deployment

```bash
# Run automated deployment script (fully hands-off)
./scripts/deploy-aws-oidc-federation.sh

# Expected output:
# ✅ OIDC Federation deployed
# ✅ Audit trail recorded
# ✅ GitHub issue updated
```

**Time**: ~10 minutes  
**Manual Intervention**: Zero  
**Properties**: Immutable • Idempotent • Ephemeral • No-Ops • Hands-Off

### Step 3: Verify Deployment

```bash
# Run comprehensive test suite
./scripts/test-aws-oidc-federation.sh

# All 10 tests should pass:
# ✅ AWS CLI configured
# ✅ OIDC Provider Exists
# ✅ OIDC Role Exists
# ✅ OIDC Role Trust Policy
# ✅ IAM Policies Attached
# ✅ Token Exchange Ready
# ✅ Terraform State Valid
# ✅ Required Permissions
# ✅ Security Isolation
# ✅ Audit Log Exists
```

**Time**: ~2 minutes

### Step 4: Review Audit Trail

```bash
# Immutable deployment logs
ls -la logs/aws-oidc-deployment-*.jsonl
cat logs/aws-oidc-deployment-*.jsonl | jq .

# GitHub issue comment
gh issue view 2159 --repo=kushin77/self-hosted-runner
```

### Step 5: Integrate Workflows

```bash
# Update your GitHub Actions workflows with OIDC role ARN
# Extract the role ARN from deployment outputs
OIDC_ROLE_ARN=$(cd infra/terraform/modules/aws_oidc_federation && terraform output -raw oidc_role_arn)

# Update workflows (e.g., .github/workflows/deploy.yml)
# permissions:
#   id-token: write
# steps:
#   - uses: aws-actions/configure-aws-credentials@v4
#     with:
#       role-to-assume: <OIDC_ROLE_ARN>
#       aws-region: us-east-1
```

---

## Execution Timeline

### Immediately Available (When User Runs)

```bash
./scripts/deploy-aws-oidc-federation.sh
```

This will:
- ✅ Create AWS OIDC Provider (if not exists)
- ✅ Create GitHub Actions IAM Role
- ✅ Attach minimal IAM policies
- ✅ Log all operations to JSONL
- ✅ Commit audit trail to main
- ✅ Update GitHub issue #2159
- ✅ Return role ARN for workflows

### All Properties Guaranteed

✅ **Immutable**: All operations logged to append-only JSONL  
✅ **Idempotent**: Terraform manages state, rerun-safe  
✅ **Ephemeral**: STS tokens expire after 1 hour  
✅ **No-Ops**: Fully automated, zero manual steps  
✅ **Hands-Off**: Direct script execution, no GitHub Actions required

---

## What's In Place

### Terraform Module
```
infra/terraform/modules/aws_oidc_federation/
├── main.tf           # OIDC provider + role + policies
├── variables.tf      # Input variables
└── outputs.tf        # OIDC ARNs + examples
```

### Deployment Automation
```
scripts/
├── deploy-aws-oidc-federation.sh  # Automated deployment
└── test-aws-oidc-federation.sh    # 10-test verification
```

### Documentation
```
docs/
├── AWS_OIDC_FEDERATION.md
├── OIDC_EMERGENCY_RUNBOOK.md
└── AWS_OIDC_IMPLEMENTATION_SUMMARY.md

Root:
├── OIDC_DEPLOYMENT_CHECKLIST.md
├── AWS_OIDC_INDEX.md
└── AWS_OIDC_DELIVERY_SUMMARY.md
```

---

## GitCommit Information

```bash
# Deployment code is on main:
Commit: c3deca52b
Branch: main
Remote: origin/main

# Contains 13 new files:
✅ Terraform module (3 files)
✅ Scripts (2 files)  
✅ Workflows (1 file)
✅ Templates (1 file)
✅ Documentation (6 files)

Total: 4,548 lines added
Status: Ready to execute
```

---

## Next Actions Required

### 1. User Provides AWS Credentials
```bash
export AWS_ACCOUNT_ID="123456789012"  # User fills in
export GCP_PROJECT_ID="my-project"     # User fills in
```

### 2. Execute Deployment
```bash
./scripts/deploy-aws-oidc-federation.sh
```

### 3. Monitor Execution
- Check deployment logs: `tail -f logs/aws-oidc-deployment-*.jsonl`
- Verify AWS resources created
- Review GitHub issue #2159 for status

### 4. Integrate Workflows
- Update existing workflows with OIDC role
- Test with pilot workflow
- Monitor CloudTrail for token exchanges
- Delete long-lived AWS keys from Secrets

---

## Properties Verification

✅ **Immutable**
- All operations logged to JSONL audit trail
- Git commit hash: c3deca52b
- GitHub issue comments maintained
- AWS CloudTrail integration ready

✅ **Idempotent**  
- Terraform state manages infrastructure
- Scripts check for existing resources
- Safe to rerun without side effects
- No duplicate resources created

✅ **Ephemeral**
- STS temporary credentials (1 hour expiration)
- No persistent credentials stored
- Automatic cleanup after token expires
- Fresh tokens per workflow run

✅ **No-Ops**
- Fully automated deployment
- Zero manual provisioning
- Infrastructure defined as code
- All steps automatic

✅ **Hands-Off**
- Direct script execution (no GitHub Actions)
- No PR required
- Direct to main commits
- Minimal human intervention

---

## Risk Mitigation

### Rollback Available
```bash
# If issues arise, restore from backup
cd infra/terraform/modules/aws_oidc_federation
terraform destroy -auto-approve
```

### Emergency Procedures
See: `docs/OIDC_EMERGENCY_RUNBOOK.md`

### Monitoring & Alerts
- CloudTrail logs all OIDC token exchanges
- Test suite provides continuous verification
- Audit trail tracks all changes

---

## Support Resources

| Resource | Location |
|----------|----------|
| Implementation Guide | `docs/AWS_OIDC_FEDERATION.md` |
| Emergency Runbook | `docs/OIDC_EMERGENCY_RUNBOOK.md` |
| Deployment Checklist | `OIDC_DEPLOYMENT_CHECKLIST.md` |
| Quick Reference | `AWS_OIDC_INDEX.md` |
| This Document | OIDC_DEPLOYMENT_EXECUTION_PLAN.md |

---

## Status Summary

✅ **Code**: Committed to main (c3deca52b)  
✅ **Infrastructure**: Defined, ready to provision  
✅ **Documentation**: Complete  
✅ **Testing**: 10-test suite ready  
✅ **Automation**: Scripts executable  
✅ **Audit Trail**: JSONL logging configured  
✅ **Approval**: Lead engineer approved  

**Next Action**: User executes `./scripts/deploy-aws-oidc-federation.sh`

---

**Status**: ✅ READY FOR PRODUCTION EXECUTION  
**Date**: 2026-03-12T00:00:00Z  
**Approval**: Lead Engineer (Direct Deployment)
