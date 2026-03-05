# Deploying Runners on AWS EC2

## Overview

This guide walks through deploying self-provisioning runners on AWS EC2 using cloud-init. Runners bootstrap in < 5 minutes and self-heal automatically.

## Prerequisites

- AWS account with EC2 launch permissions
- GitHub Personal Access Token (PAT) with `admin:self_hosted_runner` scope
- SSH key pair for EC2 access
- (Optional) VPC and security group configured

## Step 1: Create Launch Template

Create a reusable launch template with cloud-init bootstrap script:

```bash
#!/usr/bin/env bash
# create-launch-template.sh

TEMPLATE_NAME="github-actions-runner-template"
GITHUB_TOKEN="ghr_xxxxxxxxxxxxxxxx"  # PAT with admin:self_hosted_runner scope
RUNNER_URL="https://github.com/YOUR_ORG"
RUNNER_LABELS="aws,ec2,linux,docker"

# Cloud-init user-data script (inline)
read -r -d '' CLOUD_INIT <<'EOF' || true
#!/bin/bash
set -euo pipefail

# Bootstrap runner from GitHub repo
git clone https://github.com/YOUR_ORG/self-hosted-runner /opt/runner-platform
cd /opt/runner-platform/bootstrap

export RUNNER_TOKEN="${RUNNER_TOKEN}"
export RUNNER_URL="${RUNNER_URL}"
export RUNNER_LABELS="${RUNNER_LABELS}"
export RUNNER_HOME="/opt/actions-runner"

sudo bash bootstrap.sh

# Enable auto-healing and update daemons
sudo bash setup-daemons.sh

echo "✓ Runner bootstrap complete"
EOF

# Create launch template
aws ec2 create-launch-template \
  --launch-template-name "${TEMPLATE_NAME}" \
  --version-description "GitHub Actions self-hosted runner" \
  --launch-template-data '{
    "ImageId": "ami-XXXXXXXX",  # Ubuntu 22.04 LTS
    "InstanceType": "t3.large",
    "IamInstanceProfile": {
      "Name": "github-runner-role"
    },
    "SecurityGroupIds": ["sg-XXXXXXXX"],
    "UserData": "'$(echo "${CLOUD_INIT}" | base64 -w0)'",
    "TagSpecifications": [{
      "ResourceType": "instance",
      "Tags": [
        {"Key": "Name", "Value": "github-actions-runner"},
        {"Key": "Environment", "Value": "production"},
        {"Key": "ManagedBy", "Value": "terraform"}
      ]
    }],
    "Monitoring": {"Enabled": true},
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/sda1",
      "Ebs": {
        "VolumeSize": 100,
        "VolumeType": "gp3",
        "DeleteOnTermination": true,
        "Encrypted": true
      }
    }]
  }'

echo "✓ Launch template created: ${TEMPLATE_NAME}"
```

## Step 2: Create IAM Role

Runners need permissions for EC2, CloudWatch, and Secrets Manager:

```bash
#!/usr/bin/env bash
# create-iam-role.sh

ROLE_NAME="github-runner-role"
POLICY_NAME="github-runner-policy"

# Trust policy
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name "${ROLE_NAME}" \
  --assume-role-policy-document file:///tmp/trust-policy.json

# Permission policy
cat > /tmp/policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:github/runner/token*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach policy
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "${POLICY_NAME}" \
  --policy-document file:///tmp/policy.json

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name "${ROLE_NAME}"

aws iam add-role-to-instance-profile \
  --instance-profile-name "${ROLE_NAME}" \
  --role-name "${ROLE_NAME}"

echo "✓ IAM role created: ${ROLE_NAME}"
```

## Step 3: Store Token in Secrets Manager

```bash
#!/usr/bin/env bash
# store-token.sh

GITHUB_TOKEN="ghr_xxxxxxxxxxxxxxxx"
SECRET_NAME="github/runner/token"

aws secretsmanager create-secret \
  --name "${SECRET_NAME}" \
  --description "GitHub Actions runner PAT" \
  --secret-string "{\"token\":\"${GITHUB_TOKEN}\"}" \
  --add-replica-regions "Region=us-west-2" \
  --kms-key-id alias/aws/secretsmanager

echo "✓ Token stored in Secrets Manager: ${SECRET_NAME}"
```

## Step 4: Launch Runners (Auto Scaling Group)

