# PHASE P4 DEPLOYMENT OPERATIONS GUIDE

**Last Updated**: 2026-03-05  
**Status**: Ready for Operations Execution Phase  
**Target Date**: By 2026-03-06  

---

## 📋 EXECUTIVE SUMMARY

Phase P4 AWS Spot deployment is **infrastructure-ready**. All code, Terraform, and CI/CD automation are complete and merged into `main`. 

**What's Done**:
- ✅ Terraform infrastructure (ASG, Lambda, lifecycle management)
- ✅ GitHub Actions CI workflows (plan & apply)
- ✅ AWS secrets & OIDC integration
- ✅ KEDA smoke-test automation
- ✅ Post-deployment validation scripts

**What Ops Must Do** (Estimated 2-3 hours total):
1. Add GitHub repository secrets (AWS credentials)
2. Fill Terraform variables with real AWS values
3. Approve and run Terraform plan workflow
4. Approve and run Terraform apply workflow
5. Validate runners are online and accepting jobs

**Blocking Issues** (Must resolve before proceeding):
- 🔴 #362 — GitHub Actions billing needs resolution (blocks all CI)
- 🔴 #343 — Staging cluster offline (blocks KEDA smoke-test only)
- 🟡 #342 — GitHub Actions dispatch API returns 500 (workaround: use GitHub UI)

---

## 🚀 QUICK START (for Ops)

### Phase 1: Add GitHub Secrets (5 minutes)
Go to https://github.com/kushin77/self-hosted-runner/settings/secrets/actions

Add these secrets:
```
Name: AWS_ROLE_TO_ASSUME
Value: arn:aws:iam::YOUR_ACCOUNT_ID:role/terraform-executor-role

Name: AWS_REGION
Value: us-east-1  # or your preferred region
```

### Phase 2: Update Terraform Variables (10 minutes)
Edit: `.terraform/examples/aws-spot/terraform.tfvars`

Update these lines with YOUR AWS account values:
```hcl
vpc_id = "vpc-YOUR_VPC_ID"  # Replace with your VPC

subnet_ids = [
  "subnet-YOUR_SUBNET_1",   # Replace with real subnet IDs
  "subnet-YOUR_SUBNET_2",   # At least 2 for HA
]
```

Commit and push to `main`:
```bash
git add terraform/examples/aws-spot/terraform.tfvars
git commit -m "ops: configure aws-spot tfvars for production"
git push origin main
```

### Phase 3: Run Terraform Plan (automated)
✅ The plan workflow will auto-trigger after tfvars merge
- Go to: https://github.com/kushin77/self-hosted-runner/actions/workflows/p4-aws-spot-deploy-plan.yml
- View the plan artifact
- Review for 3-5 minutes to ensure ASG, Lambda, roles look correct
- **Approve if plan looks good** (if environment approval required)

### Phase 4: Run Terraform Apply (manual)
⚙️ Once plan is approved:
- Go to: https://github.com/kushin77/self-hosted-runner/actions/workflows/p4-aws-spot-apply.yml
- Click **Run Workflow**
- Wait 5-10 minutes for Terraform to apply
- Check logs for any errors

### Phase 5: Validate Runners (10 minutes)
After apply completes:

**1. Check AWS Console**:
```bash
# View ASG
aws ec2 describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?Tags[?Key==`ManagedBy` && Value==`terraform`]]' \
  --region us-east-1
```

**2. Check GitHub Runners**:
- Go to: https://github.com/kushin77/self-hosted-runner/settings/actions/runners
- Should see 2-5 new runners labeled `self-hosted`
- Status should be "online" ✅

**3. Run Smoke Test**:
- Create a test PR with this workflow trigger:
```yaml
name: Test on Spot Runners
on: [pull_request]
jobs:
  test:
    runs-on: self-hosted  # Will run on new spot runners
    steps:
      - run: echo "✅ Spot runner works!"
```

---

## 📊 CURRENT STATUS

| Component | Status | Details |
|-----------|--------|---------|
| **Code** | ✅ Done | All merged into `main` |
| **Terraform** | ✅ Done | Infrastructure defined in `terraform/` |
| **CI/CD** | ✅ Done | Workflows in `.github/workflows/` |
| **GitHub Secrets** | 🔴 **NEEDED** | Must add AWS_ROLE_TO_ASSUME & AWS_REGION |
| **TFvars** | 🟡 **NEEDS VPC/SUBNET** | Placeholder values in terraform.tfvars |
| **Staging Kubeconfig** | 🔴 **BLOCKED** | Issue #326 - cluster offline (for smoke-test only) |
| **GitHub Billing** | 🔴 **BLOCKED** | Issue #362 - must fix first |

