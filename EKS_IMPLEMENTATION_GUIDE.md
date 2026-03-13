# EKS Multi-Cloud Secrets Integration - Complete Implementation Guide

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Infrastructure Setup](#phase-1-infrastructure-setup)
4. [Phase 2: Terraform Deployment](#phase-2-terraform-deployment)
5. [Phase 3: CSI Driver Configuration](#phase-3-csi-driver-configuration)
6. [Phase 4: Secret Providers Setup](#phase-4-secret-providers-setup)
7. [Phase 5: Application Deployment](#phase-5-application-deployment)
8. [Phase 6: Verification & Testing](#phase-6-verification--testing)
9. [Production Monitoring](#production-monitoring)
10. [Disaster Recovery](#disaster-recovery)

---

## Architecture Overview

### System Components

```
┌──────────────────────────────────────────────────────────────────┐
│                     AWS EKS Cluster                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Control Plane                                           │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ • Kubernetes API Server                                 │   │
│  │ • etcd (state storage)                                  │   │
│  │ • Scheduler, Controller Manager                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Data Plane (Worker Nodes)                               │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ ┌────────────┐ Node 1                                  │   │
│  │ │ Kubelet    │                                          │   │
│  │ │ CSI Plugin │────────────┐                             │   │
│  │ │ Workloads  │            │                             │   │
│  │ └────────────┘            │                             │   │
│  │                           │                             │   │
│  │ ┌────────────┐ Node 2     │                             │   │
│  │ │ Kubelet    │            │                             │   │
│  │ │ CSI Plugin │────────────┼─────────────────┐           │   │
│  │ │ CronJob    │            │                 │           │   │
│  │ └────────────┘            │                 │           │   │
│  │                           │                 │           │   │
│  │ ┌────────────┐ Node 3     │                 │           │   │
│  │ │ Kubelet    │            │                 │           │   │
│  │ │ CSI Plugin │────────────┘                 │           │   │
│  │ └────────────┘                              │           │   │
│  │                                             │           │   │
│  └─────────────────────────────────────────────┼───────────┘   │
│                                                │               │
│  ┌────────────────────────────────────────────┴────────────┐   │
│  │ OIDC Provider (IRSA)                                    │   │
│  │ Federated identity for AWS API access                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
         │                    │                      │
         ▼                    ▼                      ▼
    ┌──────────┐        ┌──────────┐         ┌─────────────┐
    │  Vault   │        │   GSM    │         │ AWS Secrets │
    │ Instance │        │ Provider │         │  Manager    │
    │          │        │          │         │             │
    │ Secrets: │        │ Secrets: │         │ Secrets:    │
    │ - DB     │        │ - DB     │         │ - API Keys  │
    │ - API    │        │ - API    │         │ - Creds     │
    │ - S3     │        │ - S3     │         │ - S3 Keys   │
    └──────────┘        └──────────┘         └─────────────┘
         │                    │                      │
         └────────────────────┼──────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   S3 Bucket      │
                    │  (Archival)      │
                    │                  │
                    │ Data Format:     │
                    │ - JSON Lines     │
                    │ - Timestamps     │
                    │ - Checksums      │
                    └──────────────────┘
```

### Data Flow

1. **CronJob Execution**: Scheduled every 6 hours
2. **Secret Mount**: CSI driver injects secrets into pod memory
3. **IRSA Authentication**: Service account assumes IAM role
4. **AWS API Access**: Pod can call AWS services (S3, Secrets Manager)
5. **Data Processing**: Application processes and transforms data
6. **Archive Upload**: Data archived to S3 with encryption
7. **Audit Logging**: All operations logged to CloudWatch

---

## Prerequisites

### AWS Account Setup

```bash
# Required permissions
- EKS cluster creation
- VPC/Subnet management
- EC2 security groups
- IAM roles and policies
- S3 bucket access
- Secrets Manager access
- CloudWatch logs
- OIDC provider management
```

### Tools Required

```bash
# Local development machine
aws-cli >= 2.13.0
terraform >= 1.5.0
kubectl >= 1.29.0
helm >= 3.12.0
git >= 2.40.0

# On worker node
docker (for image management)
aws-cli >= 2.13.0
curl >= 7.68.0
jq >= 1.6
```

### Environment Variables

```bash
# AWS Configuration
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"
export AWS_PROFILE="default"

# EKS Configuration
export CLUSTER_NAME="milestone-organizer-eks"
export VPC_ID="vpc-xxxxx"

# Secret Management
export VAULT_ADDRESS="https://vault.example.com"
export VAULT_NAMESPACE="admin"
export GCP_PROJECT_ID="your-project-id"

# Deployment Configuration
export S3_BUCKET="milestone-organizer-archive"
export CONTAINER_IMAGE="milestone-organizer:latest"
```

---

## Phase 1: Infrastructure Setup

### 1.1 Create VPC and Subnets

```bash
# Create VPC with private and public subnets
aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=eks-vpc}]'

# Create public subnets (for ALB/NAT)
aws ec2 create-subnet --vpc-id vpc-xxxxx --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-public-1a}]'

# Create private subnets (for nodes)
aws ec2 create-subnet --vpc-id vpc-xxxxx --cidr-block 10.0.11.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-private-1a}]'
```

### 1.2 Configure S3 Bucket for Archival

```bash
# Create bucket with encryption
aws s3api create-bucket \
  --bucket $S3_BUCKET \
  --region $AWS_REGION

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $S3_BUCKET \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $S3_BUCKET \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Enable object lock (if needed)
aws s3api put-object-lock-configuration \
  --bucket $S3_BUCKET \
  --object-lock-configuration 'ObjectLockEnabled=Enabled,Rule={DefaultRetention={Mode=GOVERNANCE,Years=1}}'
```

### 1.3 Create Secrets (GSM, Vault, AWS Secrets Manager)

**Vault (using Vault CLI):**

```bash
# Login to Vault
vault login -method=userpass username=admin

# Create database secrets
vault kv put secret/milestone-organizer/db \
  username="org_admin" \
  password="$(openssl rand -base64 32)"

# Create API key
vault kv put secret/milestone-organizer/api \
  key="$(openssl rand -hex 32)"

# Create S3 credentials
vault kv put secret/milestone-organizer/s3 \
  access_key="AKIA..." \
  secret_key="..."
```

**Google Secret Manager:**

```bash
# Set project
gcloud config set project $GCP_PROJECT_ID

# Create secrets
gcloud secrets create milestone-organizer-db-password \
  --replication-policy="automatic" \
  --data-file=- <<< "$(openssl rand -base64 32)"

gcloud secrets create milestone-organizer-api-key \
  --replication-policy="automatic" \
  --data-file=- <<< "$(openssl rand -hex 32)"
```

**AWS Secrets Manager:**

```bash
# Create database secret
aws secretsmanager create-secret \
  --name milestone-organizer/db \
  --secret-string '{
    "username": "org_admin",
    "password": "'$(openssl rand -base64 32)'"
  }'

# Create API key secret
aws secretsmanager create-secret \
  --name milestone-organizer/api \
  --secret-string '{"key": "'$(openssl rand -hex 32)'"}'
```

---

## Phase 2: Terraform Deployment

### 2.1 Configure Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
# AWS Configuration
region = "us-east-1"

# EKS Configuration
cluster_name    = "milestone-organizer-eks"
cluster_version = "1.29"
vpc_id          = "vpc-xxxxx"
subnet_ids      = ["subnet-xxxxx", "subnet-yyyyy"]
private_subnet_ids = [
  "subnet-private-1-xxxxx",
  "subnet-private-2-yyyyy",
  "subnet-private-3-zzzzz"
]

# Node Group Configuration
node_group_name  = "primary"
desired_size     = 3
min_size         = 1
max_size         = 10
instance_types   = ["t3.xlarge"]
disk_size        = 100
enable_ssm_access = true

# Secrets Configuration
vault_address    = "https://vault.example.com"
vault_namespace  = "admin"
enable_secrets_store_csi = true
csi_driver_version = "v1.3.4"

# Tags
tags = {
  Environment = "production"
  Team        = "platform"
  Project     = "milestone-organizer"
  ManagedBy   = "terraform"
}
```

### 2.2 Deploy EKS Cluster

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=eks-cluster.plan

# Review plan output carefully
cat eks-cluster.plan

# Apply configuration
terraform apply eks-cluster.plan

# Wait for cluster to be ready (5-10 minutes)
aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
```

### 2.3 Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region $AWS_REGION \
  --name $CLUSTER_NAME

# Verify cluster access
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

---

## Phase 3: CSI Driver Configuration

### 3.1 Verify Helm Installation

```bash
# Check installed charts
helm list -n kube-system

# Verify CSI driver
kubectl get csidriver
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
```

### 3.2 Troubleshoot CSI Driver Issues

```bash
# Check driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver -f

# Verify driver installation
kubectl get daemonset -n kube-system -l app=secrets-store-csi-driver

# Test CSI functionality
kubectl run -it --rm csi-test \
  --image=alpine:latest \
  -n default \
  -- sh
```

---

## Phase 4: Secret Providers Setup

### 4.1 Deploy Vault Provider

```bash
# Create SecretProviderClass for Vault
cat > /tmp/vault-provider.yaml <<'EOF'
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-database-secrets
  namespace: cron-jobs
spec:
  provider: vault
  parameters:
    vaultAddress: $VAULT_ADDRESS
    vaultNamespace: $VAULT_NAMESPACE
    vaultRole: milestone-organizer
    vaultKubernetesMountPath: kubernetes
    secretPath: secret/data/milestone-organizer
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/milestone-organizer/db"
        secretKey: "password"
      - objectName: "db-username"
        secretPath: "secret/data/milestone-organizer/db"
        secretKey: "username"
EOF

# Apply with environment variable substitution
envsubst < /tmp/vault-provider.yaml | kubectl apply -f -

# Verify
kubectl get secretproviderclass -n cron-jobs
```

### 4.2 Deploy GSM Provider

```bash
# Create SecretProviderClass for GSM
cat > /tmp/gsm-provider.yaml <<'EOF'
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: gsm-database-secrets
  namespace: cron-jobs
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-db-password/versions/latest"
        path: "db-password"
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-db-username/versions/latest"
        path: "db-username"
EOF

envsubst < /tmp/gsm-provider.yaml | kubectl apply -f -
```

---

## Phase 5: Application Deployment

### 5.1 Deploy CronJob

```bash
# Run deployment script on worker node
bash /home/akushnir/self-hosted-runner/deploy/milestone-organizer-deploy-and-test.sh
```

### 5.2 Configure IRSA Annotations

```bash
# Verify IRSA annotation on service account
kubectl get sa milestone-organizer -n cron-jobs -o yaml | grep role-arn

# Should see annotation:
# eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/...
```

---

## Phase 6: Verification & Testing

### 6.1 Run Verification Script

```bash
# Run on local machine
bash /home/akushnir/self-hosted-runner/verify-eks-cluster.sh $CLUSTER_NAME $AWS_REGION
```

### 6.2 Manual Verification Tests

```bash
# Test 1: Secret access from pod
kubectl run -it --rm secret-test \
  --image=alpine:latest \
  -n cron-jobs \
  -- sh

# Inside pod:
cat /mnt/secrets-vault/db-password
cat /mnt/secrets-gsm/db-password

# Test 2: IRSA role assumption
kubectl run -it --rm iam-test \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- sts get-caller-identity

# Test 3: S3 access
kubectl run -it --rm s3-test \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- s3 ls s3://$S3_BUCKET/
```

### 6.3 Monitor Initial Job Execution

```bash
# Watch CronJob execution
kubectl get cronjobs -n cron-jobs -w

# Monitor job progress
kubectl get jobs -n cron-jobs -w

# View pod logs
kubectl logs -f -n cron-jobs milestone-organizer-<timestamp>

# Check S3 archival
aws s3 ls s3://$S3_BUCKET/milestone-organizer/ --recursive
```

---

## Production Monitoring

### 7.1 CloudWatch Health Dashboard

```bash
# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
  --dashboard-name milestone-organizer-eks \
  --dashboard-body file:///tmp/dashboard.json
```

### 7.2 Alerting Configuration

```bash
# Create SNS topic for alerts
aws sns create-topic --name milestone-organizer-alerts

# Create alarm for failed jobs
aws cloudwatch put-metric-alarm \
  --alarm-name milestone-organizer-job-failures \
  --alarm-description "Alert on CronJob failures" \
  --metric-name NumberOfFailedJobs \
  --namespace AWS/EKS \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:region:account:milestone-organizer-alerts"
```

### 7.3 Log Analysis

```bash
# Query CloudWatch logs
aws logs filter-log-events \
  --log-group-name /aws/eks/$CLUSTER_NAME \
  --filter-pattern "[ERROR, WARN]" \
  --start-time $(date -d '1 hour ago' +%s)000

# Subscribe to real-time logs
aws logs tail /aws/eks/$CLUSTER_NAME --follow
```

---

## Disaster Recovery

### 8.1 Backup Strategy

```bash
# Backup cluster configuration
kubectl get all --all-namespaces -o yaml > /tmp/cluster-backup.yaml

# Backup ETCD
aws eks describe-cluster --name $CLUSTER_NAME > /tmp/cluster-config.json

# Backup S3 archival
aws s3 sync s3://$S3_BUCKET /tmp/s3-backup
```

### 8.2 Rollback Procedure

```bash
# If deployment fails, rollback step-by-step:

# 1. Delete CronJob
kubectl delete cronjob milestone-organizer -n cron-jobs

# 2. Delete SecretProviderClasses
kubectl delete secretproviderclass --all -n cron-jobs

# 3. Drain nodes gracefully
kubectl drain <node-name> --ignore-daemonsets

# 4. If needed, destroy cluster
terraform destroy -auto-approve
```

---

## Next Steps

1. **Production Hardening**: Add network policies, pod security policies
2. **Advanced Observability**: Deploy Prometheus/Grafana/Jaeger
3. **GitOps Integration**: Use ArgoCD or Flux for continuous deployment
4. **Cost Optimization**: Implement Karpenter for improved autoscaling
5. **Disaster Recovery Testing**: Regular DR drills and backups
6. **Security Scanning**: Container image scanning, SIEM integration
7. **Compliance**: RBAC auditing, PCI-DSS, HIPAA if needed

---

## Contact & Support

For issues or questions:
- Review [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- Check [Kubernetes documentation](https://kubernetes.io/docs/)
- Review [Vault documentation](https://www.vaultproject.io/docs/)
- Check [AWS Support Center](https://console.aws.amazon.com/support/)