```bash
#!/usr/bin/env bash
# launch-runners.sh

ASG_NAME="github-actions-runners"
DESIRED_CAPACITY=5
MIN_SIZE=1
MAX_SIZE=20

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${ASG_NAME}" \
  --launch-template LaunchTemplateName=github-actions-runner-template \
  --min-size "${MIN_SIZE}" \
  --max-size "${MAX_SIZE}" \
  --desired-capacity "${DESIRED_CAPACITY}" \
  --vpc-zone-identifier "subnet-XXXXXXXX,subnet-YYYYYYYY" \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --tags "Key=Name,Value=github-runner,PropagateAtLaunch=true" \
           "Key=Environment,Value=production,PropagateAtLaunch=true"

# Create scaling policies
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "${ASG_NAME}" \
  --policy-name "scale-up" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    }
  }'

echo "✓ Auto Scaling Group created: ${ASG_NAME}"
```

## Step 5: Monitoring & Alerts

```bash
#!/usr/bin/env bash
# create-alarms.sh

ASG_NAME="github-actions-runners"
SNS_TOPIC="arn:aws:sns:us-east-1:ACCOUNT:github-runner-alerts"

# High CPU utilization
aws cloudwatch put-metric-alarm \
  --alarm-name "${ASG_NAME}-high-cpu" \
  --alarm-description "Alert on high CPU in runner ASG" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions "Name=AutoScalingGroupName,Value=${ASG_NAME}" \
  --alarm-actions "${SNS_TOPIC}"

# Runner health failures
aws cloudwatch put-metric-alarm \
  --alarm-name "${ASG_NAME}-health-failures" \
  --alarm-description "Alert on runner health check failures" \
  --metric-name HealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --dimensions "Name=AutoScalingGroupName,Value=${ASG_NAME}" \
  --alarm-actions "${SNS_TOPIC}"

echo "✓ CloudWatch alarms created"
```

## Step 6: Verify Deployment

```bash
#!/usr/bin/env bash
# verify.sh

# List running instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=github-runner" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,State.Name]' \
  --output table

# Check runner registration (in GitHub)
echo "Check runners in GitHub:"
echo "  Organization: Settings → Actions → Runners"
echo "  Repository: Settings → Actions → Runners"

# SSH into a runner
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=github-runner" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "SSH access:"
echo "  aws ssm start-session --target ${INSTANCE_ID}"
echo "  ssh -i key.pem ec2-user@PUBLIC_IP"
```

## Monitoring & Troubleshooting

### CloudWatch Metrics

- `CPUUtilization` — CPU usage per runner
- `NetworkIn/Out` — Network traffic
- `DiskFreeUtilization` — Available disk space

### CloudWatch Logs

```bash
# View bootstrap logs
aws logs tail /aws/ec2/runner-bootstrap --follow

# View runner logs
aws logs tail /var/log/runner-bootstrap.log --follow
```

### SSH Debugging

```bash
# Connect to runner instance
aws ssm start-session --target i-0123456789abcdef

# Check runner status
sudo systemctl status actions-runner.service

# View bootstrap log
sudo tail -f /var/log/runner-bootstrap.log

# Manual health check
sudo bash /opt/runner-platform/scripts/health-check.sh
```

## Cleanup

```bash
#!/usr/bin/env bash
# cleanup.sh

# Delete Auto Scaling Group
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name github-actions-runners \
  --force-delete

# Terminate instances
aws ec2 terminate-instances --instance-ids "i-XXXXXXXX" "i-YYYYYYYY"

# Delete launch template
aws ec2 delete-launch-template \
  --launch-template-name github-actions-runner-template

# Delete IAM role
aws iam delete-instance-profile \
  --instance-profile-name github-runner-role
aws iam delete-role-policy \
  --role-name github-runner-role \
  --policy-name github-runner-policy
aws iam delete-role --role-name github-runner-role

echo "✓ All resources cleaned up"
```

## Cost Optimization

- Use Spot Instances for non-critical workloads (up to 70% savings)
- Schedule scale-down during off-hours
- Use smaller instance types (t3.medium) for simple jobs
- Cache Docker images to reduce build time

## Security Best Practices

1. **Restrict security group** — Only allow HTTPS outbound
2. **Use VPC endpoints** — For GitHub API, CloudWatch, Secrets Manager
3. **Enable EBS encryption** — Default in account settings
4. **Audit logs** — Enable CloudTrail for all API calls
5. **Rotate tokens** — Refresh PAT regularly
6. **Network isolation** — Private subnets with NAT gateway

## References

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/)
- [Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [CloudWatch Alarms](https://docs.aws.amazon.com/cloudwatch/)
