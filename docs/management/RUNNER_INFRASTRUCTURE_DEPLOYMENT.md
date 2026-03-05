# Runner Infrastructure Deployment Guide

## Overview

This guide covers the infrastructure provisioning, configuration, and deployment of self-hosted GitHub Actions runners for Production.

## Architecture

```
┌──────────────────────────────┐
│  GitHub.com                  │
│  (Runner Registration API)   │
└──────────────┬───────────────┘
               │ (API calls)
               │
┌──────────────┴───────────────────────────────────────────┐
│                    AWS VPC (Isolated)                    │
│                                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Runner Instances (Standard + High-Memory)         │  │
│  │  - Ubuntu 22.04 LTS  (per tier)                   │  │
│  │  - IAM Roles (scoped)                             │  │
│  │  - Security Group (SSH blocked, HTTPS allowed)    │  │
│  │  - EBS volumes (encrypted)                        │  │
│  └────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │  CloudWatch Monitoring (Retention: 30 days)      │  │
│  │  - Health metrics                                 │  │
│  │  - Error logs                                     │  │
│  │  - Performance data                               │  │
│  └────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

## Prerequisites

### AWS Account
- VPC with subnets in 2+ availability zones
- IAM permissions (EC2, CloudWatch, Systems Manager)
- S3 bucket for Terraform state (recommended)

### Tools
- Terraform >= 1.0
- AWS CLI configured with credentials
- GitHub org/repo admin access

## Deployment Steps

### 1. Prepare Terraform Variables

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region       = "us-east-1"
project_name     = "elevatediq-runners"
environment      = "prod"
vpc_id           = "vpc-abc123..."     # Your VPC
subnet_ids       = ["subnet-x1", ...]  # Private subnets
runner_count     = 4                   # Total runners
runner_token     = "ghr_xxxx..."       # GitHub action runner token
github_owner     = "your-org"
github_repo      = "your-repo"
```

### 2. Initialize Terraform

```bash
terraform init
terraform plan  # Review changes
```

### 3. Apply Configuration

```bash
terraform apply
```

Output will include runner IP addresses and security group IDs.

### 4. Verify Deployment

```bash
# Check runner health
./scripts/validate-deployment.sh

# View CloudWatch logs
aws logs tail /aws/ec2/runners --follow
```

### 5. Register Runners with GitHub

Runners auto-register when launched via the user data script. To verify:

```bash
# GitHub UI: Settings → Actions → Runners
# CLI:
gh api repos/{owner}/{repo}/actions/runners
```

## Configuration

### Runner Tiers

**Standard Runners** (for unit tests, linting):
- Instance Type: `t3.medium` (2 vCPU, 4GB)
- Count: 60% of total
- Storage: 20GB

**High-Memory Runners** (for builds, E2E):
- Instance Type: `r5.xlarge` (4 vCPU, 32GB)
- Count: 40% of total  
- Storage: 200GB

### Security Configuration

**Inbound Rules:**
- SSH: Disabled (managed only via Terraform)

**Outbound Rules:**
- HTTPS (443): All destinations
- DNS (53): All destinations
- NTP (123): All destinations

### Monitoring & Alerts

Enable CloudWatch alarms (via Terraform):

```bash
TF_VAR_enable_alarms=true terraform apply
```

Alarms notify on:
- Runner down (no heartbeat > 5 min)
- Disk usage > 90%
- Memory usage > 95%
- Excessive failed jobs

## Operations

### Scale Up/Down

```bash
terraform apply -var="runner_count=8"
```

### Update AMI

```bash
terraform destroy
# Edit module for new AMI
terraform apply
```

### Emergency Restart

```bash
aws ec2 reboot-instances --instance-ids <id>
```

### View Logs

```bash
aws logs tail /aws/ec2/runners --follow
```

## Troubleshooting

### Runner Not Registering

1. Check user data logs on EC2 instance:
   ```bash
   ssh ubuntu@<runner-ip> "tail -100 /var/log/cloud-init-output.log"
   ```

2. Verify runner token is valid and not expired

3. Check network routing (must reach github.com:443)

### Runner Stops Running Jobs

1. Check disk space: `aws ssm start-session --target <instance-id>`
2. Restart runner service: `systemctl restart actions-runner`
3. Check GitHub API rate limits

### High CPU/Memory Usage

1. Identify stuck job: `ps aux | grep runner`
2. Kill stuck process or restart instance
3. Implement job timeout policies in workflows

## Cost Optimization

- Use Spot instances (50-70% savings) for non-critical workloads
- Schedule runners to scale down during off-hours
- Monitor CloudWatch for resource waste

## Backup & Recovery

Terraform state is your source of truth:

```bash
# Backup state file
aws s3 cp terraform.tfstate s3://backup-bucket/

# Recreate infrastructure
terraform destroy
terraform apply
```

## See Also

- [Health Monitoring](./RUNNER_HEALTH_MONITORING_SYSTEM.md)
- [Governance Policies](../governance/runners.md)
- [AWS Best Practices](https://aws.amazon.com/articles/best-practices-for-github-actions/)