---

## 🔧 DETAILED RUNBOOK

### Step 1: Prepare AWS Credentials

**Prerequisites**:
- Access to AWS account where runners will be deployed
- Ability to create IAM roles and policies
- Terraform permissions (EC2, ASG, Lambda, SNS, SQS, IAM)

**Create Terraform Executor Role**:
```bash
# Option A: Use existing CI/CD role
# Option B: Create dedicated role
aws iam create-role --role-name github-actions-terraform \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::ACCOUNT_ID:oid c:GitHub.com"},
      "Action": "sts:AssumeRoleWithWebIdentity"
    }]
  }'

# Attach admin policy (or least-privilege policy)
aws iam attach-role-policy --role-name github-actions-terraform \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Get the role ARN:
```bash
aws iam get-role --role-name github-actions-terraform \
  --query 'Role.Arn' --output text
# Output: arn:aws:iam::123456789012:role/github-actions-terraform
```

### Step 2: Add Secrets to GitHub

Go to: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions/new

| Secret Name | Value | Source |
|---|---|---|
| `AWS_ROLE_TO_ASSUME` | `arn:aws:iam::123456789012:role/github-actions-terraform` | From Step 1 |
| `AWS_REGION` | `us-east-1` | Your region choice |

### Step 3: Identify VPC & Subnets

```bash
# List VPCs
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[*].[VpcId,Tags]'

# List subnets in a VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --region us-east-1 --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]'
```

Choose 2-3 subnets across different AZs for HA.

### Step 4: Update terraform.tfvars

File: `terraform/examples/aws-spot/terraform.tfvars`

```hcl
# Update these values
vpc_id = "vpc-0a1b2c3d4e5f6g7h8"  # Your VPC ID

subnet_ids = [
  "subnet-0123456789abcdef0",  # Subnet 1 (AZ-a)
  "subnet-0fedcba987654321",   # Subnet 2 (AZ-b)
]

# Optional: uncomment to use SSH key
# key_name = "github-runners-key"

# Optional: leave blank unless using webhook secrets
# webhook_secret_arn = ""

# Instance configuration (defaults shown; adjust if needed)
# instance_type = "t3.medium"
# desired_capacity = 2
# min_size = 1
# max_size = 10
# enable_lifecycle_handler = true
```

Commit:
```bash
git add terraform/examples/aws-spot/terraform.tfvars
git commit -m "ops: configure aws-spot terraform variables"
git push origin main
```

### Step 5: Run Terraform Plan

The plan workflow should auto-trigger after pushing tfvars.

**Manual trigger** (if needed):
```bash
gh workflow run p4-aws-spot-deploy-plan.yml -r main
```

Or via GitHub UI: https://github.com/kushin77/self-hosted-runner/actions/workflows/p4-aws-spot-deploy-plan.yml

**What to expect**:
- Runs on GitHub-hosted runner
- ~2 min execution time
- Generates artifact: `aws-spot.plan.txt`
- Shows Terraform plan with resources to create

**Review the plan**:
- Look for: ASG creation, Lambda function, SNS topic, IAM role
- No errors or warnings
- Instance count matches desired_capacity
- Security groups properly configured

### Step 6: Approve Terraform Apply

Once plan looks good:

```bash
gh workflow run p4-aws-spot-apply.yml -r main \
  --ref main
```

Or via GitHub UI: https://github.com/kushin77/self-hosted-runner/actions/workflows/p4-aws-spot-apply.yml

**Environment Approval**:
- Workflow will pause for `prod-terraform-apply` environment approval
- Approve in GitHub UI or via comments
- Apply will proceed automatically

**What to expect**:
- 5-10 minutes for Terraform to apply
- Creates:
  - EC2 Launch Template
  - Auto Scaling Group
  - Lambda function (if enabled)
  - SNS/SQS topics
  - IAM role & instance profile

### Step 7: Validate Deployment

**Check AWS Resources**:
```bash
# Get ASG details
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "aws-spot-runner-asg-*" \
  --region us-east-1

# Get running instances
aws ec2 describe-instances \
  --filters "Name=tag:ManagedBy,Values=terraform" \
  --region us-east-1 \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]'

# Get Lambda function
aws lambda list-functions --region us-east-1 | grep -i spot
```

**Check GitHub Runners**:
```bash
# Via CLI
gh api repos/kushin77/self-hosted-runner/actions/runners \
  --query '.runners[*].[name,status,labels]'

