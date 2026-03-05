# P4 AWS Spot Deployment Readiness Checklist

This document provides a comprehensive checklist for deploying Phase P4 aws-spot self-hosted runners with spot-interruption lifecycle Lambda handler.

## Pre-Deployment (Ops)

- [ ] **AWS Credentials Configured**
  - [ ] `AWS_ROLE_TO_ASSUME` secret added to GitHub repository (ARN of role for CI to assume)
  - [ ] `AWS_REGION` secret added to GitHub repository (e.g., `us-east-1`)
  - [ ] Role has permissions for: EC2, ASG, Lambda, SNS, SQS, Secrets Manager, IAM

- [ ] **Terraform Variables Prepared**
  - [ ] `terraform/examples/aws-spot/terraform.tfvars` merged with real values:
    - [ ] `vpc_id` populated (VPC to launch runners in)
    - [ ] `subnet_ids` populated (at least 2 subnets for HA, preferably across AZs)
    - [ ] `key_name` set if SSH access needed (optional)
    - [ ] `webhook_secret_arn` set if using Secrets Manager webhook (optional)

- [ ] **Environment Protection**
  - [ ] GitHub environment `prod-terraform-apply` is protected
  - [ ] Approvers assigned to `prod-terraform-apply` environment
  - [ ] Required reviewers configured for apply workflow

- [ ] **Network & Security**
  - [ ] Security group ingress/egress rules reviewed (if using custom SG)
  - [ ] NAT gateway or route to internet available for runner outbound connections
  - [ ] Private/public subnet configuration matches intent

## Deployment (CI/CD)

- [ ] **Plan Workflow Runs**
  - [ ] Trigger or wait for `p4-aws-spot-deploy-plan.yml` to run (auto-triggers on tfvars merge)
  - [ ] Review plan artifact `aws-spot.plan.txt` for:
    - [ ] ASG creation with correct instance type/desired capacity
    - [ ] Launch template with user-data/spot options
    - [ ] Lambda function creation (if `enable_lifecycle_handler=true`)
    - [ ] SNS/SQS topic creation for lifecycle events
    - [ ] IAM role creation with least-privilege policy
  - [ ] Approval step passes without errors

- [ ] **Apply Workflow**
  - [ ] Trigger `p4-aws-spot-apply.yml` workflow
  - [ ] Wait for apply to complete (typically 3-5 minutes)
  - [ ] Verify no errors in workflow run logs
  - [ ] Check that apply completed successfully

## Post-Deployment Validation

- [ ] **AWS Resources Created**
  - [ ] Check AWS Console → EC2 → Auto Scaling Groups:
    - [ ] ASG named with `aws-spot-runner` created
    - [ ] Desired capacity matches configuration
    - [ ] Instances launching (may see mix of on-demand + spot)
  - [ ] Check EC2 → Instances:
    - [ ] Runners appear with correct tags/names
    - [ ] Runners are in "running" state
    - [ ] User-data logs show runner registration (check system logs)

- [ ] **Lambda Lifecycle Handler (if enabled)**
  - [ ] Lambda function appears in AWS Console → Lambda
  - [ ] Function has correct IAM role attached
  - [ ] EventBridge rule created for EC2 spot-termination notices
  - [ ] SNS topic created for notifications
  - [ ] SQS queue created for termination messages

- [ ] **Health & Connectivity**
  - [ ] Navigate to repo Settings → Actions → Runners
    - [ ] New self-hosted runners appear as "online"
    - [ ] Runners are accepting jobs (run a test workflow)
  - [ ] Test a workflow job on the new runners:
    - [ ] Create a simple test PR or push to a test branch
    - [ ] Verify job runs on self-hosted runner (logs show runner name)
    - [ ] Job completes successfully

- [ ] **Monitoring**
  - [ ] CloudWatch metrics available for runners:
    - [ ] ASG lifecycle events
    - [ ] Spot instance interruptions (if any)
    - [ ] Lambda invocations (if enabled)
  - [ ] SNS topic receives test message (can publish manually if needed)

- [ ] **Cost Verification**
  - [ ] AWS Billing → Cost Anomaly Detection enabled (optional but recommended)
  - [ ] Spot pricing savings estimated (typically 60-80% cheaper than on-demand)

## Rollback (If Issues)

- [ ] **Immediate Rollback**
  - [ ] In GitHub Actions, trigger `p4-aws-spot-destroy.yml` workflow (if available)
  - [ ] Or manually run: `terraform destroy -auto-approve` from `terraform/examples/aws-spot/`
  - [ ] Verify ASG deleted and instances terminated

- [ ] **Post-Rollback**
  - [ ] Remove secrets if they were temporary
  - [ ] Delete tfvars file or revert to placeholder
  - [ ] Notify team of rollback reason
  - [ ] Create issue to track remediation

## Success Criteria

✅ Deployment is successful when:
1. ASG exists and has instances running
2. Runners appear online in GitHub Settings → Actions
3. At least one test workflow runs successfully on self-hosted runner
4. No unplanned Lambda errors in CloudWatch logs
5. Cost monitoring set up (optional but recommended)

## Support & Escalation

- **Terraform Errors**: See `docs/PHASE_P4_AWS_SPOT_VERIFICATION.md`
- **Runner Registration Issues**: Check runner registration token, network connectivity
- **Spot Interruptions**: Expected behavior; Lambda should handle gracefully (if enabled)
- **Cost Overages**: Review ASG desired capacity, instance type, spot vs on-demand mix
