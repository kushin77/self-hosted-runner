# Phase P4 AWS Spot Runner - Pre & Post Deployment Verification

## Pre-Deployment Checklist

### Ops Responsibilities (before running plan/apply)
- [ ] **AWS Credentials**: Configured locally or via IAM role that allows assume-role into the target AWS account
- [ ] **Repository Secrets**: Set in GitHub (Settings → Secrets)
  - [ ] `AWS_ROLE_TO_ASSUME` — Role ARN for CI runner assume-role
  - [ ] `AWS_REGION` — Target AWS region
- [ ] **Terraform Inputs**: Either
  - [ ] Create `terraform/examples/aws-spot/terraform.tfvars` with required values, OR
  - [ ] Pass variables via GitHub Actions workflow
  - Required variables:
    - [ ] `vpc_id` — VPC where runners will launch
    - [ ] `subnet_ids` — List of subnets
    - [ ] `key_name` (optional) — EC2 key pair for SSH
- [ ] **AWS Secrets Manager** (optional but recommended):
  - [ ] Create a secret containing the runner drain webhook URL
  - [ ] Note the secret ARN to provide as `webhook_secret_arn`
- [ ] **GitHub Environment Protection**:
  - [ ] Repository → Settings → Environments → create `prod-terraform-apply`
  - [ ] Add environment protection rules (require approval if multi-person)
- [ ] **Terraform Version**: >= 1.0 installed locally and in CI
- [ ] **Plan Review**: Download and review the plan artifact before apply

### Code & Configuration Checks
- [ ] Terraform files pass `terraform fmt -check`
- [ ] `terraform validate` succeeds with no errors
- [ ] Module dependencies resolved (archive, aws providers)
- [ ] Security groups / IAM policies reviewed and approved
- [ ] Lambda handler code reviewed (services/spot-lifecycle/handler.py)

## Plan Run Steps

Use the automated setup script (recommended):
```bash
cd /path/to/self-hosted-runner
./scripts/ops/p4-aws-spot-setup.sh
```

Or manually:
```bash
cd terraform/examples/aws-spot
terraform init
terraform validate
terraform plan -out=aws-spot.plan
terraform show -no-color aws-spot.plan > aws-spot.plan.txt
```

### Review Checklist
- [ ] Plan shows only expected resource creations (no unexpected deletions)
- [ ] ASG, Launch Template, SNS, SQS, Lambda resources present
- [ ] Lifecycle hook configured
- [ ] IAM roles/policies follow least-privilege
- [ ] Security group ingress/egress rules are correct
- [ ] Plan artifact uploaded/reviewed

## Apply Execution

### Via GitHub Actions (Recommended)
1. Review plan artifact details available in workflow run
2. Navigate to Workflows → p4-aws-spot-apply
3. Trigger manually (if configured)
4. Confirm at the `prod-terraform-apply` environment approval gate
5. Monitor apply logs for errors

### Via Local Terraform (Alternative)
```bash
cd terraform/examples/aws-spot
terraform apply aws-spot.plan
```

### Apply Validation
- [ ] All resources created successfully
- [ ] No errors or warnings in apply output
- [ ] Check AWS console:
  - [ ] ASG exists with correct name
  - [ ] Launch Template visible in EC2 console
  - [ ] SNS topic and SQS queue exist
  - [ ] Lambda function deployed (if enabled)
  - [ ] CloudWatch log group created for Lambda

## Post-Deployment Verification

### AWS Console Checks
- [ ] **AutoScaling Group**:
  - [ ] Desired/min/max capacity set correctly
  - [ ] Instances launching in correct subnets
  - [ ] Lifecycle hook attached and in `Wait for timeout` state
- [ ] **Launch Template**:
  - [ ] AMI ID (Ubuntu 20.04) correct
  - [ ] Instance type matches configuration
  - [ ] Key pair assigned (if configured)
- [ ] **SNS/SQS**:
  - [ ] Topic subscribed to SQS queue
  - [ ] Queue policy allows SNS publish
  - [ ] Visibility timeout and message retention configured
- [ ] **Lambda Function** (if enabled):
  - [ ] Function deployed with correct runtime (python3.11)
  - [ ] Environment variables set (RUNNER_DRAIN_WEBHOOK, etc.)
  - [ ] Execution role has permission to read Secrets Manager (if webhook secret used)
  - [ ] SQS event source mapping active

### Functional Tests
- [ ] Trigger an ASG instance termination and verify:
  - [ ] Lifecycle hook intercepts and holds instance
  - [ ] SNS message published
  - [ ] SQS message received
  - [ ] Lambda invoked (check CloudWatch logs)
  - [ ] Drain webhook called (check logs or webhook receiver)
- [ ] Verify graceful runner drain:
  - [ ] Runner finishes current jobs before shutdown
  - [ ] Terminal state reached before instance termination

### Observability Checks
- [ ] **CloudWatch Logs**:
  - [ ] Lambda logs present in `/aws/lambda/runner-lifecycle-handler` (or similar)
  - [ ] Error stack traces reviewed (should be minimal)
- [ ] **CloudWatch Metrics** (optional):
  - [ ] ASG activity visible
  - [ ] Lambda invocations and duration
- [ ] **Grafana** (if integrated):
  - [ ] ASG metrics available
  - [ ] Spot interruption events visible

### Security Validation
- [ ] **IAM Roles**:
  - [ ] Lambda role only has minimal permissions (SNS publish, Secrets Manager read)
  - [ ] ASG notification role can only publish to specific SNS topic
- [ ] **Secrets**:
  - [ ] Webhook URL not logged or exposed in plaintext
  - [ ] Secrets Manager secret ARN correct
  - [ ] Lambda fetches secret at runtime (confirmed in logs)
- [ ] **Network**:
  - [ ] Security groups restrict unnecessary inbound traffic
  - [ ] NAT/routing allows Lambda → webhook URL reach

## Rollback Plan

If issues are discovered during deployment:

1. **Pause Instances**: Manually terminate test instances or reduce ASG desired capacity to 0
2. **Disable Lifecycle Hook**: 
   ```bash
   aws autoscaling delete-lifecycle-hook --lifecycle-hook-name spot-termination-hook --auto-scaling-group-name runner-asg
   ```
3. **Review & Fix**: Address issues in code/config
4. **Destroy via Terraform**:
   ```bash
   cd terraform/examples/aws-spot
   terraform destroy
   ```
5. **Redeploy**: After fixes, run terraform plan/apply again

## Follow-up Actions

- [ ] Document any configuration customizations in PHASE_P4_OPERATIONS_DOCUMENTATION.md
- [ ] Set up monitoring/alerting for Lambda errors and ASG terminations
- [ ] Train platform team on scaling/troubleshooting procedures
- [ ] Schedule post-deployment review (1 week after go-live)

## Contacts & References

- Master Tracker Issue: #240
- Lambda Deployment Tracking: #261
- Terraform Review: #266
- Environment Protection: #268
- Plan Failures Escalation: #279
- Setup Script: `scripts/ops/p4-aws-spot-setup.sh`
- Handoff Doc: `docs/PHASE_P4_AWS_SPOT_HANDOFF.md`