# Or via UI: https://github.com/kushin77/self-hosted-runner/settings/actions/runners
```

Expected:
- 2-5 runners appearing as "online"
- Labels: `self-hosted, linux` (or your config)

**Run Smoke Test**:

Option A: Trigger via KEDA (if staging cluster available):
```bash
gh workflow run keda-smoke-test.yml -r main --ref main -f use_real_cluster=true
```

Option B: Simple test job:
```bash
# Create test-runner.yml in .github/workflows/
name: Test Self-Hosted Runner
on: [workflow_dispatch]
jobs:
  test:
    runs-on: self-hosted
    steps:
      - name: Check Environment
        run: |
          echo "✅ Runner: $(hostname)"
          echo "✅ User: $(whoami)"
          echo "✅ Disk: $(df -h / | tail -1)"
```

Trigger: `gh workflow run test-runner.yml -r main`

---

## 🚨 BLOCKED ISSUES (Resolve Before/After)

### 🔴 #362: GitHub Actions Billing Limit

**Impact**: All GitHub Actions workflows blocked  
**Status**: External (GitHub account issue)  
**Action**: 
- Go to: https://github.com/account/billing/overview
- Review recent charges and payment method
- Update payment or increase spending limit
- Retry workflows after resolution

**Workaround**: None; must fix billing first

---

### 🔴 #343: Staging Cluster Offline

**Impact**: KEDA smoke-test cannot run (optional, post-deployment)  
**Status**: Ops infrastructure issue  
**Action**:
```bash
# Verify cluster is running
ssh admin@192.168.168.42 systemctl status k3s

# If down, start it
ssh admin@192.168.168.42 systemctl start k3s

# Verify connectivity
kubectl cluster-info --kubeconfig ~/.kube/config
```

**Workaround**: Use simple test job instead (see Step 7 above)

---

### 🟡 #342: GitHub Actions Dispatch API Returns 500

**Impact**: Cannot trigger workflows via API (workaround available)  
**Status**: GitHub platform issue (transient)  
**Action**:
- Retry dispatch requests
- If persists >1 hour, check: https://www.githubstatus.com/

**Workaround**: Trigger workflows via GitHub UI or `git push` with trigger conditions

---

## 📈 POST-DEPLOYMENT MONITORING

After runners are online:

### Daily Checks
- [ ] ASG metrics in CloudWatch
- [ ] Lambda invocations (if lifecycle enabled)
- [ ] Spot instance pricing changes
- [ ] Any failed workflows with error logs

### Weekly Checks
- [ ] Spot savings estimate
- [ ] Cost trend (ensure within budget)
- [ ] Runner health (all statuses "online")
- [ ] Job execution times (compare to old runners)

### Cost Tracking
```bash
# Get current ASG capacity
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[0].[DesiredCapacity,RunningInstances]'

# Estimate monthly cost (spot instances are ~60-80% cheaper)
# Example: t3.medium
# - On-demand: ~$30/month per instance
# - Spot: ~$9/month per instance (70% savings)
```

---

## ✅ ACCEPTANCE CRITERIA

This deployment is **COMPLETE** when:

- [ ] AWS resources created (ASG, Lambda, SNS validated)
- [ ] 2+ runners online in GitHub Settings
- [ ] Smoke test job executed successfully on spot runner
- [ ] CloudWatch logs show no errors for 30+ minutes
- [ ] Team acknowledges readiness for production traffic

---

## 🔄 ROLLBACK PROCEDURE

If issues found after deployment:

```bash
# Option 1: Destroy via Terraform (clean)
cd terraform/examples/aws-spot/
terraform destroy -auto-approve

# Option 2: Kill ASG (immediate)
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "aws-spot-runner-asg-prod" \
  --force-delete \
  --region us-east-1

# Option 3: Workflow trigger
gh workflow run p4-aws-spot-destroy.yml -r main
```

Post-rollback:
- Remove GitHub secrets
- Revert tfvars to placeholder values
- Create issue with rootcause
- Plan remediation

---

## 📞 ESCALATION CONTACTS

| Role | Contact | Responsibilities |
|------|---------|------------------|
| **Ops Lead** | @kushin77 | Approve deployment, manage AWS account |
| **DevOps Eng** | @kushin77 | Debug CI/CD issues, Terraform support |
| **On-Call** | PagerDuty | Critical production issues |
| **GitHub Support** | support@github.com | GitHub API/Actions issues |

---

## 📚 REFERENCE LINKS

- [Terraform AWS Spot Module](../terraform/modules/aws_spot_runner)
- [CI/CD Workflows](.github/workflows/p4-aws-spot-*.yml)
- [Deployment Readiness Checklist](PHASE_P4_DEPLOYMENT_READINESS.md)
- [AWS Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)

---

**Document Status**: ✅ Ready for Ops Execution  
**Last Verified**: 2026-03-05 by @KushinirDev  
**Next Review**: After first deployment complete
